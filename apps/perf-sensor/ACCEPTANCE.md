# perf-sensor — acceptance run (`claude -p`, on the IDE)

Flow exercise, not a content exercise: prove that the skill
(investigate → root cause → solution → apply → exit) plus the page-side
rollout/load/verify loop works end to end on a clean env, and that the twelve-item
checklist moves as expected. The first Claude call is `claude -p`; every later one is
`claude -c -p`, which continues that session. Changes are reviewed in the IDE's git view.
Each module ends with a commit so the next module shows only its own change.

Two terminals: **A** for everything below, **B** for the port-forward (started once).

The sensor is read-only and drives no traffic, and a blocked virtual thread exists only while
requests are in flight (neither the wall profile nor JFR records it), so every **score** and
the **latency question** run while your load is flowing. One block does both: start the 120 s
benchmark in the background, wait 60 s for the window to have a peak, ask, then `wait` for the
benchmark to end.

**Score block** =
```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```

Image tags are fixed: `:latest`, `:aot`, `:crac` in the workshop ECR repo. No variables.

---

## 1. Preconditions (fresh bootstrap, nothing to do)

Sensor deployed, skills + `.mcp.json` + `settings.json` installed, baseline at
1 vCPU / 2 Gi Guaranteed, `:latest`, no `JAVA_TOOL_OPTIONS`, scrape annotations present,
profiler not yet attached. The profiler inject policy now adds a `perf-scratch` emptyDir at
`/perf` (app + sidecar) and starts a 10-min JFR ring in the app JVM.

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
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```

Expected **4/12**:

| | # | Deciding signal |
|---|---|---|
| ✅ | 1 | request 2048 == limit 2048, restarts 0 |
| ❌ | 2 | 2048 / peak ≈ 370 ≈ 5.5× (bar 2.5) |
| ❌ | 3 | maxHeap 512 / 2048 = 0.25 |
| ❌ | 4 | initialHeap 32 / 512 = 0.06 |
| ✅ | 5 | limit 1, sees 1, SerialGC |
| ❌ | 6 | request 1.0 / p95 ≈ 0.2–0.3 |
| ✅ | 7 | throttled ≈ 0 over 5 min (record the value) |
| ❌ | 8 | startup ≈ 13 s |
| ✅ | 9 | startup budget 50 ≥ 26, no initialDelay, liveness 30, distinct paths |
| ❌ | 10 | grace 30 < preStop 10 + 30 |
| ❌ | 11 | blocked ≥ 1 (diagnoseBlocking OK, load flowing) |
| ❌ | 12 | mean latency ≈ 200+ ms (bar 100) |

If 11 shows 🟡 BLOCKED, the load was not flowing when Claude called the tool: rerun the
score block. Save the output as `~/environment/baseline.txt`.

---

## Module pattern

```
ask       cd ~/environment && claude -c -p "<question>"
          → Root cause / Evidence / Solution / "Files changed: …" /
            "Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect."
review    IDE git view — matches the reference artifact except measured values / placeholders
roll out  kubectl / build.sh — from this runbook, never from Claude
commit    git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "<module>"
score     the score block (load in background + ask)
```

**Skill-boundary checks on every module** (fail the module if any is violated):
- The turn edits only the listed files, does not `git add`/`commit`, does not run
  `kubectl`, `build.sh` or `benchmark.sh`, and ends with the exact closing line.
- No checklist score, no "other improvements" inside an optimization run.
- All numbers in the answer come from a named tool result.

## 4. Module 1 — right-size memory

```bash
cd ~/environment && claude -c -p "How can I reduce memory consumption of unicorn-store-spring?"
```
Expected: `sizeMemory` with the policy values; `requests == limits` (≈ 576Mi from floor ≈ 276 /
peak ≈ 366), SerialGC, `MaxRAMPercentage=75`, `InitialRAMPercentage=50`.
Review: only `resources` + `JAVA_TOOL_OPTIONS` changed.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd StoreApplication VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'
```
`jcmd` targets the JVM by main class: with the profiler sidecar the pod shares its PID namespace
and PID 1 is `/pause`. Expected `MaxHeapSize` = 75 % of the limit, `InitialHeapSize` = 50 %.

