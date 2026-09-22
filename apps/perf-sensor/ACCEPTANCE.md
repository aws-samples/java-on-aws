# perf-sensor — acceptance run (`claude -p`, on the IDE)

Flow exercise, not a content exercise: prove that the skill
(investigate → root cause → solution → apply → exit) plus the page-side
rollout/load/verify loop works end to end on a clean env, and that the twelve-item
checklist moves as expected. The first Claude call is `claude -p`; every later one is
`claude -c -p`, which continues that session. Changes are reviewed in the IDE's git view.
Each module ends with a commit so the next module shows only its own change.

Two terminals: **A** for everything below, **B** for the port-forward (started once).

The sensor is read-only and drives no traffic, and a blocked virtual thread exists only while
requests are in flight (neither the wall profile nor JFR records it), so the items that need
load (2, 6, 7, 11, 12) are decided only in the three **load runs**: baseline, the module 5
latency question, and the final score. One block does load and question together: start the
120 s benchmark in the background, wait 90 s (item 7 needs ≥ 30 s of the pod past its first
minute), ask, then `wait`. Rate 50 writes/s: one pooled connection held for the ~10 ms
EventBridge round-trip carries ~60 writes/s, so 50 keeps the mean low (≈ 12 ms) but shows the
defect in the tail and the dump — max in the seconds, blocked threads, pool waits; 200 (the
immersion-day rate) would time out and inflate the memory peak that sets module 1's limit.

**Load-run block** =
```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 50 >/dev/null 2>&1 & sleep 90; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Every other score is the bare `claude -c -p "How is unicorn-store-spring doing against best practices?"`.

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
Terminal A:
```bash
cd ~/environment && claude -p "List the MCP tools you can see from perf-sensor and eks-mcp, names only."
```
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
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 50 >/dev/null 2>&1 & sleep 90; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Load run 1 of 3. Expected **≈ 5/12**:

| | # | Deciding signal |
|---|---|---|
| ✅ | 1 | request 2048 == limit 2048, restarts 0 |
| ❌ | 2 | 2048 / peak ≈ 400–500 ≈ 4–5× (bar 2.5) — **record the peak**; it sets module 1's limit |
| ❌ | 3 | maxHeap 512 / 2048 = 0.25 |
| ❌ | 4 | initialHeap 32 / 512 = 0.06 |
| ✅ | 5 | limit 1, sees 1, SerialGC |
| ❌/✅ | 6 | request 1.0 / p95 ≈ 0.5 ≈ 2.0× — sits on the bar, either verdict is fine |
| ? | 7 | throttled s / used s over the pod's life minus its first minute — **record the value**, bar 0.10 is uncalibrated |
| ❌ | 8 | startup ≈ 13–15 s |
| ✅ | 9 | startup budget 50 ≥ 2× startup, no initialDelay, liveness 30, distinct paths |
| ❌ | 10 | grace 30 < preStop 10 + 30 |
| ❌ | 11 | blocked ≥ 1, blockedInsideTransaction ≥ 1, pool waits > 0 (diagnoseBlocking OK, load flowing) |
| ✅ | 12 | mean ≈ 12 ms (bar 100) — the defect is in the tail (`latencyMaxMs` in the seconds), which 12 does not score |

If 11 shows 🟡 BLOCKED, the load was not flowing when Claude called the tool: rerun the
load-run block. Save the output as `~/environment/baseline.txt`.

---

## Module pattern

```
ask       cd ~/environment && claude -c -p "<question>"
          → Root cause / Evidence / Solution / "Files changed: …" /
            "Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect."
