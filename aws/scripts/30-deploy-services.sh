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
echo "API endpoint: $(stack_output "$STACK_API" ApiEndpoint)"
