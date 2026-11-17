#!/usr/bin/env bash
# Optional - 在 CodeBuild 內驗證「非 AWS」部署路徑（Docker Compose / Kind / Kind+mTLS）
# 前置：已執行 20-build-images.sh（S3 上已有 source zip、40-build stack 已存在）
# 不推送任何 image；只在 CodeBuild 容器內起服務、測試、拆除。
source "$(dirname "$0")/env.sh"

PROJECT_NAME="$(stack_output "$STACK_BUILD" BuildProjectName)"
BUCKET="$(aws cloudformation list-exports --query "Exports[?Name=='${PROJECT}-artifact-bucket'].Value" --output text)"

# 以目前的工作目錄重新打包（不影響 20-build-images.sh 使用的 source zip）
ZIP="$STATE_DIR/rbac-poc-local-verify.zip"
rm -f "$ZIP"
( cd "$REPO_ROOT" && zip -qr "$ZIP" . \
    -x '.git/*' '*/build/*' 'build/*' '.gradle/*' '*/bin/*' '*.class' '*/node_modules/*' )
aws s3 cp "$ZIP" "s3://$BUCKET/source/rbac-poc-local-verify.zip" --only-show-errors

BUILD_ID="$(aws codebuild start-build --project-name "$PROJECT_NAME" \
  --source-type-override S3 \
  --source-location-override "$BUCKET/source/rbac-poc-local-verify.zip" \
  --buildspec-override aws/codebuild/buildspec-local-verify.yml \
  --timeout-in-minutes-override 90 \
  --query build.id --output text)"
log "CodeBuild (local-env verify) started: $BUILD_ID"
while :; do
  read -r STATUS PHASE < <(aws codebuild batch-get-builds --ids "$BUILD_ID" \
     --query 'builds[0].[buildStatus,currentPhase]' --output text)
  echo "  status=$STATUS phase=$PHASE"
  [[ "$STATUS" != "IN_PROGRESS" ]] && break
  sleep 30
done

aws logs filter-log-events --log-group-name "/aws/codebuild/${PROJECT}-build" \
  --log-stream-names "${BUILD_ID#*:}" --filter-pattern '"VERIFY SUMMARY"' \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' | grep -E '^VERIFY SUMMARY' | sed 's/^/  /'
[[ "$STATUS" == "SUCCEEDED" ]] || die "local-env verify $STATUS - see log stream ${BUILD_ID#*:} in /aws/codebuild/${PROJECT}-build"
ok "Docker Compose / Kind / Kind+mTLS 驗證全部通過"
