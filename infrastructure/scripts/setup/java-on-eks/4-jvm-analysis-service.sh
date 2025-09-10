#!/bin/bash

BASE_DIR="/home/ec2-user/environment/jvm-analysis-service"

echo "Creating JVM Analysis Service ..."
mkdir -p "$BASE_DIR"

cat > "$BASE_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.5.5</version>
        <relativePath/>
    </parent>
    <groupId>com.unicorn</groupId>
    <artifactId>jvm-analysis-service</artifactId>
    <version>1.0.0</version>
    <name>jvm-analysis-service</name>
    <description>JVM Analysis Service</description>

    <properties>
        <java.version>21</java.version>
        <aws.sdk.version>2.33.4</aws.sdk.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>s3</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>bedrockruntime</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
            <plugin>
                <groupId>com.googlecode.maven-download-plugin</groupId>
                <artifactId>download-maven-plugin</artifactId>
                <version>1.13.0</version>
                <executions>
                    <execution>
                        <id>download-jfr-converter</id>
                        <phase>generate-resources</phase>
                        <goals>
                            <goal>wget</goal>
                        </goals>
                        <configuration>
                            <url>https://github.com/async-profiler/async-profiler/releases/download/v4.1/jfr-converter.jar</url>
                            <outputDirectory>${project.build.directory}/classes/async-profiler/lib</outputDirectory>
                            <outputFileName>jfr-converter.jar</outputFileName>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>com.google.cloud.tools</groupId>
                <artifactId>jib-maven-plugin</artifactId>
                <version>3.4.6</version>
                <configuration>
                    <from>
                        <image>amazoncorretto:21-alpine</image>
                    </from>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
EOF

mkdir -p "$BASE_DIR/src/main/java/com/unicorn/jvm"

cat > "$BASE_DIR/src/main/java/com/unicorn/jvm/JvmAnalysisService.java" << 'EOF'
package com.unicorn.jvm;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@SpringBootApplication
@RestController
public class JvmAnalysisService {

    private static final Logger logger = LoggerFactory.getLogger(JvmAnalysisService.class);

    private final BedrockRuntimeClient bedrockClient;
    private final S3Client s3Client;
    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${aws.s3.bucket:default_bucket_name}")
    private String s3Bucket;

    @Value("${aws.s3.prefix.analysis:analysis/}")
    private String s3PrefixAnalysis;

    @Value("${aws.s3.prefix.profiling:profiling/}")
    private String s3PrefixProfiling;

    @Value("${aws.bedrock.model_id:us.anthropic.claude-3-7-sonnet-20250219-v1:0}")
    private String modelId;

    @Value("${aws.bedrock.max_tokens:10000}")
    private int maxTokens;

    public JvmAnalysisService() {
        this.s3Client = S3Client.builder().build();
        this.bedrockClient = BedrockRuntimeClient.builder().build();
    }

    public static void main(String[] args) {
        SpringApplication.run(JvmAnalysisService.class, args);
    }

    @PostMapping("/webhook")
    public Map<String, Object> handleWebhook(@RequestBody JsonNode request) {
        int count = 0;
        for (JsonNode alert : request.get("alerts")) {
            try {
                long startTime = System.currentTimeMillis();
                JsonNode labels = alert.get("labels");

                JsonNode podNode = labels.get("pod");
                JsonNode instanceNode = labels.get("instance");

                if (podNode == null || instanceNode == null) {
                    logger.warn("Skipping alert - missing required labels. Available labels: {}", labels);
                    continue;
                }

                String podName = podNode.asText();
                String podIp = instanceNode.asText();

                if (podName.isEmpty() || podIp.isEmpty()) {
                    logger.warn("Skipping alert - empty pod name or IP. Pod: {}, IP: {}", podName, podIp);
                    continue;
                }

                logger.info("Starting analysis for pod: {}", podName);

                long threadDumpStart = System.currentTimeMillis();
                String threadDump = getThreadDump(podIp);
                logger.info("Thread dump retrieved in: {}ms", (System.currentTimeMillis() - threadDumpStart));

                long profilingStart = System.currentTimeMillis();
                String profilingData = getLatestProfilingData(podName);
                logger.info("Profiling data retrieved in: {}ms", (System.currentTimeMillis() - profilingStart));

                long analysisStart = System.currentTimeMillis();
                String analysis = analyzeWithSpringAI(threadDump, profilingData);
                logger.info("AI analysis completed in: {}ms", (System.currentTimeMillis() - analysisStart));

                long storeStart = System.currentTimeMillis();
                storeResults(podName, threadDump, analysis);
                logger.info("Results stored in: {}ms", (System.currentTimeMillis() - storeStart));

                logger.info("Total processing time: {}ms", (System.currentTimeMillis() - startTime));
                count++;
            } catch (Exception e) {
                logger.error("Failed to process alert: {}", e.getMessage());
            }
        }
        return Map.of("message", "Processed alerts", "count", count);
    }

    @GetMapping("/health")
    public String health() { return "OK"; }

