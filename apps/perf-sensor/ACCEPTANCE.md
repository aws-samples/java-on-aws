# perf-sensor — acceptance run (`claude -p`, on the IDE)

Flow exercise, not a content exercise: prove that the skill
(investigate → root cause → solution → apply → exit) plus the page-side
rollout/load/verify loop works end to end on a clean env, and that the twelve-item
checklist moves as expected. The first Claude call is `claude -p`; every later one is
`claude -c -p`, which continues that session. Changes are reviewed in the IDE's git view.
Each module ends with a commit so the next module shows only its own change.

Three terminals: **A** for everything below, **B** for the port-forward, **C** for the load
(both started once and left running).

The service runs under steady load for the whole session, like a service in production. The
sensor is read-only and drives no traffic, and a blocked virtual thread exists only while
requests are in flight (neither the wall profile nor JFR records it), so the items that need
load (2, 6, 7, 11, 12) read from that traffic; Claude never starts load and has no Bash. Rate
50 writes/s: one pooled connection held for the ~10 ms EventBridge round-trip carries ~60
writes/s, so 50 keeps the mean low (≈ 12 ms) but shows the defect in the tail and the dump —
max in the seconds, blocked threads, pool waits; 200 (the immersion-day rate) would time out
and inflate the memory peak that sets module 1's limit.

Every question is a plain `claude -c -p "<question>"` on its own line; in an interactive
`claude` session type the same text. Shell blocks hold only the developer's steps.

Image tags are fixed: `:latest`, `:aot`, `:crac` in the workshop ECR repo. No variables.

---

## 1. Preconditions (fresh bootstrap, nothing to do)

Sensor deployed, skills + `.mcp.json` + `settings.json` installed, baseline at
1 vCPU / 2 Gi Guaranteed, `:latest`, no `JAVA_TOOL_OPTIONS`, scrape annotations present,
profiler not yet attached. The profiler inject policy now adds a `perf-scratch` emptyDir at
`/perf` (app + sidecar) and starts a 10-min JFR ring in the app JVM.

```bash
GRAFANA_URL=$(kubectl get svc grafana -n monitoring -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
GRAFANA_PASSWORD=$(kubectl get secret grafana-admin -n monitoring -o jsonpath="{.data.password}" | base64 --decode)
echo "✅ Grafana Access Details" &&
echo "🌍 URL:      http://${GRAFANA_URL}" &&
echo "👤 Username: admin" &&
echo "🔑 Password: ${GRAFANA_PASSWORD}"
```bash

## 2. Wire up

Terminal B (leave running; reconnects when Karpenter moves the sensor pod):
```bash
while true; do kubectl -n monitoring port-forward svc/perf-sensor 8090:8080; sleep 2; done
```
Terminal C (leave running; 10-minute runs back to back, ~1 s gap between them):
```bash
while true; do ~/environment/unicorn-store-spring/scripts/load.sh 600 50; done
```
Terminal A:

`cd ~/environment && claude -p "List the MCP tools you can see from perf-sensor and eks-mcp, names only."`
Expected: `measure, sizeMemory, sizeCpu, threadDump, diagnoseBlocking, profileTop, startupLog`
and the eks-mcp read tools, no permission prompt.

## 3. Baseline

Terminal A:
```bash
yq -i '.spec.template.metadata.labels."perf-profile/sidecar" = "true"' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[*].name}'; echo   # unicorn-store-spring perf-profiler
kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.volumes[?(@.name=="perf-scratch")].name}'; echo   # perf-scratch
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "baseline: profiler attached"
```
Wait ≥ 2 min after the rollout (item 7 needs the pod past its first minute plus 30 s), then:

`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected **≈ 5/12**:

| | # | Deciding signal |
|---|---|---|
| ✅ | 1 | request 2048 == limit 2048, restarts 0 |
| ❌ | 2 | 2048 / peak ≈ 450–500 ≈ 4–5× (bar 2.5) — **record the peak**; it sets module 1's limit |
| ❌ | 3 | maxHeap 512 / 2048 = 0.25 |
| ❌ | 4 | initialHeap 32 / 512 = 0.06 |
| ✅ | 5 | limit 1, sees 1, SerialGC |
| ❌ | 6 | request 1.0 / p95 ≈ 0.5 ≈ 2.0× (bar 1.75) |
| ❌ | 7 | ≈ 0.25 — a 13 s-startup JVM still JITs the request path past its first minute under load |
| ❌ | 8 | startup ≈ 13–15 s |
| ✅ | 9 | startup budget 50 ≥ 2× startup, no initialDelay, liveness 30, distinct paths |
| ❌ | 10 | grace 30 < preStop 10 + 30 |
| ❌ | 11 | blocked ≥ 1, blockedInsideTransaction ≥ 1, pool waits ≥ 1 |
| ✅ | 12 | mean ≈ 12 ms (bar 100) — the defect is in the tail (`latencyMaxMs` in the seconds), which 12 does not score |

If 11 shows 🟡 BLOCKED, terminal C is not running. Save the output as `~/environment/baseline.txt`.

---

## Module pattern

```
ask       cd ~/environment && claude -c -p "<question>"
          → Root cause / Evidence / Solution / "Files changed: …" /
            "Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect."
