package com.example.ecommerce.security.converter;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 從 Amazon Cognito JWT 的 {@code cognito:groups} claim 提取角色。
 *
 * <p>在 AWS 版本中，Keycloak Realm Role 以 Cognito User Pool Group 取代，
 * Group 名稱即角色名稱（ADMIN / TENANT_ADMIN / USER / VIEWER / AUDITOR）。</p>
 *
 * <pre>
 * {
 *   "cognito:groups": ["ADMIN"],
 *   "username": "admin.user",
 *   "tenant_id": "tenant-a"      // 由 Pre Token Generation Lambda (V2) 注入
 * }
 * </pre>
 */
public class CognitoGroupsRoleConverter implements Converter<Jwt, Collection<GrantedAuthority>> {

    public static final String COGNITO_GROUPS_CLAIM = "cognito:groups";

    @Override
    public Collection<GrantedAuthority> convert(Jwt jwt) {
        List<String> groups = jwt.getClaimAsStringList(COGNITO_GROUPS_CLAIM);
        if (groups == null) {
            return Set.of();
        }
        return groups.stream()
            .map(g -> g.toUpperCase().startsWith("ROLE_") ? g.toUpperCase() : "ROLE_" + g.toUpperCase())
            .map(SimpleGrantedAuthority::new)
            .collect(Collectors.toSet());
    }
}
