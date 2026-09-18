# perf-optimizer

A **deterministic, finding-driven Java optimization advisor** for services on
Amazon EKS, exposed over **MCP** (SSE) and **REST**. Separate from `perf-analyzer`
(which powers the analysis labs) so those stay intact.

**Principle: Java computes, the model explains.** Every value that ends up in an
artifact — right-sized requests/limits, GC choice, startup levers — is computed by
code from measured facts. The model only writes rationale and fills in prose. It
never chooses a number. So `analyze` is byte-for-byte reproducible and `explain`
returns the same artifact every time (Dockerfiles are byte-identical to the golden
files in `apps/dockerfiles`).

## Pipeline

```
Prometheus ─┐
Pyroscope  ─┤► Collectors ──► Facts ──► Evaluator(catalog/findings.yaml) ──► Findings
sidecar/dump┤     (Java)                                                       │
K8s API (RO)┘                                                                  ▼
                                                     Explainer (Bedrock, structured) ──► MCP / REST
```

- **Facts** (`facts/`): typed, nullable-aware records — `WorkloadFacts` (K8s
  desired state), `RuntimeFacts` (measured memory/heap/GC/startup/uptime),
  `ProfileFacts` (CPU/wall shares), `ThreadFacts` (request-path blocking). `Facts`
  flattens to a nested map the catalog SpEL reads (memory in MiB, CPU in cores).
- **Collectors** (`collect/`): `K8sCollector` (deployments/pods/HPA, read-only),
  `PrometheusTool` (working-set floor/peak, startup), `PyroscopeCollector`
  (JIT/GC/futex shares + warm-up), `DumpCollector` (sidecar `/dump`). Each degrades
  to null independently.
- **Evaluator** (`catalog/Evaluator.java`): pure `Facts -> List<Finding>`, no I/O,
  no LLM. SpEL drives `detector`/`compute`/`gain`; `requires` gates null facts
  (NOT_EVALUABLE), guards gate dependents (BLOCKED), a detector that stops firing
  after being OPEN becomes RESOLVED. Deterministic ranking.
- **Explainer** (`explain/`): Spring AI `ChatClient` (Bedrock, temperature 0,
  structured output) writes only `rationale`/`expectedOutcome`; `TemplateRenderer`
  renders the artifact in Java (`.hbs` token substitution; golden Dockerfiles
  verbatim), `ApplyCommand` builds the exact commands.

## Interfaces (same three operations)

| Operation | MCP tool | REST | LLM? |
|---|---|---|---|
| measure  | `measure(service, windowMinutes?)` | `GET /api/v1/measure/{service}` | no |
| analyze  | `analyze(service, windowMinutes?, explain?)` | `GET /api/v1/analyze/{service}` | no (unless `explain=true`) |
| explain  | `explain(service, findingId)` | `GET /api/v1/explain/{service}/{findingId}` | yes (one finding) |

`service` is the Pyroscope `service_name` = Kubernetes Deployment name (e.g.
`unicorn-store-spring`). The legacy single-shot `optimizeService` tool
(`OptimizerTools`) is kept for backward compatibility.

Finding status: `OPEN | BLOCKED | RESOLVED | NOT_APPLICABLE | NOT_EVALUABLE`.
A re-`analyze` after a fix reports the finding **RESOLVED** with a measured
before→after delta (in-process cache; no persistence).

## Catalog schema (`src/main/resources/catalog/findings.yaml`)

