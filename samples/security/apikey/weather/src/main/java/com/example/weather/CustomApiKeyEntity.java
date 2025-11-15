package com.example.weather;

import org.springaicommunity.mcp.security.server.apikey.ApiKeyEntity;
import org.springaicommunity.mcp.security.server.apikey.memory.ApiKeyEntityImpl;

public class CustomApiKeyEntity implements ApiKeyEntity {
    
    private final ApiKeyEntityImpl delegate;
    
    public static CustomApiKeyEntity create(String id, String name, String secret) {
        ApiKeyEntityImpl base = ApiKeyEntityImpl.builder()
                .id(id)
                .name(name)
                .secret(secret)
                .build();
        return new CustomApiKeyEntity(base);
    }
    
    private CustomApiKeyEntity(ApiKeyEntityImpl delegate) {
        this.delegate = delegate;
    }
    
    @Override
    public String getId() {
        return delegate.getId();
    }
    
    @Override
    public String getSecret() {
        return delegate.getSecret();
    }
    
    @Override
    public void eraseCredentials() {
        // Intentionally do nothing - ignore credential erasure
    }
    
    @Override
    public ApiKeyEntity copy() {
        return new CustomApiKeyEntity(delegate.copy());
    }
}