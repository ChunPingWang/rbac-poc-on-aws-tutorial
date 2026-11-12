#!/usr/bin/env bash
# =====================================================================
# Shared settings & helpers for all rbac-poc-on-aws scripts.
# Usage: source aws/scripts/env.sh
# =====================================================================
set -euo pipefail

export PROJECT="${PROJECT:-rbac-poc}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
export CFN_DIR="$REPO_ROOT/aws/cloudformation"
export STATE_DIR="${STATE_DIR:-$HOME/.rbac-poc}"      # local, never committed
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"

# Stack names (deployer policy only allows rbac-poc-* stacks)
export STACK_BOOTSTRAP="$PROJECT-00-bootstrap-iam"
export STACK_NETWORK="$PROJECT-10-network"
export STACK_DATA="$PROJECT-20-data"
export STACK_IDENTITY="$PROJECT-30-identity"
export STACK_BUILD="$PROJECT-40-build"
export STACK_SERVICES="$PROJECT-50-services"
export STACK_API="$PROJECT-60-api"

C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[1;33m'; C_BLU='\033[0;34m'; C_OFF='\033[0m'
log()  { echo -e "${C_BLU}[$(date +%H:%M:%S)]${C_OFF} $*"; }
ok()   { echo -e "${C_GRN}[OK]${C_OFF} $*"; }
warn() { echo -e "${C_YLW}[WARN]${C_OFF} $*"; }
die()  { echo -e "${C_RED}[ERROR]${C_OFF} $*" >&2; exit 1; }

account_id() { aws sts get-caller-identity --query Account --output text; }

cfn_exec_role_arn() {
  aws cloudformation list-exports \
    --query "Exports[?Name=='${PROJECT}-cfn-exec-role-arn'].Value" --output text
}

# stack_output <stack> <OutputKey>
stack_output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

# cfn_deploy <stack> <template-file> [Key=Value ...]
# Always deploys through the CloudFormation execution role (least privilege for humans).
cfn_deploy() {
  local stack="$1" tpl="$2"; shift 2
  local role; role="$(cfn_exec_role_arn)"
  [[ -n "$role" && "$role" != "None" ]] || die "CFN execution role not found - run 00-bootstrap-iam.sh first"
  log "Deploying stack ${stack} (${tpl##*/}) via ${role##*/}"
  local params=(ProjectName="$PROJECT" "$@")
  aws cloudformation deploy \
    --stack-name "$stack" \
    --template-file "$tpl" \
    --role-arn "$role" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --tags Project="$PROJECT" ManagedBy=CloudFormation \
    --parameter-overrides "${params[@]}" \
    || { aws cloudformation describe-stack-events --stack-name "$stack" --max-items 15 \
           --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" \
           --output table; die "stack $stack failed"; }
  ok "stack ${stack} ready"
}
