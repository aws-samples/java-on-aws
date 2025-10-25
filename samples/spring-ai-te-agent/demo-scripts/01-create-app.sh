#!/bin/bash

echo "Checking if spring-boot-cli directory exists and remove it if it does..."
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

echo "Checking if assistant directory exists and remove it..."
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
echo -e "   \033[1m--dependencies=spring-ai-bedrock-converse,web,thymeleaf,actuator,devtools \033[0m\\"
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
   --dependencies=spring-ai-bedrock-converse,web,thymeleaf,actuator,devtools \
   --extract \
   assistant

echo ""
echo "Initializing Git repository..."
git init
git add .
git commit -m "Create app"

echo ""
echo "Press any key to continue with App initialization..."
read -n 1 -s

echo ""
echo "Configuring application.properties..."
cd assistant
cat >> src/main/resources/application.properties << 'EOL'

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
spring.ai.bedrock.converse.chat.options.model=global.anthropic.claude-sonnet-4-20250514-v1:0
EOL

echo "Creating necessary directories and files..."
mkdir -p src/main/resources/templates
mkdir -p src/main/java/com/example/assistant

cp "$SOURCES_FOLDER/assistant/src/main/resources/templates/chat.html" src/main/resources/templates/
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/WebViewController.java" src/main/java/com/example/assistant/
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/PromptConfig.java" src/main/java/com/example/assistant/
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatController.java" src/main/java/com/example/assistant/
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatRequest.java" src/main/java/com/example/assistant/
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatRetryConfig.java" src/main/java/com/example/assistant/
cp "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.1" src/main/java/com/example/assistant/ChatService.java

echo "Files copied successfully."

echo "Updating pom.xml with dependencies..."
awk '/<dependencies>/ && !done {
	print
	print "\t\t<!-- Resilience4j dependencies -->"
	print "\t\t<dependency>"
	print "\t\t\t<groupId>io.github.resilience4j</groupId>"
	print "\t\t\t<artifactId>resilience4j-spring-boot3</artifactId>"
	print "\t\t\t<version>2.3.0</version>"
	print "\t\t</dependency>"
	print "\t\t<dependency>"
	print "\t\t\t<groupId>io.github.resilience4j</groupId>"
	print "\t\t\t<artifactId>resilience4j-retry</artifactId>"
	print "\t\t\t<version>2.3.0</version>"
	print "\t\t</dependency>"
	done=1
	next
}
1' pom.xml > pom.xml.tmp && mv pom.xml.tmp pom.xml

echo ""
echo "Git status:"
git status

echo ""
echo "Opening files in VS Code..."
code src/main/resources/application.properties
code pom.xml
code src/main/java/com/example/assistant/ChatService.java

echo ""
echo "Committing changes to Git repository..."
git add .
git commit -m "Update initial files"

cd ..
