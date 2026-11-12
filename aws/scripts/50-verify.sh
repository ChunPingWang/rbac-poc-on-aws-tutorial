#!/usr/bin/env bash
# =====================================================================
# Step 6 - End-to-end verification on AWS
#   A. Edge authN (API Gateway JWT authorizer)
#   B. Token claims (Cognito groups + Pre Token Lambda tenant_id)
#   C. RBAC matrix (README 權限對照表)
#   D. /api/users/me profile
#   E. Multi-tenant isolation (multi-tenant.feature)
#   F. Audit trail (audit-lib on RDS)
#   G. Security posture (tenant self-escalation, private ALB/RDS, ECR scan)
# Output: console + $STATE_DIR/verify-report-<ts>.md
# =====================================================================
set +e
source "$(dirname "$0")/env.sh"
set +e +u

API="$(stack_output "$STACK_API" ApiEndpoint)"
POOL="$(stack_output "$STACK_IDENTITY" UserPoolId)"
CLIENT="$(stack_output "$STACK_IDENTITY" TestHarnessClientId)"
# shellcheck disable=SC1091
source "$STATE_DIR/test-users.env" || die "run 40-seed-users.sh first"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$STATE_DIR/verify-report-$TS.md"
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

{ echo "# rbac-poc-on-aws verification report"; echo; echo "- Time (UTC): $TS"; echo "- API: $API"
  echo "- User pool: $POOL"; echo; echo "| # | Case | Expected | Actual | Result |"; echo "|---|---|---|---|---|"; } > "$REPORT"
N=0
check() {  # check <case> <expected> <actual>
  N=$((N+1))
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); echo -e "  ${C_GRN}PASS${C_OFF} [$N] $1 (=$3)"; R=PASS
  else FAIL=$((FAIL+1)); echo -e "  ${C_RED}FAIL${C_OFF} [$N] $1 expected=$2 actual=$3"; R=FAIL; fi
  echo "| $N | $1 | $2 | $3 | $R |" >> "$REPORT"
}
section() { echo; echo -e "${C_BLU}== $* ==${C_OFF}"; echo "| | **$*** | | | |" >> "$REPORT"; }

token() {  # token <username> <password>
  aws cognito-idp admin-initiate-auth --user-pool-id "$POOL" --client-id "$CLIENT" \
    --auth-flow ADMIN_USER_PASSWORD_AUTH --auth-parameters "USERNAME=$1,PASSWORD=$2" \
    --query 'AuthenticationResult.AccessToken' --output text
}
claims() { python3 -c 'import sys,base64,json;p=sys.argv[1].split(".")[1];p+="="*(-len(p)%4);print(json.dumps(json.loads(base64.urlsafe_b64decode(p))))' "$1"; }
# call <METHOD> <PATH> <TOKEN|-> [JSON]  -> prints HTTP status, body in $TMP/body
call() {
  local m="$1" p="$2" t="$3" d="$4" args=(-s -o "$TMP/body" -w '%{http_code}' -X "$m" "$API$p")
  [[ "$t" != "-" ]] && args+=(-H "Authorization: Bearer $t")
  [[ -n "$d" ]] && args+=(-H 'Content-Type: application/json' -d "$d")
  curl "${args[@]}"
}
body() { cat "$TMP/body"; }

log "API endpoint: $API"
log "Getting access tokens from Cognito (ADMIN_USER_PASSWORD_AUTH via test-harness client)"
T_ADMIN="$(token admin.user "$PW_ADMIN_USER")"
T_TA="$(token tenant-a.admin "$PW_TENANT_A_ADMIN")"
T_TB="$(token tenant-b.admin "$PW_TENANT_B_ADMIN")"
T_USER="$(token normal.user "$PW_NORMAL_USER")"
T_VIEW="$(token viewer.user "$PW_VIEWER_USER")"
T_AUD="$(token auditor.user "$PW_AUDITOR_USER")"
for v in T_ADMIN T_TA T_TB T_USER T_VIEW T_AUD; do [[ -n "${!v}" && "${!v}" != None ]] || die "token $v missing"; done

# ------------------------------------------------------------------
section "A. Edge authentication (API Gateway JWT authorizer)"
check "No token GET /api/products"            401 "$(call GET /api/products -)"
check "Garbage token GET /api/products"       401 "$(call GET /api/products not.a.jwt)"
TAMPERED="$(python3 - "$T_USER" <<'PY'
import sys,base64,json
h,p,s=sys.argv[1].split(".")
d=json.loads(base64.urlsafe_b64decode(p+"="*(-len(p)%4)))
d["cognito:groups"]=["ADMIN"]; d.pop("tenant_id",None)
print(h+"."+base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")+"."+s)
PY
)"
check "Tampered token (USER→ADMIN, bad signature)" 401 "$(call GET /api/products "$TAMPERED")"
check "Unrouted path with valid token /api/nope" 404 "$(call GET /api/nope "$T_ADMIN")"

