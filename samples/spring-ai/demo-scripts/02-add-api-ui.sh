#!/bin/bash

# Script to copy template and Java files to the assistant app

# Check if source folder exists
if [ ! -d "$SOURCES_FOLDER" ]; then
    echo "Error: Source folder $SOURCES_FOLDER does not exist."
    exit 1
fi

# Check if assistant folder exists
if [ ! -d "assistant" ]; then
    echo "Error: assistant folder not found in current directory."
    echo "Please run this script from the directory containing the assistant folder."
    exit 1
fi

cd assistant

# Update pom.xml to add Web dependencies
echo "Updating pom.xml with Web/UI dependencies..."

# Create a temporary file with the new dependencies
cat > temp_dependencies.xml << 'EOL'
        <!-- Web/UI dependencies -->
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-web</artifactId>
		</dependency>
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-starter-thymeleaf</artifactId>
		</dependency>
EOL

# Create a temporary file for the modified pom.xml
cat pom.xml | awk '
BEGIN { print_deps = 1; in_first_deps = 0; }
/<dependencies>/ {
    if (!in_first_deps) {
        print $0;
        system("cat temp_dependencies.xml");
        in_first_deps = 1;
        next;
    }
}
{ print $0; }
' > pom.xml.new

# Replace the original file with the new one
mv pom.xml.new pom.xml
rm temp_dependencies.xml

echo "Opening pom.xml in VS Code..."
code pom.xml

echo ""
echo "Configuring application.properties..."

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
EOL

echo ""
echo "Opening files in VS Code..."
code pom.xml
code src/main/java/com/example/assistant/AssistantApplication.java
code src/main/resources/application.properties

echo "Creating necessary directories..."
# Create templates directory if it doesn't exist
mkdir -p src/main/resources/templates

# Create package directories if they don't exist
mkdir -p src/main/java/com/example/assistant
mkdir -p src/main/java/com/example/assistant/config
mkdir -p src/main/java/com/example/assistant/controller
mkdir -p src/main/java/com/example/assistant/model
mkdir -p src/main/java/com/example/assistant/service
mkdir -p src/main/java/com/example/assistant/util

echo "Copying template file..."
# Copy template file - check if it exists first
if [ -f "$SOURCES_FOLDER/assistant/templates/chat.html" ]; then
    cp "$SOURCES_FOLDER/assistant/templates/chat.html" src/main/resources/templates/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/resources/templates/chat.html" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/resources/templates/chat.html" src/main/resources/templates/
else
    echo "Warning: chat.html not found in expected locations. Skipping."
fi

echo "Copying Java files..."
# Copy Java files - check each possible location

# PromptConfig.java
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/config/PromptConfig.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/config/PromptConfig.java" src/main/java/com/example/assistant/config/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/PromptConfig.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/PromptConfig.java" src/main/java/com/example/assistant/
else
    echo "Warning: PromptConfig.java not found in expected locations. Skipping."
fi

# ChatController.java
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/controller/ChatController.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/controller/ChatController.java" src/main/java/com/example/assistant/controller/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatController.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatController.java" src/main/java/com/example/assistant/
else
    echo "Warning: ChatController.java not found in expected locations. Skipping."
fi

# WebViewController.java
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/controller/WebViewController.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/controller/WebViewController.java" src/main/java/com/example/assistant/controller/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/WebViewController.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/WebViewController.java" src/main/java/com/example/assistant/
else
    echo "Warning: WebViewController.java not found in expected locations. Skipping."
fi

# ChatRequest.java
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/model/ChatRequest.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/model/ChatRequest.java" src/main/java/com/example/assistant/model/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatRequest.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/ChatRequest.java" src/main/java/com/example/assistant/
else
    echo "Warning: ChatRequest.java not found in expected locations. Skipping."
fi

# RetryUtils.java
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/util/RetryUtils.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/util/RetryUtils.java" src/main/java/com/example/assistant/util/
elif [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/RetryUtils.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/RetryUtils.java" src/main/java/com/example/assistant/
else
    echo "Warning: RetryUtils.java not found in expected locations. Skipping."
fi

# ChatService.java - Copy from the specific location only
echo "Copying ChatService.java from demo-scripts folder..."
if [ -f "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.2" ]; then
    cp "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.2" src/main/java/com/example/assistant/service/ChatService.java
    echo "ChatService.java copied successfully."

    # Open ChatService.java in VS Code
    echo "Opening ChatService.java in VS Code..."
    code src/main/java/com/example/assistant/service/ChatService.java
else
    echo "Error: ChatService.java.2 not found at $SOURCES_FOLDER/demo-scripts/ChatService/."
    echo "Please ensure the file exists at the specified location."
    exit 1
fi

echo "Files copied successfully."

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo Done!
cd ..
