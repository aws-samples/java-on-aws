# Run modes
- Simple chat
- Chat with local memory
- Chat with external memory

## Examples HTTP requests
chat-requests.http

## Prerequisite for external memory: PostgreSQL, for application started locally without container
```
docker run --name my-postgres \
-e POSTGRES_DB=ai-agent-db \
-e POSTGRES_USER=chatuser \
-e POSTGRES_PASSWORD=chatpass \
-p 5432:5432 \
-d postgres:16
```

## Build Docker Image with JIB plugin
- mvn compile jib:dockerBuild

## Run postgres and spring-ai-agent containers
docker-compose up

