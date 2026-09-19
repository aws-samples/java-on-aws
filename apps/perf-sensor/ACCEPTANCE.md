# perf-sensor — §4b acceptance runbook (interactive, on the IDE)

The implementer checks (§4a, REST/no-Claude) and a functional dry-run pass on any host.
The **acceptance** below must run from a fresh `claude` on the workshop **IDE**, because it
exercises skill auto-load + the two MCP servers + run-to-run variance — none of which the
implementer host reproduces.

## 0. Prerequisites (bootstrap does these; verify)
- `perf-sensor` deployed in `monitoring`, pod Ready. (`deploy/java-on-amazon-eks/perf-sensor.sh`)
- Skills + `~/environment/.mcp.json` installed. (`deploy/java-on-amazon-eks/perf-sensor-ide.sh`)
- The workload opted into profiling: `perf-profile/sidecar: "true"` on its pod template.

## 1. Wire up
```bash
kubectl -n monitoring port-forward svc/perf-sensor 8090:8080 &   # perf-sensor.mcp -> localhost:8090/mcp
cd ~/environment && claude                                       # skills + .mcp.json load from here
```
Confirm in-session: `perf-sensor` tools and `eks-mcp` are connected (`/mcp`), and the
`java-on-eks-optimization` / `java-on-eks-checklist` skills are listed.

## 2. Baseline
Scale to the demo size, drive load, capture the baseline so the end-of-session recap can diff:
```bash
kubectl -n unicorn-store-spring scale deploy/unicorn-store-spring --replicas=10
infra/scripts/test/benchmark.sh $(infra/scripts/test/getsvcurl.sh eks) 120 20
```
While it warms, participants read the architecture. Then ask **"How are we doing against best
practices?"** and save the score + `measure` JSON as the baseline.

## 3. The six questions — 3 runs each, on a fresh baseline
| # | Prompt | Pass criteria |
|---|---|---|
| 1 | How can I reduce memory consumption of unicorn-store-spring? | calls `measure`+`sizeMemory`; values equal tool output; proposes SerialGC / MaxRAMPercentage=75; explains the second pass; stops at the change |
| 2 | How can I start faster without changing the image? | `resizePolicy` + boot CPU from the reference; manual resize command with the full resources map |
| 3 | How can I start faster without changing the application? | AOT (Java 25); `Dockerfile.aot` identical to the reference except placeholders filled with `store-spring-1.0.0-exec.jar` / `com.unicorn.store.StoreApplication` |
| 4 | How can I start in under a second? | CRaC; `Dockerfile.crac`; finds `UnicornPublisher` (EventBridge) and proposes the `Resource` hook; mentions credentials-at-restore |
| 5 | (under load) Why is latency high and how do I fix it? | cites futex wall share and `UnicornService.publishUnicornEvent:<line>` from `threadDump` (use `sampleN` ≥ replicas); proposes non-blocking publish + pool size |
| 6 | How are we doing against best practices? | checklist skill runs on `measure` facts; score + grouped items with sources; identical PASS/FAIL across the three runs |

**Variance rule:** anything that differs between the three runs other than prose is a defect in
the skill or a tool description — fix it before the verdict.

## 4. Apply loop
With apply confirmed, apply 1–4 in sequence, build with `scripts/build.sh`, deploy, and confirm
the `java-on-eks-checklist` score rises monotonically. For fast iteration operate at 1–2 replicas;
scale back to 10 at the end to show nodes freed (Grafana "Java on EKS — Sensor": fleet
reserved-vs-used, node count) and faster fleet scale-up.

## 5. Verdict
3/3 runs pass on all six → adopt. Otherwise tighten the skill first; fall back to page-provided
artifacts only if the skill cannot be made stable.