review    IDE git view — matches the reference artifact except measured values / placeholders
roll out  build.sh / kubectl — from this runbook, never from Claude (rebuilding is part of the lesson and fast on the warm cache)
commit    git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "<module>"
score     cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```

The sensor scopes facts to the current pod, and the load in terminal C never stops, so a
score taken ≥ 2 min after a rollout has every item. Per module, check the items named as
flipping; the score after §8b is the verdict.

**Skill-boundary checks on every module** (fail the module if any is violated):
- The turn edits only the listed files, does not `git add`/`commit`, runs no shell command
  at all (no Bash is allowed), and ends with the exact closing line.
- No checklist score, no "other improvements" inside an optimization run.
- All numbers in the answer come from a named tool result.

`jcmd` inside the pod: PID 1 is `/pause` (shared PID namespace with the sidecar) and the
main class shows as the jar, so target the JVM by pid from `jcmd -l`:
```
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'
```

## 4. Module 1 — right-size memory

`cd ~/environment && claude -c -p "How can I reduce memory consumption of unicorn-store-spring?"`

Expected: `sizeMemory` with the policy values; `requests == limits` = peak × 1.4 rounded up to
128Mi (640Mi for peaks ≤ 457, 768Mi for peaks ≤ 548 — **record which**; the prebuilt `:crac`
assumes 640), SerialGC, `MaxRAMPercentage=75`, `InitialRAMPercentage=50`.
Review: only `resources` + `JAVA_TOOL_OPTIONS` changed.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'   # 75 % / 50 % of the limit / SerialGC
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "right-size memory"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected: 2, 3, 4 ✅; 7 lower than baseline (record).

## 5. Module 2 — start faster without changing the image

`cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the image?"`

Expected: `sizeCpu` called with the policy values; three edits: `k8s/startup-cpu-boost.yaml`
(`StartupCPUBoost`, `<app>`/`<namespace>` filled); in `k8s/deployment.yaml` `requests.cpu` set to
`sizeCpu.requestsCpu` (≈ 750m from p95 ≈ 0.5) with `limits.cpu` unchanged at 1, and
`-XX:ActiveProcessorCount=1` appended to `JAVA_TOOL_OPTIONS`. Review: those two files only.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/startup-cpu-boost.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # record it: boost + ActiveProcessorCount=1 (≈ 7 s, was ≈ 13)
curl -s localhost:8090/api/v1/measure/unicorn-store-spring | jq '.jfr.container'           # effectiveCpuCount 1, cpuQuotaCores 2.0 (boosted at boot)
sleep 30; kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[0].resources}'; echo   # request 750m / limit 1 once the boost controller has resized down
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "startup cpu boost + cpu request"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected: 5, 6 ✅; 8 still ❌ (≈ 7 s > 5).
Once, for the page: remove `-XX:ActiveProcessorCount=1`, `rollout restart`, read `startupLog`
(expect ≈ 7 s) and `jfr.container.effectiveCpuCount` (expect 2); put the flag back, restart. The
two numbers are the trade-off the page states.

## 6. Module 3 — start faster without changing the application (AOT)

`cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the application?"`

