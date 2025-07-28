# Run modes
- Simple chat
- Chat with local memory
- Chat with external memory

## Examples HTTP requests
chat-requests.http

## Prerequisite for external memory: PostgreSQL, for application started locally without container
```
docker run --name my-postgres \                    ✘ 125 
-e POSTGRES_DB=ai-agent-db \
-e POSTGRES_USER=chatuser \
-e POSTGRES_PASSWORD=chatpass \
-p 5432:5432 \
-d pgvector/pgvector:pg16
```

## Build Docker Image with JIB plugin
- mvn compile jib:dockerBuild

## Run postgres and spring-ai-agent containers
docker-compose up

## Observability Configuration

### Option A: Basic Monitoring (Default)
**Includes:** Prometheus metrics + Grafana dashboards + AWS X-Ray tracing

1. Use default `docker-compose.yaml` (AWS OpenTelemetry agent is automatically included in Docker image)

2. Build and start:
   ```bash
   mvn compile jib:dockerBuild
   docker-compose up
   ```

3. Access:
   - Grafana: http://localhost:3000 (admin/admin)
   - Prometheus: http://localhost:9090
   - AWS X-Ray Console: https://console.aws.amazon.com/xray/

### Option B: Open source Observability Stack (Optional)
**Includes:** Prometheus + Grafana + Tempo traces + Loki logs

1. Remove AWS OpenTelemetry agent configuration from pom.xml JIB plugin (jvmFlags section)

2. Copy observability files:
   ```bash
   cp docker-compose.yaml-zipkin docker-compose.yaml
   cp logback-spring.xml-loki src/main/resources/logback-spring.xml
   ```

3. Rebuild application:
   ```bash
   mvn compile jib:dockerBuild
   ```

4. Start full stack:
   ```bash
   docker-compose up
   ```

5. Access:
   - Grafana: http://localhost:3000 (admin/admin)
   - Prometheus: http://localhost:9090
   - Tempo: http://localhost:3200
   - Loki: http://localhost:3100

6. In Grafana Explore:
   - **Metrics**: Select Prometheus data source
   - **Traces**: Select Tempo data source
   - **Logs**: Select Loki data source

