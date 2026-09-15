# perf-optimizer

Bedrock-backed **optimization agent** exposed over **MCP** (SSE). Separate from
`perf-analyzer` (which powers the analysis labs) so those stay intact.

**Thin-slice POC:** one MCP tool, `optimizeService(service, windowMinutes)`.
It reads live Pyroscope CPU + wall profiles for the service and asks Amazon
Bedrock — grounded by a system prompt encoding the *measured* heuristics
(right-size off RSS+non-heap, keep SerialGC on 1-vCPU small heap, AOT ~4s /
CRaC ~0.2s / in-place CPU boost) — for a right-size / GC / startup plan.
Claude Code on the dev EC2 is the MCP client and implements the plan.

No collector dependency (queries Pyroscope directly), no auth (POC).

## Build + deploy (on the amd64 "ide" instance)

Delivered via S3 (see `deploy-optimizer.sh`):

```bash
aws s3 cp s3://<workshop-bucket>/perf-scenario/deploy-optimizer.sh ~/deploy-optimizer.sh
bash ~/deploy-optimizer.sh
```

## Connect Claude Code

```bash
kubectl -n monitoring port-forward svc/perf-optimizer 8080:8080 &
claude mcp add --transport sse perf-optimizer http://localhost:8080/sse
# then: "use perf-optimizer to optimize unicorn-store-spring-eks"
```

## Next phases (not in this slice)
- Emit **applyable artifacts** (right-sized deployment patch + AOT/CRaC Dockerfile).
- Add **JFR** heap/GC/container signals (via sidecar `/dump` or exec), not just Pyroscope.
- **KB grounding** (`spring-ai-starter-vector-store-bedrock-knowledgebase` +
  `QuestionAnswerAdvisor`) seeded with golden Dockerfiles + the right-sizing playbook.
- Prod auth (SigV4/Cognito) — see `java-spring-ai-agents` `SigV4McpConfig`.
