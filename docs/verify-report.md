# rbac-poc-on-aws 驗證報告

- 執行時間 (UTC)：**2026-11-15 15:54:48**（第二次完整部署：移除 Spring Cloud 與 CORS 之後）
- 執行身分：`rbac-poc-deployer`（CloudShell, us-east-1）
- Image tag：`20261115153847-1`
- 單元測試（CodeBuild）：`TEST SUMMARY: tests=144 failures=0 errors=0 skipped=0`
- 結果：**53 passed, 0 failed**（第 53 項 ECR 掃描在第一次部署時因權限不足 SKIP，template 補權限後本次 PASS）
- CORS 移除檢查：`CorsConfiguration` 為空；帶 `Origin` 的請求回應不含 `Access-Control-Allow-Origin`（截圖 [31](images/31-aws-verify-53-no-cors.jpg)）
- 前一次結果（2026-11-12 13:00:40 UTC，image `20261112123407-5`）：52 passed, 0 failed, 1 skipped

> 第一次在 2026-11-15 執行 `50-verify.sh` 時有 7 項因 **API Gateway VPC Link 仍為 PENDING** 回傳 503；
> 等 VPC Link 變成 `AVAILABLE` 後重跑全數通過。`30-deploy-services.sh` 已加入等待 VPC Link 的步驟（見 README §10）。

| # | Case | Expected | Actual | Result |
|---|---|---|---|---|
| | **A. Edge authentication (API Gateway JWT authorizer)** | | | |
| 1 | No token GET /api/products | 401 | 401 | PASS |
| 2 | Garbage token GET /api/products | 401 | 401 | PASS |
| 3 | Tampered token (USER→ADMIN, bad signature) | 401 | 401 | PASS |
| 4 | Unrouted path with valid token /api/nope | 404 | 404 | PASS |
| | **B. Token claims (Cognito groups + Pre Token Generation V2)** | | | |
| 5 | admin token_use | access | access | PASS |
| 6 | admin cognito:groups | ADMIN | ADMIN | PASS |
| 7 | admin has no tenant_id (→ system) | null | null | PASS |
| 8 | tenant-a.admin tenant_id claim | tenant-a | tenant-a | PASS |
| 9 | normal.user email claim injected | normal.user@example.com | normal.user@example.com | PASS |
| 10 | issuer is the Cognito pool | https://cognito-idp.us-east-1.amazonaws.com/us-east-1_63rEU… | https://cognito-idp.us-east-1.amazonaws.com/us-east-1_63rEU… | PASS |
| | **C. RBAC matrix** | | | |
| 11 | ADMIN POST /api/products | 201 | 201 | PASS |
| 12 | ADMIN GET /api/products | 200 | 200 | PASS |
| 13 | ADMIN PUT /api/products/{id} | 200 | 200 | PASS |
| 14 | ADMIN GET updated name | Admin Item v2 | Admin Item v2 | PASS |
| 15 | ADMIN DELETE /api/products/{id} | 204 | 204 | PASS |
| 16 | TENANT_ADMIN POST /api/products | 201 | 201 | PASS |
| 17 | TENANT_ADMIN PUT own product | 200 | 200 | PASS |
| 18 | TENANT_ADMIN DELETE (ADMIN only) | 403 | 403 | PASS |
| 19 | USER GET /api/products | 200 | 200 | PASS |
| 20 | USER POST /api/products | 403 | 403 | PASS |
| 21 | USER PUT /api/products/{id} | 403 | 403 | PASS |
| 22 | USER DELETE /api/products/{id} | 403 | 403 | PASS |
| 23 | VIEWER GET /api/products | 200 | 200 | PASS |
| 24 | VIEWER POST /api/products | 403 | 403 | PASS |
| 25 | Validation: negative price → 400 | 400 | 400 | PASS |
| | **D. /api/users/me (user-service)** | | | |
| 26 | USER GET /api/users/me | 200 | 200 | PASS |
| 27 | me.username | normal.user | normal.user | PASS |
| 28 | me.tenantId | tenant-a | tenant-a | PASS |
| 29 | me.roles contains ROLE_USER | true | true | PASS |
| 30 | me.groups (cognito:groups) | USER | USER | PASS |
| 31 | me.firstName (Lambda claim) | Normal | Normal | PASS |
| | **E. Multi-tenant isolation** | | | |
| 32 | tenant-b.admin creates B1 | 201 | 201 | PASS |
| 33 | tenant-a list contains A1 | true | true | PASS |
| 34 | tenant-a list hides B1 | false | false | PASS |
| 35 | tenant-a list only tenant-a | true | true | PASS |
| 36 | tenant-b list hides A1 | false | false | PASS |
| 37 | tenant-b GET A1 by id → 404 | 404 | 404 | PASS |
| 38 | tenant-b PUT A1 by id → 404 | 404 | 404 | PASS |
| 39 | normal.user(tenant-a) GET A1 | 200 | 200 | PASS |
| 40 | ADMIN(system) sees A1 and B1 | true | true | PASS |
| 41 | ADMIN GET B1 by id | 200 | 200 | PASS |
| 42 | B1.tenantId persisted | tenant-b | tenant-b | PASS |
| | **F. Audit trail (audit-lib → RDS PostgreSQL)** | | | |
| 43 | AUDITOR GET /api/v1/audit-logs | 200 | 200 | PASS |
| 44 | audit has PRODUCT_CREATED by tenant-a.admin | true | true | PASS |
| 45 | audit has PRODUCT_DELETED by admin.user | true | true | PASS |
| 46 | USER GET audit-logs → 403 | 403 | 403 | PASS |
| 47 | TENANT_ADMIN GET audit-logs → 403 | 403 | 403 | PASS |
| | **G. Security posture** | | | |
| 48 | User cannot change own custom:tenant_id | denied | denied | PASS |
| 49 | ALB scheme | internal | internal | PASS |
| 50 | RDS publicly accessible | False | False | PASS |
| 51 | RDS storage encrypted | True | True | PASS |
| 52 | ECS task has no public IP | None | None | PASS |
| 53 | ECR scan: CRITICAL findings (product image) | None | None | PASS |

**TOTAL: 53 passed, 0 failed**
