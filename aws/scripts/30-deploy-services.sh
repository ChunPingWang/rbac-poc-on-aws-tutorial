#!/usr/bin/env bash
# Step 4 - ECS services + internal ALB, then API Gateway
source "$(dirname "$0")/env.sh"

TAG="${IMAGE_TAG:-$(cat "$STATE_DIR/image-tag" 2>/dev/null || true)}"
[[ -n "$TAG" ]] || die "no image tag - run 20-build-images.sh first"
log "Deploying image tag $TAG"
cfn_deploy "$STACK_SERVICES" "$CFN_DIR/50-services.yaml" ImageTag="$TAG" DesiredCount="${DESIRED_COUNT:-1}"
cfn_deploy "$STACK_API"      "$CFN_DIR/60-api.yaml"

CLUSTER="$(stack_output "$STACK_SERVICES" ClusterName)"
log "Waiting for ECS services to become stable"
aws ecs wait services-stable --cluster "$CLUSTER" \
  --services "$PROJECT-product-service" "$PROJECT-user-service"
ok "services stable"

# A new VPC Link stays PENDING for a few minutes after the stack completes; until it is
# AVAILABLE every request through API Gateway returns 503 (seen on 2026-11-15).
log "Waiting for API Gateway VPC Link to become AVAILABLE"
for _ in $(seq 1 40); do
  VL="$(aws apigatewayv2 get-vpc-links --query "Items[?Name=='${PROJECT}-vpclink'].VpcLinkStatus | [0]" --output text)"
  [[ "$VL" == "AVAILABLE" ]] && break
  echo "  vpc link: $VL"; sleep 15
done
[[ "$VL" == "AVAILABLE" ]] || die "VPC Link not AVAILABLE (status: $VL)"
ok "VPC Link AVAILABLE"
echo "API endpoint: $(stack_output "$STACK_API" ApiEndpoint)"
