#!/usr/bin/env bash
# =====================================================================
# Step 0 - IAM bootstrap. Run ONCE as an account ADMINISTRATOR (not root).
# Creates the CFN execution role, permissions boundary, deployer group /
# user (no password, no access key) and the artifact bucket.
# =====================================================================
source "$(dirname "$0")/env.sh"

ARN="$(aws sts get-caller-identity --query Arn --output text)"
[[ "$ARN" == *":root" ]] && die "You are signed in as ROOT. Sign in as an IAM administrator (e.g. rex-admin) instead."
log "Caller: $ARN"

DEPLOYER_USER="${DEPLOYER_USER:-rbac-poc-deployer}"
# If the deployer user was created by hand in the console, only add it to the group
if aws iam get-user --user-name "$DEPLOYER_USER" >/dev/null 2>&1 \
   && ! aws cloudformation describe-stack-resource --stack-name "$STACK_BOOTSTRAP" --logical-resource-id DeployerUser >/dev/null 2>&1; then
  USER_EXISTS=true; log "IAM user $DEPLOYER_USER already exists -> will only add it to RbacPocDeployers"
else
  USER_EXISTS=false
fi
aws cloudformation deploy \
  --stack-name "$STACK_BOOTSTRAP" \
  --template-file "$CFN_DIR/00-bootstrap-iam.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags Project="$PROJECT" ManagedBy=CloudFormation \
  --parameter-overrides ProjectName="$PROJECT" DeployerUserName="$DEPLOYER_USER" DeployerUserExists="$USER_EXISTS" AllowedRegion="$AWS_REGION"

aws cloudformation describe-stacks --stack-name "$STACK_BOOTSTRAP" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
cat <<MSG

Next (human, in the IAM console):
  1. IAM > Users > ${DEPLOYER_USER} > Security credentials > Enable console access (custom password)
  2. Assign an MFA device to ${DEPLOYER_USER}
  3. Sign out and sign in as ${DEPLOYER_USER} (MFA), open CloudShell in ${AWS_REGION}
MSG
