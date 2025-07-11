#!/bin/bash

# Script to add memory functionality to the assistant app

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

# Check if database folder exists and delete it if it does
echo "Checking for database folder..."
if [ -d "database" ]; then
    echo "Found existing database folder, removing it..."
    rm -rf database
fi

Copy database folder from source
echo "Copying database folder from source..."
if [ -d "$SOURCES_FOLDER/database" ]; then
    cp -r "$SOURCES_FOLDER/database" .
    echo "Database folder copied successfully."
else
    echo "Error: Database folder not found at $SOURCES_FOLDER/database."
    echo "Please ensure the folder exists at the specified location."
    exit 1
fi

# Change to assistant directory and commit changes
echo "Committing previous changes..."
cd assistant
git add .
git commit -m "add ChatController"

# Create service directory if it doesn't exist
mkdir -p src/main/java/com/example/assistant/service

# Copy ChatMemoryService.java
echo "Copying ChatMemoryService.java..."
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/ChatMemoryService.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/ChatMemoryService.java" src/main/java/com/example/assistant/service/
    echo "ChatMemoryService.java copied successfully."
else
    echo "Error: ChatMemoryService.java not found at $SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/."
    echo "Please ensure the file exists at the specified location."
    exit 1
fi

# Copy ChatService.java.3 to ChatService.java
echo "Copying ChatService.java from version 3..."
if [ -f "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.3" ]; then
    cp "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.3" src/main/java/com/example/assistant/service/ChatService.java
    echo "ChatService.java copied successfully."

    # Open ChatService.java in VS Code
    echo "Opening ChatService.java in VS Code..."
    code src/main/java/com/example/assistant/service/ChatService.java
else
    echo "Error: ChatService.java.3 not found at $SOURCES_FOLDER/demo-scripts/ChatService/"
    echo "Please ensure the file exists at the specified location."
    exit 1
fi

# Add PostgreSQL and JPA configuration to application.properties
echo "Updating application.properties with database configuration..."
cat >> src/main/resources/application.properties << 'EOL'

# PostgreSQL Configuration
spring.datasource.url=jdbc:postgresql://localhost:5432/assistant_db
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

echo "Opening application.properties in VS Code..."
code src/main/resources/application.properties

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

echo "Files copied and configurations updated successfully."

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..