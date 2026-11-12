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
