# JVM Analysis Service

A Spring Boot microservice that provides automated JVM performance analysis using AI-powered recommendations. The service processes alert webhooks, retrieves thread dumps and profiling data, generates flame graphs, and provides intelligent analysis using AWS Bedrock.

## Features

- **Automated JVM Analysis**: Processes performance alerts and generates comprehensive analysis reports
- **AI-Powered Recommendations**: Uses AWS Bedrock (Claude 4 Sonnet) for intelligent performance insights
- **Flame Graph Generation**: Converts profiling data to interactive HTML flame graphs
- **S3 Integration**: Stores and retrieves profiling data, thread dumps, and analysis results
- **Resilient Design**: Built-in retry mechanisms for external service calls

## Architecture

### Components

- **JvmAnalysisController**: REST API endpoint for webhook processing
- **JvmAnalysisService**: Core business logic orchestrating the analysis workflow
- **AIRecommendation**: AWS Bedrock integration for AI-powered analysis
- **FlameGraphConverter**: Converts collapsed profiling data to HTML flame graphs
- **S3Connector**: Handles all S3 operations for data storage and retrieval

### Workflow

1. Receives alert webhook with pod information
2. Retrieves thread dump from target pod
3. Fetches latest profiling data from S3
4. Converts profiling data to flame graph
5. Analyzes performance using AI recommendations
6. Stores results (thread dump, flame graph, analysis) in S3

## API Reference

### POST /webhook

Processes performance alert webhooks and triggers JVM analysis.

**Request Body:**
```json
{
  "alerts": [
    {
      "labels": {
        "pod": "my-app-pod-123",
        "instance": "10.0.1.100:8080"
      }
    }
  ]
}
```

**Response:**
```json
{
  "message": "Processed alerts",
  "count": 1
}
```

**Status Codes:**
- `200 OK`: Successfully processed alerts
- `400 Bad Request`: Invalid request format
- `500 Internal Server Error`: Processing failed

### Health Endpoints

- `GET /actuator/health`: Application health status
- `GET /health`: Custom health endpoint for readiness probe

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for services | `us-east-1` |
| `AWS_S3_BUCKET` | S3 bucket for data storage | `default_bucket_name` |
| `AWS_S3_PREFIX_ANALYSIS` | S3 prefix for analysis results | `analysis/` |
| `AWS_S3_PREFIX_PROFILING` | S3 prefix for profiling data | `profiling/` |
| `AWS_BEDROCK_MODEL_ID` | Bedrock model identifier | `global.anthropic.claude-sonnet-4-20250514-v1:0` |
| `AWS_BEDROCK_MAX_TOKENS` | Maximum tokens for AI analysis | `10000` |
| `THREADDUMP_URL_TEMPLATE` | Thread dump endpoint template | `http://{podIp}:8080/actuator/threaddump` |

### Application Properties

```properties
# Resilience4J retry configuration
resilience4j.retry.instances.threadDump.max-attempts=3
resilience4j.retry.instances.threadDump.wait-duration=2s
resilience4j.retry.instances.threadDump.exponential-backoff-multiplier=2
```

## Prerequisites

- Java 21+
- Maven 3.6+
- AWS Account with appropriate permissions
- S3 bucket for data storage
- AWS Bedrock access (Claude 4 Sonnet model)

### Required AWS Permissions

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
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": "arn:aws:bedrock:*:*:foundation-model/anthropic.claude-3-7-sonnet-*"
    }
  ]
}
```

## Development

### Build

```bash
mvn clean compile
```

### Test

```bash
mvn test
```

### Package

```bash
mvn clean package
```

### Run Locally

```bash
mvn spring-boot:run
```

### Docker Build

```bash
mvn compile jib:dockerBuild
```

## Deployment

### Kubernetes

1. **Set up AWS permissions:**
   ```bash
   ./k8s/enable-s3-bedrock-access.sh
   ```

2. **Deploy to cluster:**
   ```bash
   ./k8s/deploy.sh
   ```

### Manual Deployment

```bash
# Apply Kubernetes manifests
kubectl apply -f k8s/deloyment.yaml

# Wait for deployment
kubectl wait deployment jvm-analysis-service -n monitoring --for condition=Available=True --timeout=120s

# Check logs
kubectl logs -l app=jvm-analysis-service -n monitoring
```

## Monitoring

### Health Checks

- **Readiness Probe**: `GET /health` (30s initial delay, 10s interval)
- **Liveness Probe**: `GET /actuator/health` (60s initial delay, 30s interval)

### Resource Requirements

- **CPU**: 1 core (request and limit)
- **Memory**: 2Gi (request and limit)

## Data Storage

### S3 Structure

```
bucket/
├── profiling/
│   └── {pod-name}/
│       └── {date}/
│           └── {timestamp}.txt
└── analysis/
    ├── {timestamp}_profiling_{pod-name}.txt
    ├── {timestamp}_profiling_{pod-name}.html
    ├── {timestamp}_threaddump_{pod-name}.json
    └── {timestamp}_analysis_{pod-name}.md
```

## AI Analysis Output

The service generates comprehensive analysis reports including:

- **Health Status**: Overall application health rating
- **Thread Analysis**: Thread state distribution and patterns
- **Top Issues**: Critical performance problems with root causes
- **Performance Hotspots**: CPU consumers and bottlenecks from flame graphs
- **Recommendations**: Immediate and short-term improvement suggestions

## Troubleshooting

### Common Issues

1. **Thread dump retrieval fails**
   - Verify pod IP and port accessibility
   - Check actuator endpoints are enabled on target pods

2. **S3 access denied**
   - Verify AWS credentials and permissions
   - Check bucket name and region configuration

3. **Bedrock model access**
   - Ensure model is available in your region
   - Verify Bedrock permissions and quotas

### Logs

Check application logs for detailed error information:
```bash
kubectl logs -l app=jvm-analysis-service -n monitoring -f
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with appropriate tests
4. Submit a pull request

## License

This project is licensed under the MIT License.