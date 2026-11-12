package com.example.ecommerce.security.config;

import com.example.ecommerce.security.converter.PrincipalAwareJwtAuthenticationConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Spring Security 配置 - OAuth2 Resource Server
 */
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/**", "/swagger-ui/**", "/v3/api-docs/**").permitAll()
                .requestMatchers("/api/public/**").permitAll()
                .requestMatchers("/api/**").authenticated()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 ->
                oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
            );

        return http.build();
    }

    /**
     * JWT → Authentication 轉換（Keycloak + Cognito 角色、principal 名稱解析）。
     * 詳見 {@link PrincipalAwareJwtAuthenticationConverter}。
     */
    @Bean
    public PrincipalAwareJwtAuthenticationConverter jwtAuthenticationConverter() {
        return new PrincipalAwareJwtAuthenticationConverter();
    }

    static String resolvePrincipalName(Jwt jwt) {
        return PrincipalAwareJwtAuthenticationConverter.resolvePrincipalName(jwt);
    }
}
