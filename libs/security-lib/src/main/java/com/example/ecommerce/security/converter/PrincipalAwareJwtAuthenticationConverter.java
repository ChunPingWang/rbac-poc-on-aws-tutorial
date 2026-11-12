package com.example.ecommerce.security.converter;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/**
 * JWT → Authentication：
 * <ul>
 *   <li>角色：Keycloak（realm_access / realm_roles）＋ Cognito（cognito:groups）</li>
 *   <li>Principal 名稱：username（Cognito access token）→ preferred_username（Keycloak）
 *       → cognito:username → sub</li>
 * </ul>
 *
 * <p>刻意寫成具名類別而不是 lambda：Spring MVC 會把所有 {@code Converter} bean 註冊進
 * conversion service，lambda 的泛型型別無法解析，會造成
 * "Unable to determine source type &lt;S&gt; and target type &lt;T&gt;" 啟動失敗
 * （於 AWS ECS 首次部署時發現）。</p>
 */
public class PrincipalAwareJwtAuthenticationConverter implements Converter<Jwt, AbstractAuthenticationToken> {

    private final JwtAuthenticationConverter delegate = new JwtAuthenticationConverter();

    public PrincipalAwareJwtAuthenticationConverter() {
        delegate.setJwtGrantedAuthoritiesConverter(
            new CompositeRoleConverter(new KeycloakRoleConverter(), new CognitoGroupsRoleConverter()));
    }

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        AbstractAuthenticationToken token = delegate.convert(jwt);
        return new JwtAuthenticationToken(jwt, token.getAuthorities(), resolvePrincipalName(jwt));
    }

    public static String resolvePrincipalName(Jwt jwt) {
        for (String claim : new String[] {"username", "preferred_username", "cognito:username"}) {
            String v = jwt.getClaimAsString(claim);
            if (v != null && !v.isBlank()) {
                return v;
            }
        }
        return jwt.getSubject();
    }
}
