#!/usr/bin/env bash
# =====================================================================
# Step 5 - create test users in Cognito (replaces OpenLDAP bootstrap.ldif)
# Random strong passwords are generated per run and stored ONLY in
# $STATE_DIR/test-users.env (chmod 600, never committed).
# =====================================================================
source "$(dirname "$0")/env.sh"

POOL="$(stack_output "$STACK_IDENTITY" UserPoolId)"
OUT="$STATE_DIR/test-users.env"
: > "$OUT"; chmod 600 "$OUT"

#        username         group         tenant     given   family
USERS=(
  "admin.user          ADMIN         -          Admin   User"
  "tenant-a.admin      TENANT_ADMIN  tenant-a   TenantA Admin"
  "tenant-b.admin      TENANT_ADMIN  tenant-b   TenantB Admin"
  "normal.user         USER          tenant-a   Normal  User"
  "viewer.user         VIEWER        tenant-a   Viewer  User"
  "auditor.user        AUDITOR       -          Auditor User"
)

gen_pw() { echo "Rb@$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)9z"; }

for row in "${USERS[@]}"; do
  read -r U G T GN FN <<<"$row"
  ATTRS=(Name=email,Value="${U}@example.com" Name=email_verified,Value=true
         Name=given_name,Value="$GN" Name=family_name,Value="$FN")
  [[ "$T" != "-" ]] && ATTRS+=(Name=custom:tenant_id,Value="$T")

  if aws cognito-idp admin-get-user --user-pool-id "$POOL" --username "$U" >/dev/null 2>&1; then
    log "update $U"
    aws cognito-idp admin-update-user-attributes --user-pool-id "$POOL" --username "$U" --user-attributes "${ATTRS[@]}"
  else
    log "create $U ($G, tenant=$T)"
    aws cognito-idp admin-create-user --user-pool-id "$POOL" --username "$U" \
      --message-action SUPPRESS --user-attributes "${ATTRS[@]}" >/dev/null
  fi
  PW="$(gen_pw)"
  aws cognito-idp admin-set-user-password --user-pool-id "$POOL" --username "$U" --password "$PW" --permanent
  aws cognito-idp admin-add-user-to-group --user-pool-id "$POOL" --username "$U" --group-name "$G"
  VAR="PW_$(echo "$U" | tr '.-' '__' | tr '[:lower:]' '[:upper:]')"
  printf '%s=%q\n' "$VAR" "$PW" >> "$OUT"
done
ok "seeded ${#USERS[@]} users; passwords stored in $OUT (600)"
aws cognito-idp list-users --user-pool-id "$POOL" \
  --query 'Users[].[Username,UserStatus,Attributes[?Name==`custom:tenant_id`]|[0].Value]' --output table
