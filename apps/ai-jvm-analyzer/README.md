# AI JVM Analyzer

AI-powered JVM performance analyzer using Amazon Bedrock. Receives webhook alerts from monitoring systems (Grafana), collects JFR recordings and thread dumps, and generates actionable performance analysis reports with source code references.

## Architecture

```
Grafana Alert
      │
      ▼ POST /webhook
┌──────────────────┐
│ WebhookController│
└────────┬─────────┘
         ▼
┌──────────────────┐     ┌───────────────┐
│ AnalyzerService  │────▶│ S3Repository  │
│ (virtual threads)│     │ fetch JFR,    │
│                  │     │ store results │
│ 1. Fetch JFR     │     └───────────────┘
│ 2. Parse metrics │
│ 3. Collapsed stks│     ┌───────────────┐
│ 4. HTML flamegrph│────▶│ JfrParser     │
│ 5. Thread dump   │     │ CPU, GC, JVM  │
│ 6. AI analysis   │     └───────────────┘
│ 7. Store to S3   │
└────────┬─────────┘     ┌───────────────────┐
         ▼               │ FlamegraphGenerator│
┌──────────────────┐     │ collapsed stacks + │
│ AiService        │     │ HTML flamegraph    │
│ Spring AI +      │     └───────────────────┘
│ Amazon Bedrock   │
│ Claude Sonnet 4  │
│ + GitHubSource   │
│   CodeTool       │
└──────────────────┘
```

## Project Structure

```
src/main/java/com/example/ai/jvmanalyzer/
├── Application.java          # Spring Boot entry point
├── WebhookController.java    # REST endpoint for Grafana webhooks
├── AnalyzerService.java      # Orchestrates analysis pipeline (async, virtual threads)
├── AiService.java            # Amazon Bedrock integration via Spring AI
├── GitHubSourceCodeTool.java # Spring AI @Tool — fetches source code from GitHub
├── JfrParser.java            # Extracts CPU load, GC heap, JVM info from JFR
├── FlamegraphGenerator.java  # Collapsed stacks + HTML flamegraph via jfr-converter
└── S3Repository.java         # S3 storage for JFR, profiling, analysis artifacts
```

## How It Works

1. Grafana alert fires when POST request rate exceeds threshold
2. Webhook sent to `/webhook` with pod name and IP address
3. AnalyzerService runs asynchronously on a virtual thread:
   - Retrieves latest JFR recording from S3 (with retry for in-progress files)
   - `JfrParser` extracts runtime metrics (CPU load, GC heap, JVM config) from JFR binary
   - `FlamegraphGenerator` produces collapsed stacks text and HTML flamegraph using async-profiler's `jfr-converter` library
   - Fetches thread dump from pod's actuator endpoint
   - `AiService` sends profiling summary + thread dump to Amazon Bedrock (Claude Sonnet 4)
   - If `GITHUB_REPO_URL` is configured, the model uses `GitHubSourceCodeTool` to look up source code of methods found in stack traces
4. Stores 5 artifacts per analysis to S3

## Source Code Tool

When `GITHUB_REPO_URL` is set, `AiService` registers a `GitHubSourceCodeTool` with the `ChatClient`. During analysis, the model can call this tool to fetch source files from the GitHub repository, enabling it to reference specific file paths, line numbers, and provide concrete code fixes.

- Uses GitHub REST API (`/contents/{path}`) with base64 decoding
- `GITHUB_REPO_PATH` specifies the application root within the repo
- `GITHUB_TOKEN` enables access to private repositories (optional for public repos)

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Spring Boot | 4.0.2 | Application framework |
| Spring AI | 1.1.2 | Amazon Bedrock integration |
| AWS SDK | 2.40.15 | S3 client |
| jfr-converter | 4.3 | async-profiler collapsed stacks + flamegraph |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_REGION` | Yes | AWS Region for Amazon Bedrock and S3 |
| `AWS_S3_BUCKET` | Yes | S3 bucket name |
| `GITHUB_REPO_URL` | No | GitHub API URL (e.g. `https://api.github.com/repos/aws-samples/java-on-aws`) |
| `GITHUB_REPO_PATH` | No | Application root within repo (e.g. `apps/unicorn-store-spring`) |
| `GITHUB_TOKEN` | No | GitHub PAT with `contents:read` scope (for private repos) |
| `FLAMEGRAPH_INCLUDE` | No | Regex filter for HTML flamegraph frames (e.g. `.*unicorn.*`). Only affects the visual flamegraph — collapsed stacks sent to the AI model remain unfiltered |

## S3 Storage Layout

```
s3://{bucket}/
├── profiling/{pod-name}/
│   └── profile-{yyyyMMdd}-{HHmmss}.jfr          # async-profiler JFR recordings
└── analysis/
    ├── {timestamp}.jfr                            # JFR binary (for re-analysis)
    ├── {timestamp}_profiling_{pod-name}.md         # Runtime metrics + collapsed stacks
    ├── {timestamp}_threaddump_{pod-name}.json      # Thread dump snapshot
    ├── {timestamp}_flamegraph_{pod-name}.html      # Interactive HTML flamegraph
    └── {timestamp}_analysis_{pod-name}.md          # AI-generated performance report
```

## Building

```bash
mvn compile jib:build -Dimage={ECR_URI}:latest    # Container with Jib
mvn package                                        # Standard JAR
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/webhook` | Receive Grafana alert notifications |
| GET | `/actuator/health` | Health check |
| GET | `/actuator/prometheus` | Prometheus metrics |
