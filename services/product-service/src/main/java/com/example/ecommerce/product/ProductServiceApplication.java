package com.example.ecommerce.product;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * JPA 設定已移至 {@link com.example.ecommerce.product.config.JpaConfig}，
 * 避免影響 @WebMvcTest slice 測試。
 */
@SpringBootApplication(scanBasePackages = {
    "com.example.ecommerce.product",
    "com.example.ecommerce.security",
    "com.example.ecommerce.tenant",
    "com.example.audit"
})
public class ProductServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(ProductServiceApplication.class, args);
    }
}
