package com.example.agent;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Full application-context integration test ({@code contextLoads}).
 *
 * <p>This wires the entire bean graph: Bedrock Converse, AgentCore Memory, Knowledge Base (RAG),
 * browser / code-interpreter tool providers, and the MCP client. Those beans only exist when the
 * application is fully provisioned — in particular the AgentCore Memory beans are gated by
 * {@code @ConditionalOnProperty(prefix = "agentcore.memory", name = "memory-id")}, and
 * {@link ChatService} hard-requires the resulting {@code AgentCoreMemory} bean. The deploy script
 * {@code 02-memory.sh} writes {@code agentcore.memory.memory-id} (and other resource ids) into
 * {@code application.properties}.
 *
 * <p>Because of that, this test is opt-in and never runs in the normal build:
 * <ul>
 *   <li>Named {@code *IT} so the Maven Failsafe plugin only considers it during {@code mvn verify}.</li>
 *   <li>{@link EnabledIfSystemProperty} skips it unless {@code -Dit.agentcore=true} is passed.</li>
 * </ul>
 *
 * <p>Run it only from a provisioned workspace (resource ids present in {@code application.properties})
 * with valid AWS credentials in the environment:
 * <pre>{@code   mvn verify -Dit.agentcore=true }</pre>
 */
@EnabledIfSystemProperty(named = "it.agentcore", matches = "true")
@SpringBootTest
class AgentContextIT {

    @Test
    void contextLoads() {
    }
}
