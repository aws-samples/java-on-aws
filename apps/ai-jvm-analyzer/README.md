# AI JVM Analyzer

AI-powered JVM performance analyzer using Amazon Bedrock. Receives webhook alerts from monitoring systems (Grafana, CloudWatch), collects thread dumps and profiling data, and generates actionable performance analysis reports.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Monitoring System (Grafana/CloudWatch/Prometheus)          │
│  - Detects high CPU, memory, or thread count alerts         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ POST /webhook
┌─────────────────────────────────────────────────────────────┐
│  WebhookController                                          │
│  - Receives alert payloads with pod name and IP             │
│  - Validates alerts, filters invalid entries                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  AnalyzerService                                            │
│  - Parallel processing with Virtual Threads                 │
│  - Fetches thread dump from pod's /actuator/threaddump      │
│  - Retrieves profiling data (flamegraph) from S3            │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│  AiService              │     │  S3Repository           │
│  - Spring AI + Bedrock  │     │  - Fetch profiling data │
│  - Claude Sonnet 4      │     │  - Store analysis       │
│  - Structured prompts   │     │  - Thread dumps         │
└─────────────────────────┘     └─────────────────────────┘
```

## Project Structure

```
src/main/java/com/example/ai/jvmanalyzer/
├── Application.java       # Spring Boot entry point, beans config
├── WebhookController.java # REST endpoint for monitoring webhooks
├── AnalyzerService.java   # Orchestrates analysis workflow
├── AiService.java         # Bedrock integration via Spring AI
└── S3Repository.java      # S3 storage for profiling data and results
```

## How It Works

1. Monitoring system detects performance issue (high CPU, thread count, etc.)
2. Alert webhook sent to `/webhook` with pod name and IP address
3. Analyzer fetches thread dump from the pod's actuator endpoint
4. Retrieves latest flamegraph/profiling data from S3
5. Sends both to Claude Sonnet 4 for analysis
6. Stores thread dump, profiling data, and AI analysis report in S3

## Webhook Payload Format

```json
{
  "alerts": [
    {
      "labels": {
        "pod": "unicorn-store-spring-abc123",
        "instance": "10.0.1.50:8080"
      }
    }
  ]
}
```

## Analysis Report Contents

The AI generates a structured report including:
- Health status (Healthy/Degraded/Critical)
- Thread analysis with state distribution
- Top 3 critical issues with root cause and fix
- Performance hotspots from flamegraph
- Immediate and short-term recommendations

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Spring Boot | 4.0.1 | Application framework |
| Spring AI | 1.1.1 | Bedrock integration |
| AWS SDK | 2.40.15 | S3 client |
| Testcontainers | 2.0.3 | Integration testing |
| jqwik | 1.9.3 | Property-based testing |

## Configuration

| Property | Default | Description |
|----------|---------|-------------|
| `analyzer.thread-dump.url-template` | `http://{podIp}:8080/actuator/threaddump` | Thread dump endpoint |
| `analyzer.s3.bucket` | `ai-jvm-analyzer-bucket` | S3 bucket for storage |
| `analyzer.s3.prefix.analysis` | `analysis/` | Prefix for analysis results |
| `analyzer.s3.prefix.profiling` | `profiling/` | Prefix for profiling data |
| `spring.ai.bedrock.converse.chat.options.model` | `anthropic.claude-sonnet-4-20250514-v1:0` | Bedrock model |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_REGION` | Yes | AWS region for Bedrock and S3 |
| `AWS_S3_BUCKET` | Yes | S3 bucket name |

## Building

```bash
mvn package                    # Standard JAR
mvn package -Pnative           # Native image (GraalVM 25)
mvn jib:dockerBuild            # Container with Jib
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/webhook` | Receive monitoring alerts |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/prometheus` | Metrics |

## S3 Storage Layout

```
s3://ai-jvm-analyzer-bucket/
├── profiling/
│   └── {pod-name}/
│       └── profile-{yyyyMMdd}-{timestamp}.html   # Flamegraph data
└── analysis/
    ├── {timestamp}_threaddump_{pod-name}.json    # Raw thread dump
    ├── {timestamp}_profiling_{pod-name}.html     # Profiling snapshot
    └── {timestamp}_analysis_{pod-name}.md        # AI analysis report
```

## IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ai-jvm-analyzer-bucket",
        "arn:aws:s3:::ai-jvm-analyzer-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "bedrock:InvokeModel",
      "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
    }
  ]
}
```