review    IDE git view — matches the reference artifact except measured values / placeholders
roll out  kubectl / build.sh — from this runbook, never from Claude
commit    git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "<module>"
score     cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```

Only three load runs in the whole flow (baseline, module 5 diagnosis, module 5 final). The
per-module score runs **without load**: the sensor scopes facts to the current pod, so 2, 6,
7, 11, 12 show 🟡 "no load in window" on a freshly rolled pod — that is correct, not a
defect. Per module, check the items named as flipping; the final score in §8 is the verdict.

**Skill-boundary checks on every module** (fail the module if any is violated):
- The turn edits only the listed files, does not `git add`/`commit`, does not run
  `kubectl`, `build.sh` or `benchmark.sh`, and ends with the exact closing line.
- No checklist score, no "other improvements" inside an optimization run.
- All numbers in the answer come from a named tool result.

`jcmd` inside the pod: PID 1 is `/pause` (shared PID namespace with the sidecar) and the
main class shows as the jar, so target the JVM by pid from `jcmd -l`:
```
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'
```

## 4. Module 1 — right-size memory

```bash
cd ~/environment && claude -c -p "How can I reduce memory consumption of unicorn-store-spring?"
```
Expected: `sizeMemory` with the policy values; `requests == limits = 640Mi` (peak × 1.4 rounded up
to 128Mi — 640 holds for peaks up to 457 Mi; the first 50 rps run decides whether that is still
the number), SerialGC, `MaxRAMPercentage=75`, `InitialRAMPercentage=50`.
Review: only `resources` + `JAVA_TOOL_OPTIONS` changed. **If the limit is not 640Mi**, note it:
the prebuilt `:crac` image (module 4) bakes `-Xmx480m -Xms320m` for 640Mi and module 4 must
then build instead of deploying the prebuilt tag.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'   # 480 Mi / 320 Mi / SerialGC
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "right-size memory"
cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```
Expected: 3, 4 ✅ (0.75, 0.67); 1 ✅ at 640; 2, 6, 7, 11, 12 🟡 (no load on this pod).

## 5. Module 2 — start faster without changing the image

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the image?"
```
Expected: `sizeCpu` called with the policy values; three edits: `k8s/startup-cpu-boost.yaml`
(`StartupCPUBoost`, `<app>`/`<namespace>` filled); in `k8s/deployment.yaml` `requests.cpu` set to
`sizeCpu.requestsCpu` (≈ 750m from p95 ≈ 0.47) with `limits.cpu` unchanged at 1, and
`-XX:ActiveProcessorCount=1` appended to `JAVA_TOOL_OPTIONS`. Review: those two files only.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/startup-cpu-boost.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # record it: boost + ActiveProcessorCount=1 (≈ 7 s, was ≈ 13)
curl -s localhost:8090/api/v1/measure/unicorn-store-spring | jq '.jfr.container'           # effectiveCpuCount 1, cpuQuotaCores 2.0 (boosted at boot)
sleep 30; kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[0].resources}'; echo   # request 750m / limit 1 once the boost controller has resized down
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "startup cpu boost + cpu request"
cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```
Expected: 5 ✅ (JVM sees 1 via `ActiveProcessorCount`, SerialGC); 8 still ❌ (≈ 7 s > 5).
Once, for the page: remove `-XX:ActiveProcessorCount=1`, `rollout restart`, read `startupLog`
(expect ≈ 7 s) and `jfr.container.effectiveCpuCount` (expect 2); put the flag back, restart. The
two numbers are the trade-off the page states.

## 6. Module 3 — start faster without changing the application (AOT)

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the application?"
```
Expected: `profileTop cpu` cited (JIT share); `Dockerfile.aot` identical to the reference except
`JAR_FILE=store-spring-1.0.0-exec.jar` / `MAIN_CLASS=com.unicorn.store.StoreApplication`.
Review: `Dockerfile.aot` only. The prebuilt `:aot` tag is this exact build, so no build here.
```bash
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":aot")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # ≈ 3 s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "aot cache"
cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```
Expected: 8 ✅ (≤ 5 s).

## 7. Module 4 — under a second (CRaC)

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start in under a second?"
```
Expected: `org.crac` dependency in `pom.xml`; `Resource` hook for the class holding the
EventBridge client (found by scanning `src/`), credentials-at-restore mentioned;
`Dockerfile.crac` identical to the reference with `JAR_FILE` filled and
`JAVA_HEAP_OPTS` from the current limit (640Mi → `-Xmx480m -Xms320m`); `JAVA_TOOL_OPTIONS`
removed from the Deployment. Review: `pom.xml`, one Java file, `Dockerfile.crac`, `k8s/deployment.yaml`.
The prebuilt `:crac` tag is this exact build (same Dockerfile, same heap opts, same hook), so
no build here. Only if module 1 did not land on 640Mi:
`~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac` first (≈ 3 min, warm cache).
```bash
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":crac")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # Restored, < 0.5 s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd $(jcmd -l | grep -v JCmd | cut -d" " -f1) VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'   # 480 Mi / 320 Mi / SerialGC
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "crac"
cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"
```
Expected: 8 ✅ (Restored); 3, 4, 5 stay ✅ because the checkpoint carries the heap bounds and
SerialGC (`jfr.jvmArgs` shows them). If 3/4/5 go ❌ with `maxHeapMi ≈ 3900`, `effectiveCpuCount 2`,
G1: the running image is not the skill build — the prebuild used another Dockerfile.

