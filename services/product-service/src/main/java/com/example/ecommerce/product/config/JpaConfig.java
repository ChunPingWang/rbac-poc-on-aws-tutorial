package com.example.ecommerce.product.config;

import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * JPA 設定獨立於 {@code @SpringBootApplication} 類別之外。
 *
 * <p>原本 {@code @EnableJpaRepositories} / {@code @EntityScan} 直接標在
 * ProductServiceApplication 上，導致所有 {@code @WebMvcTest} slice 測試也被迫建立
 * JPA Repository，因缺少 entityManagerFactory 而整個 context 啟動失敗
 * （22 個 Controller 測試失敗，於 AWS CodeBuild 首次建置時發現）。
 * 放在一般 {@code @Configuration} 中，slice 測試就不會載入它。</p>
 */
@Configuration
@EnableJpaRepositories(basePackages = {
    "com.example.ecommerce.product.adapter.outbound.persistence"
})
@EntityScan(basePackages = {
    "com.example.ecommerce.product.adapter.outbound.persistence.entity",
    "com.example.audit.infrastructure.persistence.entity"
})
public class JpaConfig {
}
