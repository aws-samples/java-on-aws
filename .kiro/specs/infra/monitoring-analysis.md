# Monitoring & JVM Analysis - Workshop Comparison

## Overview

Analysis of monitoring and JVM setup across original workshops. New infrastructure (`infra/`) has none of these components yet.

---

## Monitoring by Workshop Type

| Component | java-on-aws | java-on-eks | java-ai-agents | spring-ai |
|-----------|-------------|-------------|----------------|-----------|
| Prometheus | ✅ | ✅ | ❌ | ✅ |
| Grafana | ✅ | ✅ | ❌ | ✅ |
| JVM Dashboard | ✅ | ✅ | ❌ | ❌ |
| HTTP Dashboard | ❌ | ✅ | ❌ | ❌ |
| Thread Dump Lambda | ✅ | ❌ | ❌ | ❌ |
| JVM Analysis Service | ❌ | ✅ | ❌ | ❌ |
| Async Profiler | ❌ | ✅ | ❌ | ❌ |
| S3 Profiling Storage | ❌ | ✅ | ❌ | ❌ |

---

## Script Flow

### java-on-aws Bootstrap

```
ide.sh → app.sh → eks.sh → monitoring.sh → monitoring-jvm.sh
```

### java-on-eks Bootstrap

```
ide.sh → app.sh → eks.sh → monitoring.sh → java-on-eks/1-app.sh → grafana-alerting.sh → grafana-dashboard-http.sh
```

Optional profiling flow:
```
java-on-eks/3-profiling.sh → java-on-eks/4-jvm-analysis-service.sh
```

---

## Script Details

### `monitoring.sh` - Base Monitoring Stack

**Creates:**
- K8s namespace: `monitoring`
- Prometheus (Helm chart) - ClusterIP, 24h retention
- Grafana (Helm chart) - LoadBalancer, 10Gi PVC
- Grafana secret from Secrets Manager (`unicornstore-ide-password-lambda`)
- Prometheus datasource ConfigMap

**AWS Resources:** None (K8s only)

### `monitoring-jvm.sh` - JVM Thread Monitoring (java-on-aws)

**Creates:**
- Updates Lambda function code (`unicornstore-thread-dump-lambda`)
- Grafana folder: "Unicorn Store Dashboards"
- JVM Metrics dashboard (thread count, memory usage)
- Contact point: `lambda-webhook` → API Gateway
- Alert rule: threads > 200 triggers Lambda
- Notification policy

**AWS Resources:**
- Lambda function update (code deployment)
- Uses existing API Gateway (`unicornstore-thread-dump-api`)

### `java-on-eks/1-app.sh` - Baseline App Deployment

**Creates:**
- Simplified Dockerfile (no monitoring)
- K8s Deployment, Service, Ingress
- Docker image: `unicorn-store-spring:baseline`

**AWS Resources:**
- ECR image push

### `java-on-eks/3-profiling.sh` - Async Profiler Setup

**Creates:**
- Dockerfile with async-profiler 4.1
- K8s PersistentVolume/PVC for S3 (Mountpoint S3 CSI)
- Updated deployment with profiler agent
- Docker image: `unicorn-store-spring:profiling`

**AWS Resources:**
- ECR image push
- S3 bucket access (via existing `unicornstore-lambda-bucket-name`)

### `java-on-eks/4-jvm-analysis-service.sh` - AI Analysis Service

**Creates:**
- Complete Spring Boot service (`jvm-analysis-service`)
- ECR repository + image
- K8s Deployment, Service, ServiceAccount
- Pod Identity Association

**AWS Resources:**
- ECR image push
- Pod Identity Association (`jvm-analysis-service-eks-pod-role`)

### `java-on-eks/grafana-alerting.sh` - HTTP Rate Alerting

**Creates:**
- Grafana folder: "JVM Analysis"
- Contact point: `jvm-analysis-webhook` → K8s service
- Alert rule: POST rate > 20 req/s triggers analysis
- Notification policy

**AWS Resources:** None (K8s/Grafana only)

### `java-on-eks/grafana-dashboard-http.sh` - HTTP Dashboard

