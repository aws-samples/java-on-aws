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
Ask right away: the checklist calls `measure` with `minUptimeSeconds 120`, so the sensor waits
until the pod is 2 min old (peak, p95 and throttle share need that) and Claude says so.

`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected **≈ 5/12**:

| | # | Deciding signal |
|---|---|---|
| ✅ | 1 | request 2048 == limit 2048, restarts 0 |
| ❌ | 2 | 2048 / peak ≈ 740 ≈ 2.8× (bar 2.5) — blocked requests pile up state under steady load; **record the peak**, it sets module 1's first limit |
| ❌ | 3 | maxHeap 512 / 2048 = 0.25 |
| ❌ | 4 | initialHeap 32 / 512 = 0.06 |
| ✅ | 5 | limit 1, sees 1, SerialGC |
| ✅ | 6 | request 1.0 / p95 ≈ 0.6–0.75 ≈ 1.3–1.7× (bar 1.75) — the saturated app burns CPU |
| ✅ | 7 | ≈ 0.03 — the pod has been under load for minutes, JIT is done |
| ❌ | 8 | startup ≈ 13–15 s |
| ✅ | 9 | startup budget 50 ≥ 2× startup, no initialDelay, liveness 30, distinct paths |
| ❌ | 10 | grace 30 < preStop 10 + 30 |
| ❌ | 11 | blocked ≥ 1, blockedInsideTransaction ≥ 1, pool waits ≈ 3 |
| ❌ | 12 | mean in the seconds (≈ 2 s at 50 rps: one connection held per write, the queue never drains) |

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

The sensor scopes facts to the current pod, and the load in terminal C never stops. A score
asked right after a rollout waits inside `measure` until the pod is 2 min old (Claude says
"the pod is young — measuring once it is 2 min old"); a score asked later returns at once.
Per module, check the items named as flipping; the score in §8e is the verdict.

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
128Mi — **≈ 1152Mi** from the saturated baseline's peak ≈ 740 (this is the right number for
the code as it is; §8b shrinks it after the code fix), SerialGC, `MaxRAMPercentage=75`,
`InitialRAMPercentage=50`.
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
`sizeCpu.requestsCpu` (≈ 950m from p95 ≈ 0.6 on the saturated app) with `limits.cpu` unchanged at 1, and
`-XX:ActiveProcessorCount=1` appended to `JAVA_TOOL_OPTIONS`. Review: those two files only.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/startup-cpu-boost.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # record it: boost + ActiveProcessorCount=1 (≈ 7 s, was ≈ 13)
curl -s localhost:8090/api/v1/measure/unicorn-store-spring | jq '.jfr.container'           # effectiveCpuCount 1, cpuQuotaCores 2.0 (boosted at boot)
sleep 30; kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[0].resources}'; echo   # request ≈ 950m / limit 1 once the boost controller has resized down
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "startup cpu boost + cpu request"
```
`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected: 5 ✅, 6 stays ✅ with the smaller request; 8 still ❌ (≈ 7 s > 5).
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
`JAVA_HEAP_OPTS` from the current limit (1152Mi → `-Xmx864m -Xms576m`) and `JAVA_CPU_OPTS`
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

Expected: 8 ✅ (Restored, < 0.1 s); 3, 4, 5 stay ✅ (checkpoint carries heap bounds, SerialGC
and the processor count); 7 as after module 3 — **record it**: with a warmed checkpoint the
restored pod must not JIT the write path under load (`jfr.compilation` in the window small,
`gc.maxMs` single digits). If 7 is worse than after module 3, the warm-up missed the hot path.

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

Expected: 12 ✅ (mean from seconds to single-digit ms), blocking 0 and inside-transaction 0.
Two things go **red because the fix worked** — record both: 2 (peak fell to ≈ 400, the 1152Mi
limit is now 2.9×) and 6 (p95 fell to ≈ 0.4, the 950m request is now 2.3×); 11 may stay ❌ with
`carriersParkedInPoolWait ≥ 1` and `blockedInsideTransaction 0` — the pool itself is now the
limit. Those are the closing questions.

**If 12 is still ❌**: the blocking fix was not the pod's bottleneck. Ask, and record the answer
with `runtime.cpuThrottledRatio`, `jfr.monitorTop` (with the waiting frame) and `jfr.pinned`:

`cd ~/environment && claude -c -p "Blocking is fixed but writes to unicorn-store-spring are still slow under load. Why?"`

## 8b. Re-size after the code fix

`cd ~/environment && claude -c -p "Right-size unicorn-store-spring again."`

Expected: one change from `sizeMemory` + `sizeCpu`: memory `requests == limits` ≈ 640Mi (peak
≈ 400 × 1.4 → 640), CPU request ≈ 650m (p95 ≈ 0.4 × 1.5), old → new cited; `Dockerfile.crac`
`JAVA_HEAP_OPTS` → `-Xmx480m -Xms320m` with "rebuild needed" stated. Review: `k8s/deployment.yaml`,
`Dockerfile.crac`.
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "re-size after code fix"
```
The lesson for the page: had the code fix come first, modules 1–2 would have landed on these
numbers directly. Sizing is a loop, not a step.

