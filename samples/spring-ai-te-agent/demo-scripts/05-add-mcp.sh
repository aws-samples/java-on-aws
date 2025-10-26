#!/bin/bash

# Script to add MCP functionality to the ai-agent app

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

# Check if backoffice folder exists and delete it if it does
echo "Checking for backoffice folder..."
if [ -d "backoffice" ]; then
    echo "Found existing backoffice folder, removing it..."
    rm -rf backoffice
fi

Copy backoffice folder from source
echo "Copying backoffice folder from source..."
if [ -d "$SOURCES_FOLDER/backoffice" ]; then
    cp -r "$SOURCES_FOLDER/backoffice" .
    echo "backoffice folder copied successfully."
else
    echo "Error: backoffice folder not found at $SOURCES_FOLDER/backoffice."
    echo "Please ensure the folder exists at the specified location."
    exit 1
fi

# Check if travel folder exists and delete it if it does
echo "Checking for travel folder..."
if [ -d "travel" ]; then
    echo "Found existing travel folder, removing it..."
    rm -rf travel
fi

Copy travel folder from source
echo "Copying travel folder from source..."
if [ -d "$SOURCES_FOLDER/travel" ]; then
    cp -r "$SOURCES_FOLDER/travel" .
    echo "travel folder copied successfully."
else
    echo "Error: travel folder not found at $SOURCES_FOLDER/travel."
    echo "Please ensure the folder exists at the specified location."
    exit 1
fi

# Change to ai-agent directory and commit changes
echo "Committing previous changes..."
git add .
git commit -m "add Tools"

cd ai-agent

echo "Copying ChatService.java from version 5..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.5" src/main/java/com/example/ai/agent/service/ChatService.java
# code src/main/java/com/example/ai-agent/ChatService.java

echo "Updating application.properties with database configuration..."
cat >> src/main/resources/application.properties << 'EOL'

# MCP Client Configuration
spring.ai.mcp.client.toolcallback.enabled=true
spring.ai.mcp.client.sse.connections.server1.url=http://localhost:8081
spring.ai.mcp.client.sse.connections.server2.url=http://localhost:8082
EOL

# echo "Opening application.properties in VS Code..."
# code src/main/resources/application.properties

# Update pom.xml to add MCP Client dependencies
echo "Updating pom.xml with MCP Client dependencies..."

# Create a temporary file with the new dependencies
cat > temp_dependencies.xml << 'EOL'
        <!-- MCP Client dependencies -->
		<dependency>
			<groupId>org.springframework.ai</groupId>
			<artifactId>spring-ai-starter-mcp-client</artifactId>
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

echo "Files copied and configurations updated successfully."

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..