# ------------------------------------------------------------------
section "B. Token claims (Cognito groups + Pre Token Generation V2)"
C_ADMIN="$(claims "$T_ADMIN")"; C_TA="$(claims "$T_TA")"; C_USER="$(claims "$T_USER")"
check "admin token_use"                    access     "$(jq -r '.token_use' <<<"$C_ADMIN")"
check "admin cognito:groups"               ADMIN      "$(jq -r '."cognito:groups"|join(",")' <<<"$C_ADMIN")"
check "admin has no tenant_id (→ system)"  null       "$(jq -r '.tenant_id' <<<"$C_ADMIN")"
check "tenant-a.admin tenant_id claim"     tenant-a   "$(jq -r '.tenant_id' <<<"$C_TA")"
check "normal.user email claim injected"   normal.user@example.com "$(jq -r '.email' <<<"$C_USER")"
check "issuer is the Cognito pool"         "https://cognito-idp.${AWS_REGION}.amazonaws.com/${POOL}" "$(jq -r '.iss' <<<"$C_ADMIN")"

# ------------------------------------------------------------------
section "C. RBAC matrix"
NEWP='{"name":"%s","price":%s,"category":"Electronics","description":"created on AWS by %s"}'
# shellcheck disable=SC2059
check "ADMIN   POST /api/products"   201 "$(call POST /api/products "$T_ADMIN" "$(printf "$NEWP" "Admin Item" 1000 admin)")"
ADMIN_PID="$(jq -r '.data' "$TMP/body")"
check "ADMIN   GET  /api/products"   200 "$(call GET /api/products "$T_ADMIN")"
check "ADMIN   PUT  /api/products/{id}" 200 "$(call PUT "/api/products/$ADMIN_PID" "$T_ADMIN" '{"name":"Admin Item v2","price":1200}')"
check "ADMIN   GET  updated name"    "Admin Item v2" "$(call GET "/api/products/$ADMIN_PID" "$T_ADMIN" >/dev/null; jq -r '.data.name' "$TMP/body")"
check "ADMIN   DELETE /api/products/{id}" 204 "$(call DELETE "/api/products/$ADMIN_PID" "$T_ADMIN")"

# shellcheck disable=SC2059
check "TENANT_ADMIN POST /api/products" 201 "$(call POST /api/products "$T_TA" "$(printf "$NEWP" "Tenant A Item 1" 500 tenant-a.admin)")"
A1="$(jq -r '.data' "$TMP/body")"
check "TENANT_ADMIN PUT own product"    200 "$(call PUT "/api/products/$A1" "$T_TA" '{"price":550}')"
check "TENANT_ADMIN DELETE (ADMIN only)" 403 "$(call DELETE "/api/products/$A1" "$T_TA")"

check "USER   GET  /api/products"      200 "$(call GET /api/products "$T_USER")"
check "USER   POST /api/products"      403 "$(call POST /api/products "$T_USER" "$(printf "$NEWP" "Illegal" 100 user)")"
check "USER   PUT  /api/products/{id}" 403 "$(call PUT "/api/products/$A1" "$T_USER" '{"price":1}')"
check "USER   DELETE /api/products/{id}" 403 "$(call DELETE "/api/products/$A1" "$T_USER")"
check "VIEWER GET  /api/products"      200 "$(call GET /api/products "$T_VIEW")"
check "VIEWER POST /api/products"      403 "$(call POST /api/products "$T_VIEW" "$(printf "$NEWP" "Illegal" 100 viewer)")"
check "Validation: negative price → 400" 400 "$(call POST /api/products "$T_ADMIN" '{"name":"bad","price":-1}')"

# ------------------------------------------------------------------
section "D. /api/users/me (user-service)"
check "USER GET /api/users/me"         200 "$(call GET /api/users/me "$T_USER")"
check "me.username"                    normal.user "$(jq -r '.data.username' "$TMP/body")"
check "me.tenantId"                    tenant-a    "$(jq -r '.data.tenantId' "$TMP/body")"
check "me.roles contains ROLE_USER"    true        "$(jq -r '.data.roles|index("ROLE_USER")!=null' "$TMP/body")"
check "me.groups (cognito:groups)"     USER        "$(jq -r '.data.groups|join(",")' "$TMP/body")"
check "me.firstName (Lambda claim)"    Normal      "$(jq -r '.data.firstName' "$TMP/body")"

