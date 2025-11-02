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

echo "Checking if ai-agent directory exists and remove it..."
if [ -d "ai-agent" ]; then
    echo "Found existing ai-agent directory, removing it..."
    rm -rf ai-agent
fi

echo ""
echo "About to initialize Spring Boot project with the following command:"
echo -e "\033[1m./spring-boot-cli/spring-3.5.0/bin/spring init --java-version=21 \033[0m"
echo "   --build=maven \\"
echo "   --packaging=jar \\"
echo "   --type=maven-project \\"
echo "   --artifact-id=ai.agent \\"
echo "   --name=ai-agent \\"
echo "   --group-id=com.example \\"
echo -e "   \033[1m--dependencies=spring-ai-bedrock-converse,web,thymeleaf,actuator,devtools,testcontainers,postgresql \033[0m\\"
echo "   --extract \\"
echo "   ai-agent"

echo ""
echo "Press any key to continue with Spring initialization..."
read -n 1 -s

echo ""
echo "Initializing Spring Boot project..."
./spring-boot-cli/spring-3.5.0/bin/spring init --java-version=21 \
   --build=maven \
   --packaging=jar \
   --type=maven-project \
   --artifact-id=ai.agent \
   --name=ai-agent \
   --group-id=com.example \
   --dependencies=spring-ai-bedrock-converse,web,thymeleaf,actuator,devtools,testcontainers,postgresql \
   --extract \
   ai-agent

echo ""
echo "Initializing Git repository..."
git init
git add .
git commit -m "Create ai-agent app"

echo ""
echo "Press any key to continue with App initialization..."
read -n 1 -s

echo ""
echo "Configuring application.properties..."
cd ai-agent
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
spring.ai.bedrock.converse.chat.options.model=openai.gpt-oss-120b-1:0
EOL

echo "Creating necessary directories and files..."
mkdir -p src/main/resources/templates
mkdir -p src/main/java/com/example/ai/agent/controller
mkdir -p src/main/java/com/example/ai/agent/service

cp "$SOURCES_FOLDER/ai-agent/src/main/resources/templates/chat.html" src/main/resources/templates/
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/controller/WebViewController.java" src/main/java/com/example/ai/agent/controller/
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.0" src/main/java/com/example/ai/agent/service/ChatService.java
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatController.java.0" src/main/java/com/example/ai/agent/controller/ChatController.java

echo ""
echo "Git status:"
git status

# echo ""
# echo "Opening files in VS Code..."
# code src/main/resources/application.properties
# code pom.xml
# code src/main/java/com/example/ai/agent/ChatService.java

echo ""
echo "Committing changes to Git repository..."
git add .
git commit -m "Update initial files"

./mvnw spring-boot:test-run

cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.1" src/main/java/com/example/ai/agent/service/ChatService.java

./mvnw spring-boot:test-run

cd ..