**Creates:**
- HTTP Metrics dashboard (POST request rate)

**AWS Resources:** None (Grafana only)

### `jmx-bedrock-setup.sh` - Full ECS+EKS Deployment

**Creates:**
- ECR repository (if not exists)
- ECS Cluster, Task Definition, Service
- ALB, Target Group, Listener, Security Groups
- EKS Deployment, Service, Ingress
- Prometheus scrape config update

**AWS Resources:**
- ECR repository
- ECS Cluster + Service
- ALB + Target Group
- Security Groups

---

## AWS Resources Created by Scripts

| Script | ECR | ECS | ALB | Lambda | Pod Identity | S3 |
|--------|-----|-----|-----|--------|--------------|-----|
| monitoring.sh | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| monitoring-jvm.sh | ❌ | ❌ | ❌ | ✅ update | ❌ | ❌ |
| java-on-eks/1-app.sh | ✅ push | ❌ | ❌ | ❌ | ❌ | ❌ |
| java-on-eks/3-profiling.sh | ✅ push | ❌ | ❌ | ❌ | ❌ | ✅ access |
| java-on-eks/4-jvm-analysis-service.sh | ✅ push | ❌ | ❌ | ❌ | ✅ create | ❌ |
| jmx-bedrock-setup.sh | ✅ create | ✅ create | ✅ create | ❌ | ❌ | ❌ |

---

## K8s Resources Created

### Prometheus/Grafana (monitoring.sh)

```yaml
Namespace: monitoring
Deployments: prometheus-server, grafana
Services: prometheus-server (ClusterIP), grafana (LoadBalancer)
Secrets: grafana-admin
ConfigMaps: prometheus-datasource
PVC: grafana (10Gi gp3)
```

### JVM Analysis Service (4-jvm-analysis-service.sh)

```yaml
Namespace: monitoring
Deployment: jvm-analysis-service
Service: jvm-analysis-service (ClusterIP)
ServiceAccount: jvm-analysis-service
```

### Profiling Storage (3-profiling.sh)

```yaml
PersistentVolume: s3-profiling-pv (S3 CSI)
PersistentVolumeClaim: s3-profiling-pvc (unicorn-store-spring namespace)
```

---

## Grafana Dashboards

| Dashboard | Folder | Workshop | Panels |
|-----------|--------|----------|--------|
| JVM Metrics - EKS & ECS | Unicorn Store Dashboards | java-on-aws | Thread count, Memory, Thread timeline |
| HTTP Metrics | JVM Analysis | java-on-eks | POST request rate |

---

## Grafana Alerts

| Alert | Threshold | Action | Workshop |
|-------|-----------|--------|----------|
| High JVM Threads | > 200 threads | Lambda → Thread dump | java-on-aws |
| High HTTP POST Rate | > 20 req/s | K8s service → AI analysis | java-on-eks |

---

## Dependencies

### CDK-Created Resources Used by Scripts

| Resource | Created By | Used By |
|----------|------------|---------|
| `unicornstore-ide-password-lambda` | VSCodeIde | monitoring.sh, monitoring-jvm.sh |
| `unicornstore-thread-dump-lambda` | InfrastructureMonitoringJVM | monitoring-jvm.sh |
| `unicornstore-thread-dump-api` | InfrastructureMonitoringJVM | monitoring-jvm.sh |
| `unicornstore-lambda-bucket-name` | InfrastructureCore | 3-profiling.sh, 4-jvm-analysis-service.sh |
| `jvm-analysis-service-eks-pod-role` | InfrastructureJvmAnalysis | 4-jvm-analysis-service.sh |
| `unicorn-store-spring` ECR | InfrastructureContainers | 1-app.sh, 3-profiling.sh |
| `jvm-analysis-service` ECR | InfrastructureJvmAnalysis | 4-jvm-analysis-service.sh |

---

## New Infrastructure Gaps

### Missing CDK Constructs

| Construct | Purpose | Priority |
|-----------|---------|----------|
| InfrastructureMonitoringJVM | Thread dump Lambda + API Gateway | LOW |
| InfrastructureJvmAnalysis | JVM analysis ECR + Pod role | LOW |