# ------------------------------------------------------------------
section "E. Multi-tenant isolation"
# shellcheck disable=SC2059
check "tenant-b.admin creates B1"      201 "$(call POST /api/products "$T_TB" "$(printf "$NEWP" "Tenant B Item 1" 800 tenant-b.admin)")"
B1="$(jq -r '.data' "$TMP/body")"
call GET '/api/products?size=200' "$T_TA" >/dev/null
check "tenant-a list contains A1"      true  "$(jq --arg id "$A1" '[.data.content[].id]|index($id)!=null' "$TMP/body")"
check "tenant-a list hides B1"         false "$(jq --arg id "$B1" '[.data.content[].id]|index($id)!=null' "$TMP/body")"
check "tenant-a list only tenant-a"    true  "$(jq '[.data.content[].tenantId]|all(.=="tenant-a")' "$TMP/body")"
call GET '/api/products?size=200' "$T_TB" >/dev/null
check "tenant-b list hides A1"         false "$(jq --arg id "$A1" '[.data.content[].id]|index($id)!=null' "$TMP/body")"
check "tenant-b GET A1 by id → 404"    404 "$(call GET "/api/products/$A1" "$T_TB")"
check "tenant-b PUT A1 by id → 404"    404 "$(call PUT "/api/products/$A1" "$T_TB" '{"price":1}')"
check "normal.user(tenant-a) GET A1"   200 "$(call GET "/api/products/$A1" "$T_USER")"
call GET '/api/products?size=200' "$T_ADMIN" >/dev/null
check "ADMIN(system) sees A1 and B1"   true "$(jq --arg a "$A1" --arg b "$B1" '[.data.content[].id] as $i|($i|index($a)!=null) and ($i|index($b)!=null)' "$TMP/body")"
check "ADMIN GET B1 by id"             200 "$(call GET "/api/products/$B1" "$T_ADMIN")"
check "B1.tenantId persisted"          tenant-b "$(jq -r '.data.tenantId' "$TMP/body")"

# ------------------------------------------------------------------
section "F. Audit trail (audit-lib → RDS PostgreSQL)"
sleep 2
check "AUDITOR GET /api/v1/audit-logs"  200 "$(call GET '/api/v1/audit-logs?username=tenant-a.admin&eventType=PRODUCT_CREATED' "$T_AUD")"
check "audit has PRODUCT_CREATED by tenant-a.admin" true "$(jq '[.content[]|select(.eventType=="PRODUCT_CREATED" and .username=="tenant-a.admin")]|length>0' "$TMP/body")"
call GET '/api/v1/audit-logs?username=admin.user&eventType=PRODUCT_DELETED' "$T_AUD" >/dev/null
check "audit has PRODUCT_DELETED by admin.user" true "$(jq '.content|length>0' "$TMP/body")"
check "USER GET audit-logs → 403"       403 "$(call GET /api/v1/audit-logs "$T_USER")"
check "TENANT_ADMIN GET audit-logs → 403" 403 "$(call GET /api/v1/audit-logs "$T_TA")"

# ------------------------------------------------------------------
section "G. Security posture"
SELF="$(aws cognito-idp update-user-attributes --access-token "$T_USER" \
        --user-attributes Name=custom:tenant_id,Value=tenant-b 2>&1)"
check "User cannot change own custom:tenant_id" denied "$( [[ "$SELF" == *"NotAuthorized"* || "$SELF" == *"unauthorized attribute"* || "$SELF" == *"InvalidParameter"* ]] && echo denied || echo allowed)"
ALB_SCHEME="$(aws elbv2 describe-load-balancers --names "$PROJECT-internal-alb" --query 'LoadBalancers[0].Scheme' --output text 2>/dev/null)"
check "ALB scheme"                    internal "$ALB_SCHEME"
check "RDS publicly accessible"       False "$(aws rds describe-db-instances --db-instance-identifier "$PROJECT-postgres" --query 'DBInstances[0].PubliclyAccessible' --output text 2>/dev/null)"
check "RDS storage encrypted"         True  "$(aws rds describe-db-instances --db-instance-identifier "$PROJECT-postgres" --query 'DBInstances[0].StorageEncrypted' --output text 2>/dev/null)"
CLUSTER="$(stack_output "$STACK_SERVICES" ClusterName)"
TASK="$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$PROJECT-product-service" --query 'taskArns[0]' --output text)"
ENI_PUB="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text \
          | xargs -I{} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null || echo error)"
check "ECS task has no public IP"     None "${ENI_PUB:-None}"
TAG="$(aws ecs describe-task-definition --task-definition "$PROJECT-product-service" --query 'taskDefinition.containerDefinitions[0].image' --output text | awk -F: '{print $NF}')"
CRIT="$(aws ecr describe-image-scan-findings --repository-name "$PROJECT/product-service" --image-id imageTag="$TAG" \
        --query 'imageScanFindings.findingSeverityCounts.CRITICAL' --output text 2>/dev/null || echo error)"
check "ECR scan: CRITICAL findings (product image)" None "${CRIT:-None}"

# ------------------------------------------------------------------
echo; echo "TOTAL: $PASS passed, $FAIL failed"
{ echo; echo "**TOTAL: $PASS passed, $FAIL failed**"; } >> "$REPORT"
log "report: $REPORT"
[[ $FAIL -eq 0 ]]
