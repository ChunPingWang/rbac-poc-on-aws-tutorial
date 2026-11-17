# 部署實錄（供教學文件引用）

| 時間 (UTC) | 身分 | 步驟 | 結果 / 備註 | 截圖 |
|---|---|---|---|---|
| 10:2x | root | 開啟 CloudShell、查身分 | 發現以 root 登入、帳號無自訂角色 | 00 |
| 10:42 | root | 手動建立 IAM user `poc-admin`、`rbac-poc-deployer`、群組 `RbacPocDeployers` | 兩個 user 皆無政策、無 MFA；root 有 1 把 access key；無密碼政策 | 01 |
| 10:5x | root | 掛 AdministratorAccess 給 poc-admin、設定密碼政策（14 碼） | 成功 | 02, 03 |
| 11:12 | poc-admin | CloudShell「動作→上傳檔案」上傳 git bundle、clone、validate-template | 成功 | 04, 05, 06 |
| 11:12 | poc-admin | `00-bootstrap-iam.sh` 第一次 | **失敗**：`AWS::IAM::Group RbacPocDeployers already exists`（手動建立的空群組同名）→ ROLLBACK_COMPLETE | 07, 08 |
| 11:16 | poc-admin | 刪除空 stack 與空群組後重跑 | 成功：CfnExecutionRole、boundary、DeployerPolicy、ForceMfaPolicy、artifact bucket；deployer 已加入群組 | 09, 10 |
| 11:30 | deployer | `01-preflight.sh` | 全部 template validate 通過 | 11, 12 |
| 11:30 | deployer | `10-deploy-foundation.sh`：network | 成功（約 2.5 分鐘，NAT Gateway 最久） | |
| 11:33 | deployer | identity stack | **失敗**：`Invalid write attributes specified while creating a client`。原因：User Pool 的 **必填屬性 (email) 必須在 App Client 的 WriteAttributes 內**。修正：WriteAttributes 加入 email（custom:tenant_id 仍不可寫） | 13 |
| 11:39 | deployer | 刪除 ROLLBACK_COMPLETE 的 identity stack、修正後重部署 identity / build | 成功（identity 約 1.5 分、build 約 1 分）；data (RDS) 仍在建立 | 14 |
| 11:42 | deployer | `20-build-images.sh`：zip 原始碼 (780 KB) → S3 → CodeBuild | 啟動 | |
| 11:44 | deployer | CodeBuild #1 | **失敗**：security-lib / user-service 測試通過；product-service 128 測試中 22 個失敗（全部 `@WebMvcTest` Controller 測試，`NoSuchBeanDefinitionException`）。查 git 歷史：`@EnableJpaRepositories` 於 e2ac84b 加到 `ProductServiceApplication`，晚於 Controller 測試，**原專案既有回歸**。修正：移到 `config/JpaConfig`。另：deployer 無 `codebuild:ListReportsForReportGroup` 權限（最小權限生效），改在 buildspec 失敗時直接印出失敗測試細節 | 15 |
| 11:52 | deployer | `30-deploy-services.sh` | ECS task 啟動失敗：`Unable to create tempDir. java.io.tmpdir is set to /tmp` / `AccessDeniedException`。原因：Fargate 的 ephemeral bind volume 預設為 root:root 0755，非 root 容器（UID 65532）無法寫入。修正：加入 init container（root、執行 `chmod 1777 /tmp` 後結束），app 容器 `DependsOn: SUCCESS`；仍維持非 root + 唯讀 root FS | 16 |
| 12:0x | deployer | 刪除 ROLLBACK_COMPLETE 的 services stack | 注意：`wait stack-rollback-complete` 不適用建立失敗（ROLLBACK_COMPLETE），會一直等待 | |
| 12:13 | deployer | 第二次部署 services | init container `tmp-ready` 成功；app 啟動失敗 `Unable to determine source type <S> and target type <T> for your Converter`（本次改造的 lambda @Bean 造成）→ 改具名類別 + 回歸測試，重新 CodeBuild | 17 |
| 12:15 | deployer | CodeBuild #4 | 成功，`TEST SUMMARY: tests=144 failures=0 errors=0 skipped=0`，image tag `20261112121507-4` | |
| 12:27 | deployer | 第三次部署 services（新 image） | 兩個服務皆啟動；user-service log 出現 `syntax error at or near "user"`：schema 名 `user` 為 PostgreSQL 保留字 → 改為 `user_service`，重新建置 | 18 |
| 12:55 | deployer | services / api 部署完成、seed 6 位使用者 | API endpoint `https://1v70386w88.execute-api.us-east-1.amazonaws.com` | 19, 20 |
| 12:56 | deployer | `50-verify.sh` 第一次 | 11 pass / 42 fail：**驗證腳本本身的 bug**（`local m=... args=(... "$m")` 同一行宣告時 `$m` 尚未賦值 → curl `-X` 空白）；另 deployer 無 `ecr:DescribeImageScanFindings` | |
| 12:58 | deployer | `50-verify.sh` 第二次 | 27 pass / 25 fail：所有 GET 由 ALB 回 400（`server: awselb/2.0`）。原因 ALB `desync_mitigation_mode=strictest` → 改 `defensive` 並 update stack | 21 |
| 13:00 | deployer | ALB 改 defensive 後 `50-verify.sh` 第三次 | **52 passed, 0 failed, 1 skipped**（ECR scan 讀取權限） | 22, 23, 24, 25 |
| 13:02–13:12 | deployer | `99-cleanup.sh`（60→10） | 全部刪除（約 10 分鐘）。殘留：bootstrap stack（IAM，免費）、artifact S3 bucket、兩個由 AWS 服務自行建立的 log group（RDS、Container Insights，0 bytes）→ 需 poc-admin 執行 `--all` | 26 |
| 13:21–13:23 | poc-admin | `99-cleanup.sh --all` + 最終檢查 | bucket、2 個 log group、bootstrap 刪除；所有資源類別檢查皆為空 | 27 |
| 13:xx（驗證後） | — | 文件與設定一致性修正 | `00-bootstrap-iam.yaml` 新增 `rbac-poc-admin-force-mfa`（強制 poc-admin 使用 MFA）、`00-bootstrap-iam.sh` 檢查呼叫者 MFA；**僅 cfn-lint 驗證，未重新部署** | |
| 2026-11-15 | poc-admin（CloudShell，無 AWS 資源） | 移除 Spring Cloud 元件與 CORS 後執行全部模組測試 | Corretto 17：350 tests / 0 failures（含 6 項改寫的契約測試、18 個 Cucumber 場景）；部署腳本僅語法檢查 | 28 |
| 2026-11-15 15:15–15:21 | poc-admin | `00-bootstrap-iam.sh`（含強制 MFA 的新版 template） | 輸出 `AdminMfaEnforcedFor = poc-admin`；`simulate-principal-policy`：MFA=true → allowed、MFA=false → explicitDeny | 29, 30 |
| 2026-11-15 15:24–15:49 | deployer | `deploy-all.sh`（第二次完整部署，已移除 Spring Cloud / CORS） | foundation → CodeBuild（144 tests / 0 failures，image `20261115153847-1`）→ 50-services；途中 CloudShell 工作階段重置使前景腳本中斷（stack 已完成），改用 `nohup` 續跑 30 → 40 → 50 | |
| 2026-11-15 15:52 | deployer | `50-verify.sh` 第一次 | 46 pass / 7 fail：API Gateway 回 503，VPC Link 仍為 PENDING → `30-deploy-services.sh` 加入等待 `AVAILABLE` | |
| 2026-11-15 15:54 | deployer | `50-verify.sh` 第二次 | **53 passed, 0 failed**；`CorsConfiguration` 為空、回應無 `Access-Control-Allow-Origin` | 31 |
| 2026-11-15 15:55–16:03 | deployer | `25-verify-local-envs.sh` 第一次 | Docker Compose 15/15、Kind 31/31 通過；mTLS 檢查失敗：帶憑證打 `:8081/actuator/health` 回 401（健康檢查在管理埠 8091，8081 需 JWT；握手其實成功）→ 修正檢查邏輯 | |
| 2026-11-15 16:07 | deployer | `25-verify-local-envs.sh` 第二次 | CodeBuild `DOWNLOAD_SOURCE` 失敗：buildspec 指令含 `通過: ` 被 YAML 解析成 mapping → 改用區塊字串 | |
| 2026-11-15 16:12–16:22 | deployer | `25-verify-local-envs.sh` 第三次 | **Docker Compose 15/15、Kind 31/31、Kind+mTLS 通過**（帶憑證 → TLS 1.3 握手、HTTP 401；不帶憑證 → 000） | 32 |
