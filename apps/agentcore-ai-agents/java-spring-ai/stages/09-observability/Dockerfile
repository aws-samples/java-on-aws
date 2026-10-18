# >> Amazon Corretto 25 as the Java runtime; the Maven build creates the JAR before `docker build`
FROM public.ecr.aws/amazoncorretto/amazoncorretto:25-al2023-headless
# <<

WORKDIR /app
# >> The ADOT Java agent exports the traces; the version is pinned for reproducible images
ADD https://github.com/aws-observability/aws-otel-java-instrumentation/releases/download/v2.31.0/aws-opentelemetry-agent.jar /app/aws-opentelemetry-agent.jar
# <<
COPY target/agent-0.0.1-SNAPSHOT.jar /app/app.jar

RUN chmod 644 /app/*.jar
USER 1000

# >> `-javaagent` starts ADOT before the application; ADOT exports traces only, over OTLP/HTTP
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/aws-opentelemetry-agent.jar" \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    OTEL_LOGS_EXPORTER=none \
    OTEL_METRICS_EXPORTER=none \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
# <<
# >> AgentCore Runtime calls the HTTP service on port 8080
EXPOSE 8080
# <<
CMD ["java", "-jar", "/app/app.jar"]
