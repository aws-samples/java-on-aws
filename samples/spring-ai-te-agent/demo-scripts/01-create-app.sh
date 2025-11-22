#!/bin/bash

pause_and_execute() {
    echo ""
    echo "About to execute:"
    echo "$1"
    echo ""
    echo "Press any key to continue..."
    read -n 1 -s
    echo ""
    eval "$1"
}

echo "Checking if ai-agent directory exists and remove it..."
if [ -d "ai-agent" ]; then
    echo "Found existing ai-agent directory, removing it..."
    rm -rf ai-agent
fi

pause_and_execute "curl https://start.spring.io/starter.zip \\
  -d type=maven-project \\
  -d language=java \\
  -d bootVersion=3.5.7 \\
  -d baseDir=ai-agent \\
  -d groupId=com.example \\
  -d artifactId=ai-agent \\
  -d name=ai-agent \\
  -d description='AI Agent with Spring AI and Amazon Bedrock' \\
  -d packageName=com.example.ai.agent \\
  -d packaging=jar \\
  -d javaVersion=21 \\
  -d dependencies=spring-ai-bedrock-converse,web,thymeleaf \\
  -o ai-agent.zip"

unzip ai-agent.zip
rm ai-agent.zip

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
spring.ai.bedrock.converse.chat.options.model=global.anthropic.claude-sonnet-4-20250514-v1:0
EOL

echo "Creating necessary directories and files..."
mkdir -p src/main/resources/templates
mkdir -p src/main/java/com/example/ai/agent/controller
mkdir -p src/main/java/com/example/ai/agent/service

cp "$SOURCES_FOLDER/ai-agent/src/main/resources/templates/chat.html" src/main/resources/templates/
cp "$SOURCES_FOLDER/demo-scripts/Steps/WebViewController.java.1" src/main/java/com/example/ai/agent/controller/WebViewController.java
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.0" src/main/java/com/example/ai/agent/service/ChatService.java
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatController.java.0" src/main/java/com/example/ai/agent/controller/ChatController.java

echo ""
echo "Git status:"
git status

sleep 1
./mvnw clean package
./mvnw spring-boot:run

echo ""
echo "Committing changes to Git repository..."
git add .
git commit -m "Update initial files"

cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.1" src/main/java/com/example/ai/agent/service/ChatService.java

./mvnw spring-boot:run

cd ..
