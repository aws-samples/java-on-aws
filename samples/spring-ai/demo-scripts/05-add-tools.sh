#!/bin/bash

# Script to add Tools functionality to the assistant app

# Set the source folder path
SOURCES_FOLDER="/Users/bezsonov/sources/workshops/java-on-aws/samples/spring-ai"

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

# Create service directory if it doesn't exist
mkdir -p src/main/java/com/example/assistant/service

# Copy DateTimeService.java
echo "Copying DateTimeService.java..."
if [ -f "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/DateTimeService.java" ]; then
    cp "$SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/DateTimeService.java" src/main/java/com/example/assistant/service/
    echo "DateTimeService.java copied successfully."
else
    echo "Error: DateTimeService.java not found at $SOURCES_FOLDER/assistant/src/main/java/com/example/assistant/service/."
    echo "Please ensure the file exists at the specified location."
    exit 1
fi

# Copy ChatService.java.5 to ChatService.java
echo "Copying ChatService.java from version 5..."
if [ -f "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.5" ]; then
    cp "$SOURCES_FOLDER/demo-scripts/ChatService/ChatService.java.5" src/main/java/com/example/assistant/service/ChatService.java
    echo "ChatService.java copied successfully."

    # Open ChatService.java in VS Code
    echo "Opening ChatService.java in VS Code..."
    code src/main/java/com/example/assistant/service/ChatService.java
else
    echo "Error: ChatService.java.5 not found at $SOURCES_FOLDER/demo-scripts/ChatService/"
    echo "Please ensure the file exists at the specified location."
    exit 1
fi

# Show git status
echo ""
echo "Git status:"
git status

echo ""
echo "Done!"
cd ..