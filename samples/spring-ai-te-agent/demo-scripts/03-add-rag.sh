#!/bin/bash

# Script to add RAG functionality to the ai-agent app

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
git commit -m "add Memory"

cd ai-agent

echo "Copying VectorStoreController.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/controller/VectorStoreController.java" src/main/java/com/example/ai/agent/controller/

echo "Copying VectorStoreService.java..."
cp "$SOURCES_FOLDER/ai-agent/src/main/java/com/example/ai/agent/service/VectorStoreService.java" src/main/java/com/example/ai/agent/service/

echo "Copying ChatService.java from version 3..."
cp "$SOURCES_FOLDER/demo-scripts/Steps/ChatService.java.3" src/main/java/com/example/ai/agent/service/ChatService.java
# code src/main/java/com/example/ai/agent/ChatService.java

# Add RAG Configuration to application.properties
echo "Updating application.properties with database configuration..."
cat >> src/main/resources/application.properties << 'EOL'

# RAG Configuration
spring.ai.model.embedding=bedrock-titan
spring.ai.bedrock.titan.embedding.model=amazon.titan-embed-text-v2:0
spring.ai.bedrock.titan.embedding.input-type=text

spring.ai.vectorstore.pgvector.initialize-schema=true
spring.ai.vectorstore.pgvector.dimensions=1024
EOL

# echo "Opening application.properties in VS Code..."
# code src/main/resources/application.properties

# Update pom.xml to add RAG dependencies
echo "Updating pom.xml with RAG dependencies..."

# Create a temporary file with the new dependencies
cat > temp_dependencies.xml << 'EOL'
        <!-- RAG dependencies -->
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-vector-store</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-advisors-vector-store</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.ai</groupId>
            <artifactId>spring-ai-starter-vector-store-pgvector</artifactId>
        </dependency>
		<dependency>
			<groupId>org.springframework.ai</groupId>
			<artifactId>spring-ai-starter-model-bedrock</artifactId>
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
