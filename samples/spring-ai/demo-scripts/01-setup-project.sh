#!/bin/bash

# Script to download and setup Spring Boot CLI

# Check if spring-boot-cli directory exists and remove it if it does
if [ -d "spring-boot-cli" ]; then
    echo "Found existing spring-boot-cli directory, removing it..."
    rm -rf spring-boot-cli
fi

echo "Downloading Spring Boot CLI 3.5.0..."
curl -L https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-cli/3.5.0/spring-boot-cli-3.5.0-bin.zip -o spring-boot-cli-3.5.0-bin.zip

echo "Creating spring-boot-cli directory..."
mkdir -p spring-boot-cli

echo "Extracting Spring Boot CLI to spring-boot-cli folder..."
unzip -q spring-boot-cli-3.5.0-bin.zip -d spring-boot-cli

echo "Cleaning up zip file..."
rm spring-boot-cli-3.5.0-bin.zip

echo "Spring Boot CLI setup complete!"
echo "You can find the CLI in the spring-boot-cli directory."

# Check if assistant directory exists and remove it if it does
if [ -d "assistant" ]; then
    echo "Found existing assistant directory, removing it..."
    rm -rf assistant
fi

echo ""
echo "About to initialize Spring Boot project with the following command:"
echo -e "\033[1m./spring-boot-cli/spring-3.5.0/bin/spring init --java-version=21 \033[0m"
echo "   --build=maven \\"
echo "   --packaging=jar \\"
echo "   --type=maven-project \\"
echo "   --artifact-id=assistant \\"
echo "   --name=assistant \\"
echo "   --group-id=com.example \\"
echo -e "   \033[1m--dependencies=web,thymeleaf,spring-ai-bedrock-converse \033[0m\\"
echo "   --extract \\"
echo "   assistant"

echo ""
echo "Press any key to continue with Spring initialization..."
read -n 1 -s

echo ""
echo "Initializing Spring Boot project..."
./spring-boot-cli/spring-3.5.0/bin/spring init --java-version=21 \
   --build=maven \
   --packaging=jar \
   --type=maven-project \
   --artifact-id=assistant \
   --name=assistant \
   --group-id=com.example \
   --dependencies=web,thymeleaf,spring-ai-bedrock-converse \
   --extract \
   assistant

echo ""
echo "Configuring application.properties..."
cd assistant
cat > src/main/resources/application.properties << 'EOL'
# Simplified logging pattern - only show the message
logging.pattern.console=%msg%n

# Debugging
logging.level.org.springframework.ai=DEBUG
spring.ai.chat.observations.log-completion=true
spring.ai.chat.observations.include-error-logging=true
spring.ai.tools.observations.include-content=true

# Thymeleaf Configuration
spring.thymeleaf.cache=false
spring.thymeleaf.prefix=classpath:/templates/
spring.thymeleaf.suffix=.html

# Amazon Bedrock Configuration
spring.ai.bedrock.aws.region=us-east-1
spring.ai.bedrock.converse.chat.options.max-tokens=10000
spring.ai.bedrock.converse.chat.options.model=us.anthropic.claude-3-7-sonnet-20250219-v1:0
EOL

echo ""
echo "Opening files in VS Code..."
code pom.xml
code src/main/java/com/example/assistant/AssistantApplication.java
code src/main/resources/application.properties

echo ""
echo "Press any key to continue with updating AssistantApplication.java..."
read -n 1 -s

echo ""
echo "Updating AssistantApplication.java with CommandLineRunner..."
cat > src/main/java/com/example/assistant/AssistantApplication.java << 'EOL'
package com.example.assistant;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import java.util.Scanner;

@SpringBootApplication
public class AssistantApplication {

	public static void main(String[] args) {
		SpringApplication.run(AssistantApplication.class, args);
	}

	@Bean
    public CommandLineRunner cli(ChatClient.Builder chatClientBuilder) {
        return args -> {
            var chatClient = chatClientBuilder
                .defaultSystem("You are a AI Assistant, expert in all sorts of things related to travel and expenses management.")
                .build();

            System.out.println("\nI am your AI Assistant.\n");
            try (Scanner scanner = new Scanner(System.in)) {
                while (true) {
                    System.out.print("\nUSER: ");
                    System.out.println("\nASSISTANT: " +
                        chatClient.prompt(scanner.nextLine()) // Get the user input
                            .call()
                            .content());
                }
            }
        };
    }
}
EOL

echo ""
echo "Building the project with Maven..."
./mvnw spring-boot:run -Dspring-boot.run.arguments="--logging.level.org.springframework.ai=INFO"

echo ""
echo "Press any key after you've exited the application..."
read -n 1 -s

echo ""
echo "Reverting AssistantApplication.java to original state..."
cat > src/main/java/com/example/assistant/AssistantApplication.java << 'EOL'
package com.example.assistant;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AssistantApplication {

	public static void main(String[] args) {
		SpringApplication.run(AssistantApplication.class, args);
	}
}
EOL

echo ""
echo "Initializing Git repository..."
git init
git add .
git commit -m "Create project"

cd ..