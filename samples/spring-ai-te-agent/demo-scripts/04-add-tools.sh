#!/bin/bash

# Script to add Tools functionality to the ai-agent app

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
git commit -m "add RAG"

cd ai-agent

mkdir -p src/main/java/com/example/ai/agent/tool

echo "Copying DateTimeService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/tool/DateTimeService.java" src/main/java/com/example/ai/agent/tool/

echo "Copying WeatherService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/tool/WeatherService.java" src/main/java/com/example/ai/agent/tool/

echo "Copying ChatService.java from version 4..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.4" src/main/java/com/example/ai/agent/service/ChatService.java

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..
