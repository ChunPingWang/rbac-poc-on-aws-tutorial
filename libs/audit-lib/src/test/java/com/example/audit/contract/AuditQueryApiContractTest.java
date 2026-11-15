package com.example.audit.contract;

import com.example.audit.application.dto.AuditLogView;
import com.example.audit.application.dto.PagedResponse;
import com.example.audit.application.service.AuditQueryService;
import com.example.audit.domain.model.AuditResult;
import com.example.audit.infrastructure.web.AuditQueryController;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.hamcrest.Matchers.*;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * 稽核查詢 API 的契約測試（取代原本的 Spring Cloud Contract）。
 *
 * <p>原專案以 Spring Cloud Contract 的 Groovy DSL 定義 6 份契約
 * （{@code src/test/resources/contracts/auditquery/*.groovy}）並自動產生測試。
 * 為移除 Spring Cloud 相依，改以一般 MockMvc 測試逐一保留相同的請求、
 * 狀態碼、回應欄位與正規表示式斷言，測試覆蓋不變。</p>
 *
 * <p>差異：不再產生 WireMock stub jar 給消費端使用；若未來需要 consumer-driven
 * contract，可改用 Pact 等不依賴 Spring Cloud 的工具。</p>
 */
@DisplayName("Audit Query API contract")
class AuditQueryApiContractTest {

    private static final String UUID_REGEX = "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}";
    private static final String ID_1 = "550e8400-e29b-41d4-a716-446655440000";
    private static final String ID_2 = "550e8400-e29b-41d4-a716-446655440001";

    private MockMvc mockMvc;

    @BeforeEach
    void setup() {
        AuditQueryService queryService = mock(AuditQueryService.class);

        AuditLogView log1 = new AuditLogView(
                UUID.fromString(ID_1), Instant.parse("2026-01-10T08:30:00Z"),
                "PRODUCT_CREATED", "Product", "prod-12345", "admin@example.com",
                "product-service", "createProduct",
                "{\"productCode\":\"TEST-001\",\"productName\":\"Test Widget\"}",
                AuditResult.SUCCESS, null, "192.168.1.100", "corr-abc-123", false);
        AuditLogView log2 = new AuditLogView(
                UUID.fromString(ID_2), Instant.parse("2026-01-10T08:31:00Z"),
                "PRODUCT_UPDATED", "Product", "prod-12345", "admin@example.com",
                "product-service", "updateProduct", "{\"price\":199.99}",
                AuditResult.SUCCESS, null, "192.168.1.100", "corr-abc-123", false);

        when(queryService.findById(UUID.fromString(ID_1))).thenReturn(Optional.of(log1));
        when(queryService.findById(UUID.fromString("00000000-0000-0000-0000-000000000000")))
                .thenReturn(Optional.empty());
        when(queryService.findByUsername(eq("admin@example.com"), anyInt(), anyInt()))
                .thenReturn(new PagedResponse<>(List.of(log1, log2), 0, 20, 2, 1, true, true));
        when(queryService.findByEventType(eq("PRODUCT_CREATED"), anyInt(), anyInt()))
                .thenReturn(new PagedResponse<>(List.of(log1), 0, 20, 1, 1, true, true));
        when(queryService.findByCorrelationId("corr-abc-123")).thenReturn(List.of(log1, log2));
        when(queryService.findByCorrelationId("nonexistent")).thenReturn(List.of());

        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.registerModule(new JavaTimeModule());
        objectMapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        MappingJackson2HttpMessageConverter converter = new MappingJackson2HttpMessageConverter(objectMapper);

        mockMvc = MockMvcBuilders.standaloneSetup(new AuditQueryController(queryService))
                .setMessageConverters(converter)
                .build();
    }

    @Test
    @DisplayName("should return 404 for nonexistent audit log ID")
    void shouldReturn404ForNonexistentId() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs/00000000-0000-0000-0000-000000000000")
                        .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("should return audit log by ID")
    void shouldReturnAuditLogById() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs/" + ID_1).contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.id").value(ID_1))
                .andExpect(jsonPath("$.timestamp").value("2026-01-10T08:30:00Z"))
                .andExpect(jsonPath("$.eventType").value("PRODUCT_CREATED"))
                .andExpect(jsonPath("$.aggregateType").value("Product"))
                .andExpect(jsonPath("$.aggregateId").value("prod-12345"))
                .andExpect(jsonPath("$.username").value("admin@example.com"))
                .andExpect(jsonPath("$.serviceName").value("product-service"))
                .andExpect(jsonPath("$.action").value("createProduct"))
                .andExpect(jsonPath("$.payload").value("{\"productCode\":\"TEST-001\",\"productName\":\"Test Widget\"}"))
                .andExpect(jsonPath("$.result").value("SUCCESS"))
                .andExpect(jsonPath("$.clientIp").value("192.168.1.100"))
                .andExpect(jsonPath("$.correlationId").value("corr-abc-123"))
                .andExpect(jsonPath("$.payloadTruncated").value(false))
                .andExpect(jsonPath("$.id", matchesPattern(UUID_REGEX)))
                .andExpect(jsonPath("$.timestamp", matchesPattern("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")))
                .andExpect(jsonPath("$.eventType", matchesPattern("[A-Z_]+")))
                .andExpect(jsonPath("$.result", matchesPattern("SUCCESS|FAILURE")));
    }

    @Test
    @DisplayName("should return audit logs by correlation ID")
    void shouldReturnAuditLogsByCorrelationId() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs/correlation/corr-abc-123").contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", hasSize(greaterThanOrEqualTo(1))))
                .andExpect(jsonPath("$[0].id").value(ID_1))
                .andExpect(jsonPath("$[0].eventType").value("PRODUCT_CREATED"))
                .andExpect(jsonPath("$[1].id").value(ID_2))
                .andExpect(jsonPath("$[1].eventType").value("PRODUCT_UPDATED"))
                .andExpect(jsonPath("$[*].aggregateType", everyItem(is("Product"))))
                .andExpect(jsonPath("$[*].aggregateId", everyItem(is("prod-12345"))))
                .andExpect(jsonPath("$[*].username", everyItem(is("admin@example.com"))))
                .andExpect(jsonPath("$[*].serviceName", everyItem(is("product-service"))))
                .andExpect(jsonPath("$[*].result", everyItem(is("SUCCESS"))))
                .andExpect(jsonPath("$[*].id", everyItem(matchesPattern(UUID_REGEX))))
                .andExpect(jsonPath("$[*].correlationId", everyItem(matchesPattern("corr-[a-z0-9-]+"))));
    }

    @Test
    @DisplayName("should return audit logs by event type")
    void shouldReturnAuditLogsByEventType() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs").param("eventType", "PRODUCT_CREATED")
                        .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.content", hasSize(1)))
                .andExpect(jsonPath("$.content[0].id").value(ID_1))
                .andExpect(jsonPath("$.content[0].eventType").value("PRODUCT_CREATED"))
                .andExpect(jsonPath("$.content[0].aggregateType").value("Product"))
                .andExpect(jsonPath("$.content[0].result").value("SUCCESS"))
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(20))
                .andExpect(jsonPath("$.totalElements").value(1))
                .andExpect(jsonPath("$.totalPages").value(1))
                .andExpect(jsonPath("$.content[*].eventType", everyItem(matchesPattern("[A-Z_]+"))));
    }

    @Test
    @DisplayName("should return audit logs by username")
    void shouldReturnAuditLogsByUsername() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs")
                        .param("username", "admin@example.com").param("page", "0").param("size", "20")
                        .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.content", hasSize(greaterThanOrEqualTo(1))))
                .andExpect(jsonPath("$.content[0].id").value(ID_1))
                .andExpect(jsonPath("$.content[0].eventType").value("PRODUCT_CREATED"))
                .andExpect(jsonPath("$.content[1].id").value(ID_2))
                .andExpect(jsonPath("$.content[1].eventType").value("PRODUCT_UPDATED"))
                .andExpect(jsonPath("$.content[*].aggregateType", everyItem(is("Product"))))
                .andExpect(jsonPath("$.content[*].result", everyItem(is("SUCCESS"))))
                .andExpect(jsonPath("$.content[*].id", everyItem(matchesPattern(UUID_REGEX))))
                .andExpect(jsonPath("$.content[*].username", everyItem(matchesPattern("[a-zA-Z0-9.@_-]+"))))
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(20))
                .andExpect(jsonPath("$.totalElements").value(2))
                .andExpect(jsonPath("$.totalPages").value(1));
    }

    @Test
    @DisplayName("should return empty list for nonexistent correlation ID")
    void shouldReturnEmptyListForNonexistentCorrelationId() throws Exception {
        mockMvc.perform(get("/api/v1/audit-logs/correlation/nonexistent").contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", hasSize(0)));
    }
}