### Missing Scripts

| Script | Purpose | Priority |
|--------|---------|----------|
| `monitoring.sh` | Prometheus + Grafana | MEDIUM |
| `monitoring-jvm.sh` | JVM dashboards + alerts | LOW |
| `java-on-eks/*.sh` | Profiling + analysis | LOW |

---

## Implementation Notes

### Monitoring Stack (monitoring.sh)

- Pure K8s/Helm deployment, no CDK changes needed
- Requires: EKS cluster, Secrets Manager secret
- Can be added to `infra/scripts/setup/monitoring.sh`

### JVM Monitoring (monitoring-jvm.sh)

- Requires CDK: Lambda function, API Gateway, VPC Endpoint
- Complex: Private API Gateway with VPC endpoint
- Consider: Simplify to K8s-only solution (like java-on-eks)

### JVM Analysis (java-on-eks)

- Self-contained K8s solution
- Requires: ECR, Pod Identity role, S3 bucket
- Simpler than Lambda-based approach

---

*Generated: December 2025*


---

## CloudWatch-Native Monitoring (Modernization Option)

Replace OSS Prometheus/Grafana with AWS-native services. Better for workshops demonstrating AWS capabilities.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Metrics Sources                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ALB ────────────────────► CloudWatch Metrics (automatic)          │
│                            - RequestCount                           │
│                            - TargetResponseTime                     │
│                            - HTTPCode_Target_2XX/4XX/5XX           │
│                                                                     │
│  Spring Boot App ─────────► CloudWatch Custom Metrics              │
│  (Micrometer CloudWatch)    - jvm_threads_current                  │
│                             - jvm_memory_used                       │
│                             - http_server_requests                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      Alerting Pipeline                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  CloudWatch Alarm ──► SNS Topic ──► Lambda Function URL            │
│       │                                    │                        │
│       │                              ┌─────┴─────┐                  │
│       │                              ▼           ▼                  │
│       │                          Lambda    AgentCore Runtime        │
│       │                        (thread     (AI-powered              │
│       │                         dump)       analysis)               │
│       │                                                             │
│  Alarms:                                                            │
│  - ALB RequestCount > 20/s (1 min period)                          │
│  - jvm_threads_current > 200                                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | AWS Service |
|-----------|---------|-------------|
| ALB Metrics | Request rate, latency, errors | CloudWatch (automatic) |
| JVM Metrics | Thread count, memory, GC | Micrometer → CloudWatch |
| Alerting | Threshold-based triggers | CloudWatch Alarms |
| Notification | Fan-out to handlers | SNS |
| Webhook Handler | Thread dump / AI analysis | Lambda or AgentCore Runtime |

### Metric Sources

#### ALB Metrics (Automatic)

No configuration needed. Available immediately when ALB is created.

```
Namespace: AWS/ApplicationELB
Metrics:
  - RequestCount
  - TargetResponseTime
  - HTTPCode_Target_2XX_Count
  - HTTPCode_Target_5XX_Count
Dimensions:
  - LoadBalancer
  - TargetGroup
```

#### JVM Metrics (Micrometer CloudWatch Registry)

Add to Spring Boot application:

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-cloudwatch2</artifactId>
</dependency>
```

```yaml
# application.yml
management:
  cloudwatch:
    metrics:
      export:
        enabled: true
        namespace: UnicornStore
        step: 1m
```

```
Namespace: UnicornStore (custom)
Metrics:
  - jvm_threads_current
  - jvm_threads_daemon
  - jvm_memory_used
  - jvm_gc_pause
  - http_server_requests_seconds_count
