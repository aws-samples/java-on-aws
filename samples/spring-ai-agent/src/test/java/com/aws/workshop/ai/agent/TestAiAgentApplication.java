
import com.aws.workshop.ai.agent.AiAgentApplication;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.devtools.restart.RestartScope;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

import java.util.List;
import java.util.Map;

public class TestAiAgentApplication {


    public static void main(String[] args) {
        System.out.println("!!!!!Starting test application");
        System.setProperty("spring.sql.init.mode", "always");
        SpringApplication.from(AiAgentApplication::main)
                .with(TestContainersConfiguration.class)
                .run(args);
    }
}


@Configuration
@Testcontainers
class TestContainersConfiguration {

    @Bean
    @ServiceConnection
    @RestartScope
    PostgreSQLContainer<?> postgreSQLContainer() {
        System.out.println("Starting postgreSQL container");
        var image = DockerImageName.parse("pgvector/pgvector:pg16")
                .asCompatibleSubstituteFor("postgres");
        return new PostgreSQLContainer<>(image);
    }
}


