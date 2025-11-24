#!/bin/bash

# Script to add Multi-model, Multi-modality functionality to the ai-agent app

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

# Copy backoffice folder from source
echo "Copying backoffice folder from source..."
if [ -d "$SOURCES_FOLDER/backoffice" ]; then
    cp -r "$SOURCES_FOLDER/backoffice" .
    echo "backoffice folder copied successfully."
else
    echo "Error: backoffice folder not found at $SOURCES_FOLDER/backoffice."
    echo "Please ensure the folder exists at the specified location."
    exit 1
fi

# Change to ai-agent directory and commit changes
echo "Committing previous changes..."
git add .
git commit -m "add MCP"

cd ai-agent

echo "Copying ChatController.java with multi-modal support..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/controller/ChatController.java" src/main/java/com/example/ai/agent/controller/

echo "Copying WebViewController.java with feature flags..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/controller/WebViewController.java" src/main/java/com/example/ai/agent/controller/

echo "Copying DocumentChatService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/service/DocumentChatService.java" src/main/java/com/example/ai/agent/service/

echo "Updating application.properties with multi-modal configuration..."
cat >> src/main/resources/application.properties << 'EOL'
spring.ai.mcp.client.streamable-http.connections.backoffice.url=http://localhost:8083

# Document processing model
ai.agent.document.model=global.anthropic.claude-sonnet-4-5-20250929-v1:0
EOL

# echo "Opening application.properties in VS Code..."
# code src/main/resources/application.properties

echo "Files copied and configurations updated successfully."

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..
