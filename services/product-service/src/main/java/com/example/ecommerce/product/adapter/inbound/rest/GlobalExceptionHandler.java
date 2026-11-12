package com.example.ecommerce.product.adapter.inbound.rest;

import com.example.ecommerce.common.dto.ApiResponse;
import com.example.ecommerce.common.exception.BusinessException;
import com.example.ecommerce.common.exception.ResourceNotFoundException;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

/**
 * 將領域例外轉為正確的 HTTP 狀態碼。
 *
 * <p>原專案沒有任何 {@code @ControllerAdvice}，ResourceNotFoundException 會變成 500。
 * 在 AWS 驗證多租戶隔離（他租戶商品應回 404）時發現此問題並補上。</p>
 *
 * <p>注意：刻意「不」處理 AccessDeniedException / 通用 Exception，
 * 讓 Spring Security 的 ExceptionTranslationFilter 維持回傳 401 / 403。</p>
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiResponse<Void> handleNotFound(ResourceNotFoundException ex) {
        return ApiResponse.error(ex.getMessage(), "RESOURCE_NOT_FOUND");
    }

    @ExceptionHandler(BusinessException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ApiResponse<Void> handleBusiness(BusinessException ex) {
        return ApiResponse.error(ex.getMessage(), ex.getErrorCode());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleValidation(MethodArgumentNotValidException ex) {
        String msg = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> e.getField() + ": " + e.getDefaultMessage())
            .collect(Collectors.joining("; "));
        return ApiResponse.error(msg, "VALIDATION_ERROR");
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleIllegalArgument(IllegalArgumentException ex) {
        return ApiResponse.error(ex.getMessage(), "BAD_REQUEST");
    }
}