## 8. Module 5 — latency (code fix)

```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 50 >/dev/null 2>&1 & sleep 90; cd ~/environment && claude -c -p "Why do some writes to unicorn-store-spring take seconds under load and how do I fix it?"; wait
```
Load run 2 of 3. Expected: `diagnoseBlocking` status OK (not BLOCKED — if BLOCKED, Claude asks for
the load run; start it and ask again); `requestThreadsBlockedInFutureGet ≥ 1`,
`blockedInsideTransaction ≥ 1`, frame `CompletableFuture.get` cited with
`UnicornService.publishUnicornEvent:<line>` and the `@Transactional createUnicorn` named as the
enclosing transaction. Solution: publish **after commit** (`@TransactionalEventListener(AFTER_COMMIT)`
or `TransactionSynchronization`) and non-blocking; the pool is sized only if
`carriersParkedInPoolWait` is expected to remain after the boundary fix, to the observed
concurrency. Image not switched. Not `profileTop wall`.
Review: `UnicornService.java` (+ a listener class if Claude chose the event form; `application.yaml`
only if the pool was sized).
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # the code changed: rebuild the current image (≈ 3 min, warm cache)
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "non-blocking publish"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 50 >/dev/null 2>&1 & sleep 90; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Load run 3 of 3 — the verdict. Expected **10–11/12**: 1–6, 8, 9, 11, 12 ✅ (11: blocked 0,
inside-transaction 0, pool waits 0; 12: mean latency well under 100 ms at 50 rps, `latencyMaxMs`
no longer in the seconds); 10 ❌ (no module fixes the grace period); 7 is the open one — record
`cpuThrottledRatio` on the CRaC pod under load; ≤ 0.10 makes it 11.

**If 12 is still ❌ with 11 ✅** (open finding from run 2: the CRaC pod showed mean ≈ 400 ms and
an 11 s flat max before *and* after the code fix, while the plain pod did 12 ms on the same
code), the blocking fix was not the pod's bottleneck. Ask, on the same load run if it is still
flowing, otherwise start one:
```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 50 >/dev/null 2>&1 & sleep 90; cd ~/environment && claude -c -p "Blocking is fixed but writes to unicorn-store-spring are still slow under load. Why?"; wait
```
Record the answer, `runtime.cpuThrottledRatio`, `jfr.monitorTop` and `jfr.pinned` verbatim. The
CRaC pod's checkpoint now pins `ActiveProcessorCount`; if the slowness is gone with that, the
cause was the JVM sized for the boosted 2 CPUs on a 1-CPU quota.

---

## 9. Variance rule and verdict

Run §3–§8 three times, each on a fresh env or after
`~/java-on-aws/infra/scripts/deploy/java-on-amazon-eks/reset-app.sh --prebuild` (hard-resets the
app repo to the starting-point commit, deletes the boost CR, redeploys `:latest`, restores the
prebuilt tags). Anything that differs between runs other than prose —
tool choice, artifact content beyond measured values, an extra action after apply, a different
checklist verdict on the same state — is a defect in a skill or a tool description. Fix it, re-run.

Record per run: the twelve verdicts after each module, item 7 on the CRaC pod, the CPU request
`sizeCpu` returned, the `-p` wall time per call.

Sensor scoping: cAdvisor facts (peak, floor, p95, throttling) and startup come from the pods
that are Ready now; traffic facts use the window clipped to the current pod's lifetime. A pod
replaced by a rollout does not leak into the verdict, and a freshly rolled pod without load
reads 🟡 on the load-guarded items.

Open decision: item 10 — fix the grace period in the baseline manifest or leave it as a
participant discovery.

Verdict: 3/3 runs pass §3–§8 with the expected flips → adopt the skill flow and rewrite the
content pages to it. Otherwise tighten the skills first.