```yaml
- id: memory-over-provisioned
  title: Memory limit far above measured working set
  severity: HIGH                 # LOW | MEDIUM | HIGH | CRITICAL
  effort: LOW                    # LOW=manifest, MEDIUM=image, HIGH=code
  guard: false                   # true = a prerequisite rule (e.g. profile-window-is-warm)
  detector: "limits.memory / rss.peak > 2.0"   # SpEL boolean over facts
  requires: [rss.floor, rss.peak, limits.memory]  # null -> NOT_EVALUABLE
  prereqs: [profile-window-is-warm]               # unsatisfied guard -> BLOCKED
  compute:                                        # SpEL; #roundUpMi(mi,step), #pct(from,to)
    requests.memory: "#roundUpMi(rss.floor * 1.25, 64)"
    limits.memory:   "#roundUpMi(rss.peak * 1.40, 64)"
    jvm.gc:          "cpu.limit <= 1 ? 'SerialGC' : 'G1GC'"
  evidence: [rss.floor, rss.peak, heap.committed, limits.memory, cpu.effective]
  gain: "'memory -' + #pct(limits.memory, computed['limits.memory']) + '%'"
  fix:
    kind: manifest-patch          # manifest-patch | dockerfile | source-patch | advice
    template: templates/deployment-resources.yaml.hbs
    files: [k8s/deployment.yaml]
  learnMore: https://catalog.workshops.aws/java-on-aws/en-US/optimize-containers
```

Fact paths available to SpEL: `limits.memory|cpu`, `requests.memory|cpu`,
`rss.floor|peak` (working-set MiB), `heap.used|committed`, `cpu.limit|effective`,
`startup`, `uptime`, `gc`, `image`, `resizePolicy`, `replicas`, `restarts`,
`hpa.present|metricType`, `sidecars.present`, `profile.warmupWindow|jitShare|gcShare|futexWallShare`,
`samples`, `threads.futureGetOnRequestPath|poolWaitCarriers`.

### Adding a finding

1. Add an entry to `findings.yaml` (detector + requires + compute + fix).
2. If the fix emits an artifact, add a `templates/*.hbs` (or a verbatim file for
   `dockerfile`); reference computed keys as `{{name}}` and workload facts as
   `{{deployment}}`, `{{namespace}}`, `{{current.limits.memory}}`, etc.
3. Add a JSON fixture under `src/test/resources/fixtures/` and assert the expected
   status/values in `EvaluatorTest` (and artifact assertions in `TemplateRendererTest`).
4. `mvn verify`.

## Build & deploy (on the amd64 "ide" instance)

```bash
bash infra/scripts/deploy/java-on-amazon-eks/perf-optimizer.sh
```

Builds + pushes the image (jib), applies the read-only `perf-optimizer` ClusterRole
(get/list/watch on deployments/pods/HPAs — **no write verbs**), optionally
provisions a Bedrock KB, and deploys the MCP server into `monitoring`. Grounding
falls back to the bundled `kb/*.md` when no KB is configured.

## Connect Claude Code

```bash
kubectl -n monitoring port-forward svc/perf-optimizer 8080:8080 &
cd unicorn-store-spring     # has .mcp.json, CLAUDE.md, .claude/commands
claude
# then: /analyze   → /apply memory-over-provisioned
```

The app repo's `CLAUDE.md` encodes the loop rules: analyze first; never invent
values; one branch per finding; show the diff and confirm before applying;
re-analyze and report the RESOLVED delta.

## Guarantees & scope

- The optimizer is **read-only** on the cluster (ClusterRole has no write verbs);
  all cluster writes happen from Claude Code in the app repo.
- The sidecar `/dump` used for ThreadFacts/heap stays `SYS_PTRACE`-only (no
  privileged, no hostPID).
- Out of scope (PoC): auth on MCP, Bedrock KB provisioning changes, UI.

## Notes

- **Image detection is tag-based.** The optimizer reads the app container's image
  tag (`WorkloadFacts.imageTag`); `startup-checkpointable` fires unless the tag is
  `crac`/`aot`, and flips to RESOLVED once a `:crac`/`:aot` image is deployed. Tag
  images accordingly (see `unicorn-store-spring/scripts/build.sh`).
- **`/dump` exposure.** The sidecar's `/dump` (port 9100) is reachable only in-cluster
  via the pod IP (no Service, not exposed via Ingress); the optimizer calls it with a
  short timeout and degrades to null ThreadFacts if it is absent. It runs `jcmd`
  read-only against the app JVM across the shared PID namespace (SYS_PTRACE only).
- **Virtual threads.** `/dump?kind=threads` uses `Thread.dump_to_file -format=json` so
  blocked virtual threads (which unmount and vanish from `Thread.print`) are
  enumerated — required for `blocking-call-in-request-path` to fire under load.
