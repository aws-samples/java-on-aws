# perf-analyzer

The brain of the agentic performance platform. Receives triggers (developer
on-demand and Grafana webhook), drives the `perf-collector` to dump JFR and
thread snapshots, queries Pyroscope for the top hot functions, calls Amazon
Bedrock via Spring AI with source-code grounding, and writes a Markdown
report to S3 alongside the raw artifacts.

The full deployment walkthrough lives in the workshop content at
`content/analysis/perf-platform/analyzer/`. This README covers build and
the contract only.

## Build

```bash
cd apps/perf-analyzer
mvn compile jib:build -Dimage=${ECR_URI}/perf-analyzer:latest
```

Multi-arch (`linux/amd64` + `linux/arm64`), Amazon Corretto 25 JRE base.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/analyze` | Developer on-demand. Body: `{service, platform, pod or task, reason}`. |
| POST | `/api/v1/grafana-webhook` | Grafana alert payload; one analysis per firing alert. |
| GET | `/actuator/health` | Liveness + readiness probes. |
| GET | `/actuator/prometheus` | Metrics. |

Both `/api/v1/*` endpoints return `202 Accepted` with
`{analysisId, s3Prefix}`. Analysis runs asynchronously on a virtual thread.

## Environment variables

| Name | Required | Description |
|------|----------|-------------|
| `AWS_REGION` | yes | AWS Region for Bedrock, S3, ECS SDK clients. |
| `AWS_S3_BUCKET` | yes | Workshop bucket (SSM `workshop-bucket-name`). |
| `PYROSCOPE_URL` | yes | `http://pyroscope.monitoring:4040` on EKS. |
| `SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MODEL` | yes | Claude Sonnet 4.6 model id. |
| `SPRING_AI_BEDROCK_CONVERSE_CHAT_OPTIONS_MAX_TOKENS` | no | Default 10000. |
| `GITHUB_REPO_URL` | no | `https://api.github.com/repos/aws-samples/java-on-aws`. |
| `GITHUB_REPO_PATH` | no | `apps/unicorn-store-spring`. |
| `GITHUB_TOKEN` | no | GitHub PAT for private repos. |

## Flow

```
POST /api/v1/analyze or /api/v1/grafana-webhook
      │
      ▼
AnalysisService.submit  ──► 202 {analysisId, s3Prefix}
      │  (virtual thread)
      ▼
Resolve collector URL
  - EKS: pod  → nodeName → DaemonSet pod IP on that node (K8s API)
  - ECS: task → DescribeTasks → sidecar ENI private IP
      │
      ▼
Three parallel lanes (virtual threads):
  a. POST /dump{jfr}        → poll S3  → JfrParser.formatForModel
  b. POST /dump{threaddump} → poll S3  → first 200 lines
  c. PyroscopeTool.topFunctions (pre-fetched canonical prompt section)
      │
      ▼
AiService builds layered prompt, calls Bedrock via Spring AI ChatClient
      │
      ▼
S3 writes: request.json, events.md, threaddump.json, analysis.md
```

## Spring AI tools (@Tool)

- **PyroscopeTool** — top-level `@Component`. Always registered. Used both
  by `AnalysisService` to pre-fetch the canonical Pyroscope section and by
  the model to request additional windows/labels during reasoning.
- **GitHubSourceCodeTool** — nested package-private class in `AiService`.
  Instantiated only when `GITHUB_REPO_URL` is set. Lets the model look up
  methods from stacks and cite file paths and line numbers in findings.

## S3 layout

```
perf-platform/
  analysis/{platform}/{service}/{target}/{YYYYMMDD-HHMMSS-hex}/
    request.json       # normalized AnalysisRequest
    events.md          # JfrParser Markdown (model input, captured)
    threaddump.json    # raw Thread.print wrapped in JSON
    analysis.md        # Markdown report (model output)
  profiling/{platform}/{service}/{target}/
    dump-{jobId}.jfr   # collector drop consumed by the JFR lane
    dump-{jobId}.json  # thread dump drop consumed by the thread-dump lane
```

## JFR events extracted

`jdk.ExecutionSample`, `jdk.CPULoad`, `jdk.GCHeapSummary`, `jdk.JVMInformation`,
`jdk.GCPhasePause`, `jdk.Compilation`, `jdk.Deoptimization`,
`jdk.JavaMonitorEnter`, `jdk.SafepointBegin`, `jdk.ContainerConfiguration`.

Each produces top-5 aggregates for model input, not raw events.
