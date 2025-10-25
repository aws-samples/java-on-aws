#!/bin/bash

# Script to add Tools functionality to the assistant app

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

# Change to assistant directory and commit changes
echo "Committing previous changes..."
cd assistant
git add .
git commit -m "add RAG"

echo "Copying DateTimeService.java..."
cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/DateTimeService.java" src/main/java/com/example/assistant/

echo "Copying ChatService.java from version 4..."
cp "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.4" src/main/java/com/example/assistant/ChatService.java

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..
