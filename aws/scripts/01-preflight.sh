#!/usr/bin/env bash
# Step 1 - sanity checks before deploying
source "$(dirname "$0")/env.sh"

ARN="$(aws sts get-caller-identity --query Arn --output text)"
log "Caller : $ARN"
log "Region : $AWS_REGION"
[[ "$ARN" == *":root" ]] && die "Do not deploy as root."
[[ "$(aws configure get region || echo "$AWS_REGION")" == "$AWS_REGION" ]] || warn "CLI default region differs; using $AWS_REGION"

ROLE="$(cfn_exec_role_arn)"; [[ -n "$ROLE" && "$ROLE" != None ]] || die "Bootstrap stack missing"
ok "CFN execution role: $ROLE"
BUCKET="$(aws cloudformation list-exports --query "Exports[?Name=='${PROJECT}-artifact-bucket'].Value" --output text)"
ok "Artifact bucket   : $BUCKET"
for t in "$CFN_DIR"/*.yaml; do
  aws cloudformation validate-template --template-body "file://$t" >/dev/null && ok "valid: ${t##*/}"
done
for c in jq zip curl; do command -v $c >/dev/null || die "missing tool: $c"; done
ok "preflight passed"
