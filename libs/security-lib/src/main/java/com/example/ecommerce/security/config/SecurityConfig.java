package com.example.ecommerce.security.config;

import com.example.ecommerce.security.converter.CognitoGroupsRoleConverter;
import com.example.ecommerce.security.converter.CompositeRoleConverter;
import com.example.ecommerce.security.converter.KeycloakRoleConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
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
     * JWT → Authentication 轉換：
     * <ul>
     *   <li>角色：同時支援 Keycloak（realm_access / realm_roles）與 Cognito（cognito:groups）</li>
     *   <li>Principal 名稱：依序取 username（Cognito access token）→ preferred_username（Keycloak）→ sub</li>
     * </ul>
     */
    @Bean
    public Converter<Jwt, AbstractAuthenticationToken> jwtAuthenticationConverter() {
        JwtAuthenticationConverter delegate = new JwtAuthenticationConverter();
        delegate.setJwtGrantedAuthoritiesConverter(
            new CompositeRoleConverter(new KeycloakRoleConverter(), new CognitoGroupsRoleConverter()));
        return jwt -> {
            AbstractAuthenticationToken token = delegate.convert(jwt);
            return new JwtAuthenticationToken(jwt, token.getAuthorities(), resolvePrincipalName(jwt));
        };
    }

    static String resolvePrincipalName(Jwt jwt) {
        for (String claim : new String[] {"username", "preferred_username", "cognito:username"}) {
            String v = jwt.getClaimAsString(claim);
            if (v != null && !v.isBlank()) {
                return v;
            }
        }
        return jwt.getSubject();
    }
}
