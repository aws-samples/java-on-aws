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

# Change to ai-agent directory and commit changes
echo "Committing previous changes..."
git add .
git commit -m "add MCP"

cd ai-agent

cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/controller/ChatController.java" src/main/java/com/example/ai/agent/controller/
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/service/DocumentChatService.java" src/main/java/com/example/ai/agent/service/

echo "Updating application.properties with database configuration..."
cat >> src/main/resources/application.properties << 'EOL'

# Document processing model
ai.agent.document.model=global.anthropic.claude-sonnet-4-20250514-v1:0
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
