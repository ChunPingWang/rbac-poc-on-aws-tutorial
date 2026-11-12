#!/usr/bin/env bash
# One-shot: preflight -> foundation -> build -> services -> seed -> verify
set -euo pipefail
D="$(dirname "$0")"
"$D/01-preflight.sh"
"$D/10-deploy-foundation.sh"
"$D/20-build-images.sh"
"$D/30-deploy-services.sh"
"$D/40-seed-users.sh"
"$D/50-verify.sh"
