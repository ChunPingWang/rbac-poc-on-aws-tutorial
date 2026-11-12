package com.example.ecommerce.security.converter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class CognitoGroupsRoleConverterTest {

    private static Jwt jwt(Map<String, Object> claims) {
        Jwt.Builder b = Jwt.withTokenValue("t").header("alg", "RS256")
            .issuedAt(Instant.now()).expiresAt(Instant.now().plusSeconds(60)).subject("sub-1");
        claims.forEach(b::claim);
        return b.build();
    }

    private static Set<String> names(java.util.Collection<GrantedAuthority> a) {
        return a.stream().map(GrantedAuthority::getAuthority).collect(Collectors.toSet());
    }

    @Test
    @DisplayName("cognito:groups → ROLE_*")
    void mapsCognitoGroups() {
        var result = new CognitoGroupsRoleConverter()
            .convert(jwt(Map.of("cognito:groups", List.of("ADMIN", "tenant_admin"))));
        assertThat(names(result)).containsExactlyInAnyOrder("ROLE_ADMIN", "ROLE_TENANT_ADMIN");
    }

    @Test
    @DisplayName("no cognito:groups → empty")
    void emptyWhenNoGroups() {
        assertThat(new CognitoGroupsRoleConverter().convert(jwt(Map.of("scope", "openid")))).isEmpty();
    }

    @Test
    @DisplayName("composite merges Keycloak realm_access and Cognito groups")
    void compositeMergesBothIdps() {
        var c = new CompositeRoleConverter(new KeycloakRoleConverter(), new CognitoGroupsRoleConverter());
        var result = c.convert(jwt(Map.of(
            "realm_access", Map.of("roles", List.of("user")),
            "cognito:groups", List.of("AUDITOR"))));
        assertThat(names(result)).containsExactlyInAnyOrder("ROLE_USER", "ROLE_AUDITOR");
    }
}
