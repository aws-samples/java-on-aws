#!/bin/bash

# Script to add memory functionality to the ai-agent app

# Check if source folder exists
if [ ! -d "$SOURCES_FOLDER" ]; then
    echo "Error: Source folder $SOURCES_FOLDER does not exist."
    exit 1
fi

# Check if ai-agent folder exists
if [ ! -d "ai-agent" ]; then
    echo "Error: ai-agent folder not found in current directory."
    echo "Please run this script from the directory containing the ai-agent folder."
    exit 1
fi

# Change to ai-agent directory and commit changes
echo "Committing previous changes..."
git add .
git commit -m "add ChatController"

cd ai-agent

echo "Copying ChatMemoryService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/service/ChatMemoryService.java" src/main/java/com/example/ai/agent/service/

echo "Copying ConversationSummaryService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/service/ConversationSummaryService.java" src/main/java/com/example/ai/agent/service/

echo "Copying ChatService.java from version 2..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.2" src/main/java/com/example/ai/agent/service/ChatService.java

echo "Copying ChatController.java from version 2..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatController.java.2" src/main/java/com/example/ai/agent/controller/ChatController.java

echo "Copying WebViewController.java from version 2..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/WebViewController.java.2" src/main/java/com/example/ai/agent/controller/WebViewController.java

# Add PostgreSQL and JPA configuration to application.properties
echo "Updating application.properties with database configuration..."
cat >> src/main/resources/application.properties << 'EOL'

# PostgreSQL Configuration (will be overridden by Testcontainers in test-run mode)
spring.datasource.url=jdbc:postgresql://localhost:5432/ai_agent_db
spring.datasource.username=postgres
spring.datasource.password=postgres
spring.datasource.driver-class-name=org.postgresql.Driver

# JPA Configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# JDBC Memory properties
spring.ai.chat.memory.repository.jdbc.initialize-schema=always
EOL

# echo "Opening application.properties in VS Code..."
# code src/main/resources/application.properties

# Update pom.xml to add PostgreSQL and JDBC memory dependencies
echo "Updating pom.xml with PostgreSQL and JDBC memory dependencies..."

# Create a temporary file with the new dependencies
cat > temp_dependencies.xml << 'EOL'
		<!-- Chat memory dependencies -->
		<dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-starter-model-chat-memory-repository-jdbc</artifactId>
        </dependency>
		<dependency>
			<groupId>org.postgresql</groupId>
			<artifactId>postgresql</artifactId>
			<scope>runtime</scope>
		</dependency>
		<dependency>
			<groupId>org.springframework.boot</groupId>
			<artifactId>spring-boot-testcontainers</artifactId>
			<scope>test</scope>
		</dependency>
		<dependency>
			<groupId>org.testcontainers</groupId>
			<artifactId>postgresql</artifactId>
			<scope>test</scope>
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

# echo "Opening pom.xml in VS Code..."
# code pom.xml

# Copy Testcontainers configuration for database setup (if directory exists)
if [ -d "$SOURCES_FOLDER/ai-agent/src/test" ]; then
    echo "Copying test configuration files..."
    rm -rf "src/test" 2>/dev/null || true
    mkdir -p src/test/
    cp -r "$SOURCES_FOLDER/ai-agent/src/test"/* src/test/ 2>/dev/null || echo "Some test files not found, continuing..."
    echo "Testcontainers configuration copied successfully!"
else
    echo "Test directory not found at $SOURCES_FOLDER/ai-agent/src/test, skipping test setup..."
    echo "Note: You can add Testcontainers configuration later for database support."
fi

echo "Files copied and configurations updated successfully."

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..