#!/usr/bin/env bash
# =====================================================================
# Cleanup - delete all rbac-poc stacks in reverse dependency order.
#   ./99-cleanup.sh          workload stacks (10..60)       [deployer]
#   ./99-cleanup.sh --all    + artifact bucket + IAM bootstrap [administrator]
# =====================================================================
source "$(dirname "$0")/env.sh"
ROLE="$(cfn_exec_role_arn)"

del() {
  local s="$1"
  if aws cloudformation describe-stacks --stack-name "$s" >/dev/null 2>&1; then
    log "deleting $s"
    aws cloudformation delete-stack --stack-name "$s" ${ROLE:+--role-arn "$ROLE"}
    aws cloudformation wait stack-delete-complete --stack-name "$s" && ok "deleted $s" || die "delete failed: $s"
  else
    warn "$s not found, skipping"
  fi
}

del "$STACK_API"
del "$STACK_SERVICES"
del "$STACK_BUILD"
del "$STACK_IDENTITY"
del "$STACK_DATA"
del "$STACK_NETWORK"

if [[ "${1:-}" == "--all" ]]; then
  BUCKET="$(aws cloudformation list-exports --query "Exports[?Name=='${PROJECT}-artifact-bucket'].Value" --output text)"
  if [[ -n "$BUCKET" && "$BUCKET" != None ]]; then
    log "emptying versioned bucket $BUCKET"
    python3 - "$BUCKET" <<'PY'
import sys, json, subprocess
b = sys.argv[1]
while True:
    out = subprocess.run(["aws","s3api","list-object-versions","--bucket",b,"--max-items","500","--output","json"],
                         capture_output=True, text=True, check=True).stdout
    d = json.loads(out or "{}")
    objs = [{"Key":v["Key"],"VersionId":v["VersionId"]} for v in d.get("Versions",[])+d.get("DeleteMarkers",[])]
    if not objs: break
    subprocess.run(["aws","s3api","delete-objects","--bucket",b,"--delete",json.dumps({"Objects":objs,"Quiet":True})], check=True)
PY
  fi
  log "deleting $STACK_BOOTSTRAP (needs administrator)"
  aws cloudformation delete-stack --stack-name "$STACK_BOOTSTRAP"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK_BOOTSTRAP" && ok "bootstrap deleted"
  rm -rf "$STATE_DIR"
fi
ok "cleanup finished"
