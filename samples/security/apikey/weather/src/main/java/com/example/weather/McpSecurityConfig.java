package com.example.weather;

import org.jspecify.annotations.NonNull;
import org.springaicommunity.mcp.security.server.apikey.ApiKeyEntity;
import org.springaicommunity.mcp.security.server.apikey.ApiKeyEntityRepository;
import org.springaicommunity.mcp.security.server.apikey.memory.InMemoryApiKeyEntityRepository;
import org.springaicommunity.mcp.security.server.config.McpApiKeyConfigurer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.CsrfConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
class McpSecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http.authorizeHttpRequests(authz -> authz.anyRequest().authenticated())
                .with(McpApiKeyConfigurer.mcpServerApiKey(), (apiKey) -> apiKey.apiKeyRepository(buildApiKeyRepository()))
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .csrf(CsrfConfigurer::disable)
                .build();
    }

    private ApiKeyEntityRepository<@NonNull ApiKeyEntity> buildApiKeyRepository() {
//        ApiKeyEntity apiKey = ApiKeyEntityImpl.builder()
//                .name("test api key")
//                .id("api01")
//                // "mycustomapikey
//                .secret("mycustomapikey")
//                .build();

        // Spring erases credentials after the first call by default, CustomApiKeyEntity ignores erasing
        var apiKey = CustomApiKeyEntity.create("api01", "test api key", "mycustomapikey");
        return new InMemoryApiKeyEntityRepository<>(List.of(apiKey));
    }

    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOriginPatterns(List.of("http://localhost:*"));
        configuration.setAllowedMethods(List.of("*"));
        configuration.setAllowedHeaders(List.of("*"));
        configuration.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
