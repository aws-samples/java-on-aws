package org.devoxx.mcp.trip.hotel;

import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.reflect.Field;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.springframework.http.MediaType.TEXT_HTML_VALUE;

@RestController
class AuthorzationServerController {
    private final InMemoryRegisteredClientRepository registeredClientRepository;

    AuthorzationServerController(RegisteredClientRepository registeredClientRepository) {
        this.registeredClientRepository = (InMemoryRegisteredClientRepository) registeredClientRepository;
    }

    @GetMapping(value = "/clients", produces = TEXT_HTML_VALUE)
    public String clients() throws Exception {
        Field field = InMemoryRegisteredClientRepository.class.getDeclaredField("clientIdRegistrationMap");
        field.setAccessible(true);
        Map<String, RegisteredClient> clientIdRegistrationMap = (Map<String, RegisteredClient>) field.get(registeredClientRepository);
        var clients = clientIdRegistrationMap.entrySet()
                .stream()
                .map(e -> clientRow(e.getKey(), e.getValue().getRedirectUris()))
                .collect(Collectors.joining("\n"))
                .indent(8);
        return """
                <body>
                    <ul>
                    %s
                    </ul>
                </body>
                """.formatted(clients);
    }

    @GetMapping("/userinfo")
    public Map<String, Object> userinfo() {
        return Map.of(
            "sub", "demo-user",
            "name", "Demo User",
            "email", "demo@example.com"
        );
    }

    public static String clientRow(String clientId, Set<String> redirectUris) {
        var redirectUriList = redirectUris.stream().map("<li>%s</li>"::formatted)
                .collect(Collectors.joining("\n"));
        return """
                <li><b>%s</b>
                <ul>
                %s
                </ul>
                </li>
                """.formatted(clientId, redirectUriList);
    }
}
