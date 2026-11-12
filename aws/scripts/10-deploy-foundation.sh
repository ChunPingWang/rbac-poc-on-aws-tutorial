#!/usr/bin/env bash
# Step 2 - network, database, identity, build pipeline (≈ 15 min, RDS is the long pole)
source "$(dirname "$0")/env.sh"

cfn_deploy "$STACK_NETWORK"  "$CFN_DIR/10-network.yaml"  NatGatewayCount="${NAT_COUNT:-1}"
# identity & build do not depend on RDS -> deploy RDS in background to save time
cfn_deploy "$STACK_DATA"     "$CFN_DIR/20-data.yaml" &
DATA_PID=$!
cfn_deploy "$STACK_IDENTITY" "$CFN_DIR/30-identity.yaml"
cfn_deploy "$STACK_BUILD"    "$CFN_DIR/40-build.yaml"
wait "$DATA_PID" || die "data stack failed"
ok "foundation ready"