    private String analyzeWithSpringAI(String threadDump, String profilingData) {
        try {
            String systemPrompt = """
                You are an expert in Java performance analysis with extensive experience diagnosing production issues.
                Analyze thread dumps and profiling data to identify performance bottlenecks and provide actionable recommendations.
                Be thorough, specific, and focus on practical solutions.
                """;

            String userPrompt = String.format("""
                Analyze this Java thread dumps and profiling performance data and provide a focused report:

                ## Health Status
                Rate: Healthy/Degraded/Critical with brief explanation

                ## Thread Analysis
                - Total threads: X (X%% RUNNABLE, X%% WAITING, X%% BLOCKED)
                - Key patterns: Describe what threads are doing and why
                - Bottlenecks: Identify specific thread contention or blocking issues

                ## Top Issues (max 3)
                For each critical issue found:
                - **Problem**: Specific technical issue with affected components
                - **Root Cause**: Why this is happening (code/config/resource issue)
                - **Impact**: Quantified performance/stability effect
                - **Fix**: Concrete action with implementation details

                ## Performance Hotspots
                From flamegraph analysis:
                - Top 3 CPU consumers with method names and sample counts
                - Memory allocation patterns and potential leaks
                - I/O bottlenecks (database, network, file operations)
                - Lock contention areas with specific synchronization points

                ## Recommendations
                **Immediate (< 1 day)**:
                - 3 quick configuration or code changes

                **Short-term (< 1 week)**:
                - 3 architectural improvements with expected impact

                **Thread Dump:**
                %s

                **Flamegraph Data:**
                %s

                Provide specific method names, class names, and quantified metrics where possible.
                Keep response under 5KB but include enough detail for actionable insights.
                """, threadDump, profilingData);

            Message systemMessage = Message.builder()
                .role(ConversationRole.USER)
                .content(ContentBlock.fromText(systemPrompt))
                .build();

            Message userMessage = Message.builder()
                .role(ConversationRole.USER)
                .content(ContentBlock.fromText(userPrompt))
                .build();

            ConverseRequest request = ConverseRequest.builder()
                .modelId(modelId)
                .messages(systemMessage, userMessage)
                .inferenceConfig(InferenceConfiguration.builder()
                    .maxTokens(maxTokens)
                    .build())
                .build();

            ConverseResponse response = bedrockClient.converse(request);
            return response.output().message().content().get(0).text();

        } catch (Exception e) {
            return String.format("""
                # Thread Dump Analysis Report

                **Generated:** %s

                **Error:** AI analysis failed - %s

                ## Inputs
                - Thread dump size: %d characters
                - Profiling data size: %d characters

                Please review manually or retry analysis.
                """,
                LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME),
                e.getMessage(),
                threadDump.length(),
                profilingData.length()
            );
        }
    }

    private String convertToFlamegraph(String collapsedData) throws IOException, InterruptedException {
        Path tempDir = Files.createTempDirectory("flamegraph_");
        Path inputFile = tempDir.resolve("collapsed.txt");
        Path outputFile = tempDir.resolve("flamegraph.html");

        try {
            Files.write(inputFile, collapsedData.getBytes());

            Process process = new ProcessBuilder(
                "java", "-jar", "/app/resources/async-profiler/lib/jfr-converter.jar",
                "-o", "html", inputFile.toString(), outputFile.toString()
            ).start();

            if (process.waitFor() == 0 && Files.exists(outputFile)) {
                return Files.readString(outputFile);
            }
            throw new RuntimeException("Flamegraph conversion failed");
        } finally {
            Files.deleteIfExists(inputFile);
            Files.deleteIfExists(outputFile);
            Files.deleteIfExists(tempDir);
        }
    }

    private String getThreadDump(String podIp) {
        for (int attempt = 1; attempt <= 3; attempt++) {
            try {
                return restTemplate.getForObject("http://" + podIp + ":8080/actuator/threaddump", String.class);
            } catch (Exception e) {
                if (attempt == 3) return "Failed to get thread dump: " + e.getMessage();
                try { Thread.sleep(2000 * attempt); } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return "Thread dump interrupted";
                }
            }
        }
        return "Failed to get thread dump";
    }

    private String getLatestProfilingData(String taskPodId) {
        try {
            String currentDate = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
            String prefix = s3PrefixProfiling + taskPodId + "/" + currentDate;
            logger.info("Listing S3 objects with prefix: {}", prefix);

            long listStart = System.currentTimeMillis();
            ListObjectsV2Response listResponse = s3Client.listObjectsV2(
                ListObjectsV2Request.builder()
                    .bucket(s3Bucket)
                    .prefix(prefix)
                    .build()
            );

            Optional<S3Object> latestFile = listResponse.contents().stream()
                .filter(obj -> obj.key().endsWith(".txt"))
                .max(Comparator.comparing(S3Object::lastModified));

            logger.info("S3 listing completed in: {}ms, found {} files", (System.currentTimeMillis() - listStart), listResponse.contents().size());

            if (latestFile.isEmpty()) return "No profiling data available";

            String fullKey = latestFile.get().key();
            logger.info("Latest file: {}", fullKey);

            long downloadStart = System.currentTimeMillis();
            String content = s3Client.getObjectAsBytes(
                GetObjectRequest.builder()
                    .bucket(s3Bucket)
                    .key(fullKey)
                    .build()
            ).asUtf8String();
            logger.info("S3 download completed in: {}ms, size: {} chars", (System.currentTimeMillis() - downloadStart), content.length());

            String fileName = fullKey.substring(fullKey.lastIndexOf('/') + 1);
            String profilingTimestamp = fileName.replace(".txt", "");

            long storeStart = System.currentTimeMillis();
            String profilingKey = s3PrefixAnalysis + profilingTimestamp + "_profiling_" + taskPodId + ".txt";
            s3Client.putObject(
                PutObjectRequest.builder()
                    .bucket(s3Bucket)
                    .key(profilingKey)
                    .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(content)
            );
            logger.info("Profiling data stored in: {}ms", (System.currentTimeMillis() - storeStart));

            long flamegraphStart = System.currentTimeMillis();
            String flamegraph = convertToFlamegraph(content);
            logger.info("Flamegraph conversion completed in: {}ms", (System.currentTimeMillis() - flamegraphStart));

            long flamegraphStoreStart = System.currentTimeMillis();
            String flamegraphKey = s3PrefixAnalysis + profilingTimestamp + "_profiling_" + taskPodId + ".html";
            s3Client.putObject(
                PutObjectRequest.builder()
                    .bucket(s3Bucket)
                    .key(flamegraphKey)
                    .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(flamegraph)
            );
            logger.info("Flamegraph stored in: {}ms", (System.currentTimeMillis() - flamegraphStoreStart));

            return String.format("File: %s\nFlamegraph (Top Performance Hotspots):\n%s", fileName, flamegraph);
        } catch (Exception e) {
            return "Failed to read profiling data: " + e.getMessage();
        }
    }

    private void storeResults(String taskPodId, String threadDump, String analysis) {
        try {
            String currentTimestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"));

            s3Client.putObject(
                PutObjectRequest.builder()
                    .bucket(s3Bucket)
                    .key(s3PrefixAnalysis + currentTimestamp + "_threaddump_" + taskPodId + ".json")
                    .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(threadDump)
            );
            s3Client.putObject(
                PutObjectRequest.builder()
                    .bucket(s3Bucket)
                    .key(s3PrefixAnalysis + currentTimestamp + "_analysis_" + taskPodId + ".md")
                    .build(),
                software.amazon.awssdk.core.sync.RequestBody.fromString(analysis)
            );
        } catch (Exception e) {
            logger.error("Failed to store results: {}", e.getMessage());
        }
    }
}
EOF

