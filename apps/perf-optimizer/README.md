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

```bash
bash infra/scripts/deploy/java-on-amazon-eks/perf-optimizer.sh
```

Builds + pushes the image (jib), provisions the Bedrock Knowledge Base (S3
Vectors) from the IDE role — passing the CDK-created `perf-optimizer-kb-role`,
no admin, no SSM — and deploys the MCP server. If KB provisioning is unavailable
the agent still runs, grounded on the bundled `kb/*.md` docs.

## Connect Claude Code

Register the MCP server at **user scope** (`-s user`) so it's available in any
directory, then run Claude Code **from the app source folder** (e.g.
`unicorn-store-spring/`, which holds the `Dockerfile` and `k8s/deployment.yaml`)
so Claude can find, edit, and apply the real Deployment when implementing the plan.

```bash
kubectl -n monitoring port-forward svc/perf-optimizer 8080:8080 &
claude mcp add -s user --transport sse perf-optimizer http://localhost:8080/sse

cd unicorn-store-spring        # app folder: Dockerfile + k8s/deployment.yaml
claude
# then: "use perf-optimizer to optimize unicorn-store-spring, then apply the plan"
```

## Grounding

Two paths, both wired in `OptimizerTools`:
- **Bundled docs** (default, zero perms): `kb/*.md` baked into the image and
  injected into every prompt — guarantees copy-paste-correct artifacts.
- **Managed Bedrock KB** (S3 Vectors) via `spring-ai-starter-vector-store-bedrock-knowledgebase`
  + `QuestionAnswerAdvisor`, enabled when `SPRING_AI_VECTORSTORE_BEDROCK_KNOWLEDGE_BASE_KNOWLEDGE_BASE_ID`
  is set — the deploy script provisions the KB and wires it.

## Possible extensions
- Add **JFR** heap/GC/container signals (via sidecar `/dump` or exec), not just Pyroscope.
- Prod auth (SigV4/Cognito) — see `java-spring-ai-agents` `SigV4McpConfig`.
