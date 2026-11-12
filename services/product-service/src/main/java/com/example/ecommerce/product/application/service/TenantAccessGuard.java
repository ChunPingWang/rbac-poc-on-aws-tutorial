package com.example.ecommerce.product.application.service;

import com.example.ecommerce.common.exception.ResourceNotFoundException;
import com.example.ecommerce.product.domain.model.aggregate.Product;
import com.example.ecommerce.tenant.context.TenantContext;

import java.util.UUID;

/**
 * 以 ID 存取單筆商品時的租戶隔離檢查。
 *
 * <p>原專案僅在「列表查詢」依租戶過濾，GET/PUT/DELETE /api/products/{id}
 * 未檢查租戶，任何租戶只要知道 ID 即可讀寫他租戶商品（違反 multi-tenant.feature
 * 「租戶無法存取其他租戶的商品 → 資源不存在」）。此 Guard 補上檢查：</p>
 * <ul>
 *   <li>{@code system}（ADMIN）可存取所有租戶</li>
 *   <li>其他租戶只能存取 tenantId 相同的商品</li>
 *   <li>不符時回 404（ResourceNotFoundException）而非 403，避免洩漏資源存在與否</li>
 *   <li>Fail-closed：取不到租戶時一律拒絕</li>
 * </ul>
 */
final class TenantAccessGuard {

    static final String SYSTEM_TENANT = "system";

    private TenantAccessGuard() {
    }

    static Product requireAccessible(Product product, UUID requestedId) {
        String currentTenant = TenantContext.getCurrentTenant();
        if (SYSTEM_TENANT.equals(currentTenant)) {
            return product;
        }
        if (currentTenant == null || !currentTenant.equals(product.getTenantId())) {
            throw new ResourceNotFoundException("Product", requestedId);
        }
        return product;
    }
}