Expected: `profileTop cpu` cited (JIT share); `Dockerfile.aot` identical to the reference except
`JAR_FILE=store-spring-1.0.0-exec.jar` / `MAIN_CLASS=com.unicorn.store.StoreApplication`.
Review: `Dockerfile.aot` only.
```bash
~/environment/unicorn-store-spring/scripts/build.sh aot Dockerfile.aot        # ≈ 1 min on the warm cache; pushes :aot
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":aot")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # ≈ 3 s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "aot cache"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected: 8 ✅ (≤ 5 s); 11 still ❌ (if it reads ✅ here the dump sampling missed the block — a
sensor defect, record it).

## 7. Module 4 — under a second (CRaC)

`cd ~/environment && claude -c -p "How can unicorn-store-spring start in under a second?"`

Expected: `org.crac` dependency in `pom.xml`; `Resource` hook for the class holding the
EventBridge client (found by scanning `src/`), credentials-at-restore mentioned;
`Dockerfile.crac` identical to the reference with `JAR_FILE`, `WARMUP_CMD` (a `POST /unicorns`),
`JAVA_HEAP_OPTS` from the current limit (640Mi → `-Xmx480m -Xms320m`) and `JAVA_CPU_OPTS`
(`-XX:ActiveProcessorCount=1`) filled; `JAVA_TOOL_OPTIONS` removed from the Deployment.
Review: `pom.xml`, one Java file, `Dockerfile.crac`, `k8s/deployment.yaml`.
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # ≈ 3 min: builds, starts, warms up, checkpoints; pushes :crac
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":crac")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # Restored, < 0.5 s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'   # 75 % / 50 % of the limit / SerialGC
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "crac"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected: 8 ✅ (Restored); 3, 4, 5 stay ✅ (checkpoint carries heap bounds, SerialGC and the
processor count); 7 and 12 as after module 3 — **record both**: with a warmed checkpoint the
restored pod must not JIT the write path under load (`jfr.compilation.totalMs` in the window
small). If 7 or 12 are worse than after module 3, the warm-up did not cover the hot path.

## 8. Module 5 — latency (code fix)

`cd ~/environment && claude -c -p "Why do some writes to unicorn-store-spring take seconds under load and how do I fix it?"`

Expected: `diagnoseBlocking` status OK; `requestThreadsBlockedInFutureGet ≥ 1`,
`blockedInsideTransaction ≥ 1`, frame `CompletableFuture.get` cited with
`UnicornService.publishUnicornEvent:<line>` and the `@Transactional createUnicorn` named as the
enclosing transaction. Solution: publish **after commit** (`@TransactionalEventListener(AFTER_COMMIT)`
or `TransactionSynchronization`) and non-blocking; the pool is sized only if
`carriersParkedInPoolWait` is expected to remain after the boundary fix, to the observed
concurrency. Image not switched. Not `profileTop wall`.
Review: `UnicornService.java` (+ a listener class if Claude chose the event form; `application.yaml`
only if the pool was sized).
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # the code changed: rebuild the current image
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "non-blocking publish"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected **11/12**: 11 ✅ (blocked 0, inside-transaction 0, pool waits 0), 12 ✅ (mean well under
100 ms, `latencyMaxMs` no longer in the seconds), 7 ✅; only 10 ❌.

**If 12 is still ❌ with 11 ✅**: the blocking fix was not the pod's bottleneck. Ask, and record
the answer with `runtime.cpuThrottledRatio`, `jfr.monitorTop` (now with the waiting frame) and
`jfr.pinned` verbatim:

`cd ~/environment && claude -c -p "Blocking is fixed but writes to unicorn-store-spring are still slow under load. Why?"`

## 8b. The last red item — extended question

`cd ~/environment && claude -c -p "How to fix item 10?"`

Expected: `terminationGracePeriodSeconds: 40` added to `k8s/deployment.yaml` (preStop 10 s +
Spring Boot's 30 s graceful-shutdown drain), the reasoning stated, nothing else changed.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "shutdown budget"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected **12/12** — the verdict.

---

## 9. Variance rule and verdict

Run §3–§8 three times, each on a fresh env or after
`~/java-on-aws/infra/scripts/deploy/java-on-amazon-eks/reset-app.sh --prebuild` (hard-resets the
app repo to the starting-point commit, deletes the boost CR, redeploys `:latest`, restores the
prebuilt tags). Anything that differs between runs other than prose —
tool choice, artifact content beyond measured values, an extra action after apply, a different
checklist verdict on the same state — is a defect in a skill or a tool description. Fix it, re-run.

Record per run: the twelve verdicts after each module, item 7 and 12 on the CRaC pod (before
and after the code fix), the memory limit `sizeMemory` returned, the CPU request `sizeCpu`
returned, the `-p` wall time per call.

Sensor scoping: cAdvisor facts (peak, floor, p95, throttling) and startup come from the pods
that are Ready now; traffic facts use the window clipped to the current pod's lifetime. A pod
replaced by a rollout does not leak into the verdict, and a freshly rolled pod without load
reads 🟡 on the load-guarded items.

Item 10 is fixed by the closing question (§8b), not by a module: the last red item is the
participant's own exercise.

Verdict: 3/3 runs pass §3–§8 with the expected flips → adopt the skill flow and rewrite the
content pages to it. Otherwise tighten the skills first.