echo "Building and pushing a container image ..."
cd "$BASE_DIR"
ECR_URI=$(aws ecr describe-repositories --repository-names jvm-analysis-service | jq --raw-output '.repositories[0].repositoryUri')
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URI

mvn compile jib:build -Dimage=$ECR_URI:latest

echo "Adding Pod Identity ..."
CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)

if ! aws eks list-pod-identity-associations --cluster-name $CLUSTER_NAME --query "associations[?serviceAccount=='jvm-analysis-service' && namespace=='monitoring']" --output text | grep -q .; then
    aws eks create-pod-identity-association \
        --cluster-name $CLUSTER_NAME \
        --namespace monitoring \
        --service-account jvm-analysis-service \
        --role-arn $(aws iam get-role --role-name jvm-analysis-service-eks-pod-role --query 'Role.Arn' --output text)
fi

echo "Deploying to EKS ..."
mkdir -p "$BASE_DIR/k8s"

S3_BUCKET=$(aws ssm get-parameter --name unicornstore-lambda-bucket-name --query 'Parameter.Value' --output text)

cat <<EOF > "$BASE_DIR/k8s/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jvm-analysis-service
  namespace: monitoring
  labels:
    app: jvm-analysis-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jvm-analysis-service
  template:
    metadata:
      labels:
        app: jvm-analysis-service
    spec:
      serviceAccountName: jvm-analysis-service
      containers:
      - name: jvm-analysis-service
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
        image: ${ECR_URI}:latest
        ports:
        - containerPort: 8080
        env:
        - name: AWS_REGION
          value: "${AWS_REGION:-us-east-1}"
        - name: AWS_S3_BUCKET
          value: "${S3_BUCKET}"
        - name: AWS_S3_PREFIX_ANALYSIS
          value: "analysis/"
        - name: AWS_S3_PREFIX_PROFILING
          value: "profiling/"
        - name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL
          value: "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
        - name: SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MAX_TOKENS
          value: "10000"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: jvm-analysis-service
  namespace: monitoring
  labels:
    app: jvm-analysis-service
spec:
  selector:
    app: jvm-analysis-service
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jvm-analysis-service
  namespace: monitoring
EOF

kubectl apply -f "$BASE_DIR/k8s/deployment.yaml"