## 8c. Shutdown budget

`cd ~/environment && claude -c -p "How to fix item 10?"`

Expected: `terminationGracePeriodSeconds: 40` added to `k8s/deployment.yaml` (preStop 10 s +
Spring Boot's 30 s graceful-shutdown drain), the reasoning stated, nothing else changed.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "shutdown budget"
```

## 8d. Connection pool

`cd ~/environment && claude -c -p "Item 11 still fails — what now?"`

Expected: `diagnoseBlocking` shows blocking 0, inside-transaction 0, `carriersParkedInPoolWait ≥ 1`;
`maximum-pool-size` in `application.yaml` set to `requestThreadsActive` (peak in-flight requests,
a small single-digit number at 50 rps — **record it**), the value cited. Review: `application.yaml`.
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # config is in the image
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "pool sized from concurrency"
```
If 11 was already ✅ after §8, skip this step and say so in the record.

## 8e. Verdict and take-away

`cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"`

Expected **12/12**.

`cd ~/environment && claude -c -p "Write SESSION.md in ~/environment: the score progression per step, and for each step the root cause, the evidence with tool names and values, the files changed with the key lines, and the measured effect; end with a baseline-vs-final table (memory limit, heap ceiling, CPU request, startup, mean latency under load, GC pause max) and the cumulative list of files changed. Facts from this session only."`

Expected: the document a participant leaves with; every number in it appeared in a tool result
during the session.

---

## 9. Variance rule and verdict

Run §3–§8 three times, each on a fresh env or after
`~/java-on-aws/infra/scripts/deploy/java-on-amazon-eks/reset-app.sh --prebuild` (hard-resets the
app repo to the starting-point commit, deletes the boost CR, redeploys `:latest`, restores the
prebuilt tags). Anything that differs between runs other than prose —
tool choice, artifact content beyond measured values, an extra action after apply, a different
checklist verdict on the same state — is a defect in a skill or a tool description. Fix it, re-run.

Record per run: the twelve verdicts after each step, item 7 on the CRaC pod, both sizing
passes (`sizeMemory`, `sizeCpu` before and after the code fix), `requestThreadsActive` at 50 rps,
the `-p` wall time per call.

Sensor scoping: cAdvisor facts (peak, floor, p95, throttling) and startup come from the pods
that are Ready now; traffic facts use the window clipped to the current pod's lifetime. A pod
replaced by a rollout does not leak into the verdict, and a freshly rolled pod without load
reads 🟡 on the load-guarded items.

Items 2, 6, 10 and 11 at the end are fixed by the closing questions (§8b–§8d), not by a
module: the last red items are the participant's own loop.

Verdict: 3/3 runs pass §3–§8 with the expected flips → adopt the skill flow and rewrite the
content pages to it. Otherwise tighten the skills first.