```

### CloudWatch Alarms

#### High Request Rate Alarm

```typescript
// CDK
new cloudwatch.Alarm(this, 'HighRequestRateAlarm', {
  metric: alb.metrics.requestCount({
    period: Duration.minutes(1),
    statistic: 'Sum',
  }),
  threshold: 1200, // 20 req/s * 60s
  evaluationPeriods: 1,
  comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  alarmName: 'unicornstore-high-request-rate',
  actionsEnabled: true,
});
alarm.addAlarmAction(new cloudwatch_actions.SnsAction(snsTopic));
```

#### High Thread Count Alarm

```typescript
// CDK
new cloudwatch.Alarm(this, 'HighThreadCountAlarm', {
  metric: new cloudwatch.Metric({
    namespace: 'UnicornStore',
    metricName: 'jvm_threads_current',
    statistic: 'Maximum',
    period: Duration.minutes(1),
  }),
  threshold: 200,
  evaluationPeriods: 2,
  comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  alarmName: 'unicornstore-high-thread-count',
});
alarm.addAlarmAction(new cloudwatch_actions.SnsAction(snsTopic));
```

### Webhook Handlers

#### Option 1: Lambda Function URL

Direct HTTP endpoint, no API Gateway needed.

```typescript
// CDK
const threadDumpLambda = new lambda.Function(this, 'ThreadDumpLambda', {
  runtime: lambda.Runtime.JAVA_21,
  handler: 'com.example.ThreadDumpHandler::handleRequest',
  code: lambda.Code.fromAsset('lambda/thread-dump'),
  timeout: Duration.seconds(30),
});

const functionUrl = threadDumpLambda.addFunctionUrl({
  authType: lambda.FunctionUrlAuthType.NONE, // or AWS_IAM
});

// SNS subscription to Lambda
snsTopic.addSubscription(new subscriptions.LambdaSubscription(threadDumpLambda));
```

#### Option 2: AgentCore Runtime

AI-powered analysis using Bedrock AgentCore.

```typescript
// CDK - SNS to HTTPS endpoint
snsTopic.addSubscription(new subscriptions.UrlSubscription(
  agentCoreEndpoint,
  { protocol: sns.SubscriptionProtocol.HTTPS }
));
```

AgentCore agent can:
- Analyze thread dumps with Bedrock models
- Correlate with recent deployments
- Suggest remediation actions
- Store analysis in S3

### Migration from Grafana Alerts

| Grafana Alert | CloudWatch Equivalent |
|---------------|----------------------|
| `jvm_threads_current > 200` | CloudWatch Alarm on custom metric `UnicornStore/jvm_threads_current` |
| `rate(http_requests_total[1m]) > 20` | CloudWatch Alarm on `AWS/ApplicationELB/RequestCount` |
| Contact point → Lambda webhook | SNS → Lambda Function URL |
| Contact point → K8s service | SNS → AgentCore Runtime HTTPS endpoint |

### IAM Requirements

#### Lambda Execution Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": ["eks:DescribeCluster"],
      "Resource": "*"
    }
  ]
}
```

#### Spring Boot App (for Micrometer CloudWatch)

Pod Identity or IRSA with:

```json
{
  "Effect": "Allow",
  "Action": ["cloudwatch:PutMetricData"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "cloudwatch:namespace": "UnicornStore"
    }
  }
}
```

### Comparison: OSS vs CloudWatch-Native

| Aspect | OSS (Prometheus/Grafana) | CloudWatch-Native |
|--------|--------------------------|-------------------|
| Setup complexity | Helm charts, PVCs | CDK constructs |
| Operational overhead | Manage pods, storage | Fully managed |
| Cost | Compute + storage | Pay per metric/alarm |
| Retention | 24h (configurable) | 15 months |
| Dashboards | Grafana (flexible) | CloudWatch Dashboards |
| Alerting | Grafana Alerting | CloudWatch Alarms + SNS |
| JVM metrics | Prometheus scrape | Micrometer push |
| Workshop value | OSS tooling | AWS-native services |

### Implementation Priority

| Component | Priority | Effort |
|-----------|----------|--------|
| ALB metrics + alarm | HIGH | LOW (automatic) |
| Micrometer CloudWatch | HIGH | MEDIUM (app change) |
| JVM thread alarm | HIGH | LOW (CDK) |
| SNS → Lambda | MEDIUM | LOW (CDK) |
| SNS → AgentCore | LOW | MEDIUM (AgentCore setup) |
| CloudWatch Dashboard | LOW | LOW (CDK) |

---

*Updated: December 2025*
