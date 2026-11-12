package com.example.ecommerce.security.converter;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.*;

/**
 * 合併多個 IdP 的角色轉換器，使同一份程式碼可同時支援 Keycloak（本地 / K8s）
 * 與 Amazon Cognito（AWS）。
 */
public class CompositeRoleConverter implements Converter<Jwt, Collection<GrantedAuthority>> {

    private final List<Converter<Jwt, Collection<GrantedAuthority>>> delegates;

    @SafeVarargs
    public CompositeRoleConverter(Converter<Jwt, Collection<GrantedAuthority>>... delegates) {
        this.delegates = List.of(delegates);
    }

    @Override
    public Collection<GrantedAuthority> convert(Jwt jwt) {
        Set<GrantedAuthority> all = new HashSet<>();
        for (Converter<Jwt, Collection<GrantedAuthority>> d : delegates) {
            Collection<GrantedAuthority> part = d.convert(jwt);
            if (part != null) {
                all.addAll(part);
            }
        }
        return all;
    }
}