Load, then the second pass (the new pod's peak under the new limit):
```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 2>&1 | tail -n 45
cd ~/environment && claude -c -p "How can I reduce memory consumption of unicorn-store-spring?"
```
Expected second pass: equal or lower values. If lower: Claude edits again → apply, rollout.
If equal: Claude reports resolved and edits nothing.
```bash
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "right-size memory"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Expected **7/12**: 2, 3, 4 ✅.

## 5. Module 2 — start faster without changing the image

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the image?"
```
Expected: `sizeCpu` called with the policy values; three edits: `k8s/startup-cpu-boost.yaml`
(`StartupCPUBoost`, `<app>`/`<namespace>` filled); in `k8s/deployment.yaml` `requests.cpu` set to
`sizeCpu.requestsCpu` (≈ 500m from p95 ≈ 0.3) with `limits.cpu` unchanged at 1, and
`-XX:ActiveProcessorCount=1` appended to `JAVA_TOOL_OPTIONS`. Review: those two files only.
```bash
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/startup-cpu-boost.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[0].resources}'; echo   # request 500m / limit 1 again after Ready (boosted at boot)
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # record it: boost + ActiveProcessorCount=1 (expect 7–9 s)
curl -s localhost:8090/api/v1/measure/unicorn-store-spring | jq '.jfr.container'           # effectiveCpuCount 1 (not the boosted 2)
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "startup cpu boost + cpu request"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Expected **8/12**: 6 ✅; 8 still ❌ (> 5 s); 5 ✅ (limit 1, JVM sees 1 via `ActiveProcessorCount`, SerialGC).
Once, for the page: remove `-XX:ActiveProcessorCount=1`, `rollout restart`, read `startupLog` again
(expect ≈ 7 s) and `jfr.container.effectiveCpuCount` (expect 2); put the flag back, restart. The two
numbers are the trade-off the page states.

## 6. Module 3 — start faster without changing the application (AOT)

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start faster without changing the application?"
```
Expected: `profileTop cpu` cited (JIT share); `Dockerfile.aot` identical to the reference except
`JAR_FILE=store-spring-1.0.0-exec.jar` / `MAIN_CLASS=com.unicorn.store.StoreApplication`.
Review: `Dockerfile.aot` only.
```bash
~/environment/unicorn-store-spring/scripts/build.sh aot Dockerfile.aot        # several minutes; pushes :aot
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":aot")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # ≈ 3 s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "aot cache"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Expected **9/12**: 8 ✅ (≤ 5 s).

## 7. Module 4 — under a second (CRaC)

```bash
cd ~/environment && claude -c -p "How can unicorn-store-spring start in under a second?"
```
Expected: `org.crac` dependency in `pom.xml`; `Resource` hook for the class holding the
EventBridge client (found by scanning `src/`), credentials-at-restore mentioned;
`Dockerfile.crac` identical to the reference with `JAR_FILE` filled and
`JAVA_HEAP_OPTS` from the current limit (576Mi → `-Xmx432m -Xms288m`); `JAVA_TOOL_OPTIONS`
removed from the Deployment. Review: `pom.xml`, one Java file, `Dockerfile.crac`, `k8s/deployment.yaml`.
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # long: builds, runs, checkpoints; pushes :crac
yq -i '.spec.template.spec.containers[0].image |= sub(":[^:]+$"; ":crac")' ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f ~/environment/unicorn-store-spring/k8s/deployment.yaml
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
curl -s localhost:8090/api/v1/startupLog/unicorn-store-spring | jq -r .line                # Restored, < 0.5 s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd StoreApplication VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'   # 432 Mi / 288 Mi / SerialGC
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "crac"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Expected **9/12**: 8 ✅ (Restored); 3, 4, 5 stay ✅ because the checkpoint carries the heap
bounds and SerialGC (`jfr.jvmArgs` now shows them). Record item 7 (throttling on the CRaC pod
over the 5-min load window): if ❌, that is a real finding about 1 vCPU after restore.

## 8. Module 5 — latency (code fix)

```bash
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "Why is unicorn-store-spring latency high under load and how do I fix it?"; wait
```
Expected: `diagnoseBlocking` status OK (not BLOCKED — if BLOCKED, Claude asks for the load run;
start it and ask again); `requestThreadsBlockedInFutureGet ≥ 1` and frame `CompletableFuture.get`
cited with `UnicornService.publishUnicornEvent:<line>`; non-blocking publish; pool sized if
`carriersParkedInPoolWait > 0`; image not switched. Not `profileTop wall`.
Review: `UnicornService.java` (+ `application.yaml` if the pool was sized).
```bash
~/environment/unicorn-store-spring/scripts/build.sh crac Dockerfile.crac      # rebuild the current image
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring
kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
git -C ~/environment/unicorn-store-spring add -A && git -C ~/environment/unicorn-store-spring commit -q -m "non-blocking publish"
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20 >/dev/null 2>&1 & sleep 60; cd ~/environment && claude -c -p "How is unicorn-store-spring doing against best practices?"; wait
```
Expected **11/12**: 11 ✅, 12 ✅ (mean latency well under 100 ms without the EventBridge
round-trip). Only 10 ❌ — no module fixes the grace period.

---

## 9. Variance rule and verdict

Run §3–§8 three times, each on a fresh env. Anything that differs between runs other than prose —
tool choice, artifact content beyond measured values, an extra action after apply, a different
checklist verdict on the same state — is a defect in a skill or a tool description. Fix it, re-run.

Record per run: the twelve verdicts after each module, item 7 on the CRaC pod, the CPU request
`sizeCpu` returned, the `-p` wall time per call.

Known sensor caveat: `rssPeakMi` is `max()` across all pods with that container name in the
15-minute window, so shortly after a rollout the old pod's peak still counts. If the second
right-size pass returns the old limit for this reason, that is the sensor, not the flow.

Open decision: item 10 — fix the grace period in the baseline manifest or leave it as a
participant discovery.

Verdict: 3/3 runs pass §3–§8 with the expected flips → adopt the skill flow and rewrite the
content pages to it. Otherwise tighten the skills first.
