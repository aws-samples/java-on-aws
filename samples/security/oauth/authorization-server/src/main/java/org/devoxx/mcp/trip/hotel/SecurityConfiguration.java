package org.devoxx.mcp.trip.hotel;

import org.devoxx.mcp.trip.hotel.user.DemoUser;
import org.devoxx.mcp.trip.hotel.user.DemoUserDetailsService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.oauth2.core.oidc.StandardClaimNames;
import org.springframework.security.oauth2.core.oidc.endpoint.OidcParameterNames;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;

import java.util.List;

import static org.springaicommunity.mcp.security.authorizationserver.config.McpAuthorizationServerConfigurer.mcpAuthorizationServer;
import static org.springframework.security.config.Customizer.withDefaults;
import static org.springframework.security.oauth2.server.authorization.config.annotation.web.configurers.OAuth2AuthorizationServerConfigurer.authorizationServer;

@Configuration
@EnableWebSecurity
class SecurityConfiguration {

	@Bean
	SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
		return http.authorizeHttpRequests(authz -> authz.anyRequest().authenticated())
			.with(authorizationServer(), authServer -> authServer.oidc(withDefaults()))
			.with(mcpAuthorizationServer(), withDefaults())
			.formLogin(withDefaults())
			.cors(cors -> cors.configurationSource(req -> configurationSource()))
			.build();
	}

	@Bean
	UserDetailsService userDetailsService() {
		return new DemoUserDetailsService(new DemoUser("andrei", "pw", "andrei@example.com"),
				new DemoUser("alice", "pw", "alice@example.com"), new DemoUser("bob", "pw", "bob@example.com"));
	}

	@Bean
	OAuth2TokenCustomizer<JwtEncodingContext> tokenCustomizer() {
		return ctx -> {
			DemoUser user = (DemoUser) ctx.getPrincipal().getPrincipal();
			ctx.getClaims().subject(user.getUserEmail());
			if (ctx.getTokenType().getValue().equals(OidcParameterNames.ID_TOKEN)) {
				ctx.getClaims().claim(StandardClaimNames.EMAIL, user.getUserEmail());
				ctx.getClaims().claim(StandardClaimNames.EMAIL_VERIFIED, true);
				ctx.getClaims().claim(StandardClaimNames.NAME, user.getUsername());
			}
		};
	}

	private CorsConfiguration configurationSource() {
		CorsConfiguration configuration = new CorsConfiguration();
		configuration.setAllowedOriginPatterns(List.of("*"));
		configuration.setAllowedMethods(List.of("*"));
		configuration.setAllowedHeaders(List.of("*"));
		configuration.setAllowCredentials(true);

		return configuration;
	}
}
