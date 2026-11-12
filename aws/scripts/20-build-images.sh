#!/usr/bin/env bash
# Step 3 - package source -> S3 -> CodeBuild (tests + images) -> ECR
source "$(dirname "$0")/env.sh"

BUCKET="$(aws cloudformation list-exports --query "Exports[?Name=='${PROJECT}-artifact-bucket'].Value" --output text)"
PROJECT_NAME="$(stack_output "$STACK_BUILD" BuildProjectName)"
ZIP="$STATE_DIR/rbac-poc-source.zip"

log "Packaging source from $REPO_ROOT"
rm -f "$ZIP"
( cd "$REPO_ROOT" && zip -qr "$ZIP" . \
    -x '.git/*' '*/build/*' 'build/*' '.gradle/*' '*/bin/*' '*.class' '*/node_modules/*' )
ls -lh "$ZIP"
aws s3 cp "$ZIP" "s3://$BUCKET/source/rbac-poc-source.zip" --only-show-errors
ok "uploaded to s3://$BUCKET/source/rbac-poc-source.zip"

BUILD_ID="$(aws codebuild start-build --project-name "$PROJECT_NAME" --query build.id --output text)"
log "CodeBuild started: $BUILD_ID"
while :; do
  read -r STATUS PHASE < <(aws codebuild batch-get-builds --ids "$BUILD_ID" \
     --query 'builds[0].[buildStatus,currentPhase]' --output text)
  echo "  status=$STATUS phase=$PHASE"
  [[ "$STATUS" != "IN_PROGRESS" ]] && break
  sleep 20
done
[[ "$STATUS" == "SUCCEEDED" ]] || die "build $STATUS - see CloudWatch log group /aws/codebuild/${PROJECT}-build"

TAG="$(aws codebuild batch-get-builds --ids "$BUILD_ID" \
        --query "builds[0].exportedEnvironmentVariables[?name=='IMAGE_TAG'].value" --output text)"
echo "$TAG" > "$STATE_DIR/image-tag"
ok "images pushed with tag $TAG (saved to $STATE_DIR/image-tag)"
# Unit-test summary is printed by buildspec into the build log (deployer has no codebuild report read rights)
aws logs filter-log-events --log-group-name "/aws/codebuild/${PROJECT}-build" \
  --log-stream-names "${BUILD_ID#*:}" --filter-pattern '"TEST SUMMARY: tests="' \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' | grep -E 'tests=[0-9]' | sed 's/^/  /'
