package com.example.ecommerce.security.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigPrincipalTest {

    private static Jwt.Builder base() {
        return Jwt.withTokenValue("t").header("alg", "RS256")
            .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(60)).subject("uuid-sub");
    }

    @Test
    @DisplayName("Cognito access token: principal = username, roles from cognito:groups")
    void cognitoToken() {
        Jwt jwt = base().claim("username", "admin.user").claim("cognito:groups", List.of("ADMIN")).build();
        var auth = new SecurityConfig().jwtAuthenticationConverter().convert(jwt);
        assertThat(auth.getName()).isEqualTo("admin.user");
        assertThat(auth.getAuthorities()).extracting("authority").containsExactly("ROLE_ADMIN");
    }

    @Test
    @DisplayName("Keycloak token: principal = preferred_username")
    void keycloakToken() {
        Jwt jwt = base().claim("preferred_username", "normal.user").build();
        assertThat(SecurityConfig.resolvePrincipalName(jwt)).isEqualTo("normal.user");
    }

    @Test
    @DisplayName("fallback to sub")
    void fallbackToSub() {
        assertThat(SecurityConfig.resolvePrincipalName(base().claim("scope", "x").build())).isEqualTo("uuid-sub");
    }
}
