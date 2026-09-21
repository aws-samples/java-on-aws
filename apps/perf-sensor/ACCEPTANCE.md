# perf-sensor — acceptance run (`claude -p`, on the IDE)

Flow exercise, not a content exercise: prove that the skill
(investigate → root cause → solution → apply → exit) plus the page-side
rollout/load/verify loop works end to end on a clean env, and that the twelve-item
checklist moves as expected. Every Claude call is `claude -p` so the transcript is
reproducible; interactive `claude` behaves the same.

**Load** always means: `~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20`
(120 s at 20 rps — satisfies `warmSeconds=120` and gives the window a peak).

---

## 1. Preconditions (fresh bootstrap, nothing to do)

The env is freshly bootstrapped from this branch: sensor deployed, skills + `.mcp.json` +
`settings.json` installed, baseline at 1 vCPU / 2 Gi Guaranteed, `:latest`, no
`JAVA_TOOL_OPTIONS`, profiler not yet attached.

## 2. Wire up Claude

Separate terminal (long-lived):
```bash
kubectl -n monitoring port-forward svc/perf-sensor 8090:8080
```
Working terminal:
```bash
cd ~/environment
claude -p "List the MCP tools you can see from perf-sensor and eks-mcp, names only."
```
Expected: `measure, sizeMemory, threadDump, diagnoseBlocking, profileTop, startupLog`
and the eks-mcp read tools, with no permission prompt.

## 3. Baseline

```bash
cd ~/environment/unicorn-store-spring
yq -i '.spec.template.metadata.labels."perf-profile/sidecar" = "true"' k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[*].name}'; echo   # app + perf-profiler
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "baseline: profiler attached"
cd ~/environment && claude -p "How are we doing against best practices?"
```

Expected score **4/12**, no UNKNOWN:

| # | Verdict | Deciding signal |
|---|---|---|
| 1 | PASS | memRequestMi 2048 == memLimitMi 2048, restarts 0 |
| 2 | FAIL | 2048 / rssPeak ≈ 370 ≈ 5.5× |
| 3 | FAIL | maxHeapMi 512 / 2048 = 0.25 |
| 4 | FAIL | initialHeapMi 32 / 512 = 0.06 |
| 5 | PASS | cpuLimit 1, effectiveCpuCount 1, SerialGC |
| 6 | FAIL | cpuRequest 1 / cpuUsageP95 ≈ 0.15–0.3 |
| 7 | PASS | cpuThrottledRatio ≈ 0 (record the value) |
| 8 | FAIL | startupSeconds ≈ 13 |
| 9 | PASS | startup budget 50 ≥ 26, no initialDelay, liveness 30, distinct paths |
| 10 | FAIL | grace 30 < preStop 10 + 30 |
| 11 | FAIL | requestThreadsBlockedInFutureGet ≥ 1 from diagnoseBlocking |
| 12 | FAIL | hikariPendingMax > 0 (pool size 1) — if 0, record as UNKNOWN-worthy |

Save the full output as `baseline.txt`.

---

## Module pattern (used five times)

```
ask      claude -p "<question>"           → Root cause / Evidence / Solution / "Files changed: …" /
                                            "Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect."
review   git diff                          → matches the reference artifact except measured values / placeholders
roll out kubectl / build.sh                → from this runbook, never from Claude
load     benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        → where the next measurement needs a warm window
verify   one hand check + claude -p score  → expected delta
commit   git add -A && git commit -m "<module>"   → so the next module's git diff shows only its own change
```

**Skill-boundary checks on every module** (fail the module if any is violated):
- The turn edits only the listed files, does not `git add`/`commit`, does not run
  `kubectl`, `build.sh` or `benchmark.sh`, and ends with the exact closing line.
- No checklist score, no "other improvements" inside an optimization run.

## 4. Module 1 — right-size memory

```bash
cd ~/environment && claude -p "How can I reduce memory consumption of unicorn-store-spring?"
```
Expected: `sizeMemory` called with the seven policy values from `sizing-policy.yaml`;
`requests == limits` (≈ 576Mi from floor ≈ 276 / peak ≈ 366), SerialGC,
`MaxRAMPercentage=75`, `InitialRAMPercentage=50`; files changed + closing line.
```bash
cd ~/environment/unicorn-store-spring && git diff                                # only resources + JAVA_TOOL_OPTIONS
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring exec deploy/unicorn-store-spring -c unicorn-store-spring -- sh -c 'JAVA_TOOL_OPTIONS= jcmd 1 VM.flags' | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize|UseSerialGC'
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD (warm window for the second pass)
cd ~/environment && claude -p "How can I reduce memory consumption of unicorn-store-spring?"   # second pass
```
Expected second pass: `sizeMemory` OK with equal or lower values. If lower: Claude edits again →
apply, rollout, load again. If equal: Claude reports resolved and edits nothing.
```bash
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "right-size memory"
cd ~/environment && claude -p "How are we doing against best practices?"
```
Expected **7/12**: 2, 3, 4 flip to PASS (record `maxHeapMi/memLimitMi` ≈ 0.75, `initialHeapMi/maxHeapMi` ≈ 0.5). Nothing else changes.

## 5. Module 2 — start faster without changing the image

```bash
cd ~/environment && claude -p "How can I start faster without changing the image?"
```
Expected: `StartupCPUBoost` CR from `startup-cpu-boost.yaml` (`<app>`/`<namespace>` filled);
the Deployment's CPU request/limit untouched. No `kubectl patch`.
```bash
cd ~/environment/unicorn-store-spring && git diff                                # k8s/startup-cpu-boost.yaml new, nothing else
kubectl -n unicorn-store-spring apply -f k8s/startup-cpu-boost.yaml
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring get pod -l app=unicorn-store-spring -o jsonpath='{.items[0].spec.containers[0].resources}'; echo   # 1 vCPU again after Ready (was 2 at boot)
kubectl -n unicorn-store-spring logs deploy/unicorn-store-spring -c unicorn-store-spring | grep -E "Started|Restored"                              # ≈ 7 s
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "startup cpu boost"
cd ~/environment && claude -p "How are we doing against best practices?"
```
Expected **7/12**, unchanged: 8 still FAIL (≈ 7 s > 5 s), 6 still FAIL (request 1 vs p95 ≈ 0.2 —
the boost does not lower the steady request; whether a module should is an open decision),
5 still PASS (SerialGC explicit), restarts 0 (resize was in place).

## 6. Module 3 — start faster without changing the application (AOT)

```bash
cd ~/environment && claude -p "How can I start faster without changing the application?"
```
Expected: `profileTop cpu` cited (JIT share), `Dockerfile.aot` identical to the reference except
`JAR_FILE=store-spring-1.0.0-exec.jar` / `MAIN_CLASS=com.unicorn.store.StoreApplication`.
```bash
cd ~/environment/unicorn-store-spring && git diff --stat                         # Dockerfile.aot only
IMG=$(./scripts/build.sh aot Dockerfile.aot)                     # several minutes
yq -i ".spec.template.spec.containers[0].image = \"$IMG\"" k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring logs deploy/unicorn-store-spring -c unicorn-store-spring | grep -E "Started|Restored"                              # ≈ 3 s
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "aot cache"
cd ~/environment && claude -p "How are we doing against best practices?"
```
Expected **8/12**: 8 flips to PASS (≤ 5 s).

## 7. Module 4 — under a second (CRaC)

```bash
cd ~/environment && claude -p "How can I start in under a second?"
```
Expected: `org.crac` dependency in `pom.xml`; `Resource` hook proposed for the class holding
the EventBridge client (found by scanning `src/`), credentials-at-restore mentioned;
`Dockerfile.crac` identical to the reference (incl. `-XX:+UseSerialGC` on the checkpoint
command); `JAVA_TOOL_OPTIONS` removed from the Deployment.
```bash
cd ~/environment/unicorn-store-spring && git diff --stat                         # pom.xml, 1 java file, Dockerfile.crac, k8s/deployment.yaml
IMG=$(./scripts/build.sh crac Dockerfile.crac)                   # long: builds, runs, checkpoints
yq -i ".spec.template.spec.containers[0].image = \"$IMG\"" k8s/deployment.yaml
kubectl -n unicorn-store-spring apply -f k8s/deployment.yaml && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
kubectl -n unicorn-store-spring logs deploy/unicorn-store-spring -c unicorn-store-spring | grep -E "Started|Restored"                              # Restored, < 0.5 s
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "crac"
cd ~/environment && claude -p "How are we doing against best practices?"
```
Expected: 8 PASS with `kind=Restored`; 5 PASS (SerialGC baked). **Items 3 and 4 are expected to
FAIL on CRaC**: `MaxHeapSize`/`InitialHeapSize` were fixed at checkpoint time from the build
container, so `maxHeapMi/memLimitMi` will not be 0.5–0.8. Record the observed values. This is the
documented CRaC trade-off (`crac.md`); the verdict decides whether the checklist keeps it visible
or the Dockerfile pins `-Xmx` at checkpoint. Score **6/12** (8/12 if you pin the heap).

## 8. Module 5 — latency (code fix)

```bash
cd ~/environment && claude -p "Why is latency high and how do I fix it?"
```
Expected: `diagnoseBlocking` called (not `profileTop wall`, not a benchmark);
`requestThreadsBlockedInFutureGet ≥ 1` and frame `CompletableFuture.get` cited with
`UnicornService.publishUnicornEvent:<line>`; non-blocking publish proposed; pool size from
`hikariPendingMax`; image not switched.
```bash
cd ~/environment/unicorn-store-spring && git diff                                # UnicornService.java, application.yaml (pool)
IMG=$(./scripts/build.sh crac Dockerfile.crac)                   # rebuild the current image
kubectl -n unicorn-store-spring rollout restart deploy/unicorn-store-spring && kubectl -n unicorn-store-spring rollout status deploy/unicorn-store-spring --timeout=300s
~/java-on-aws/infra/scripts/test/benchmark.sh $(~/java-on-aws/infra/scripts/test/getsvcurl.sh eks) 120 20        # LOAD
cd ~/environment/unicorn-store-spring && git add -A && git commit -q -m "non-blocking publish"
cd ~/environment && claude -p "How are we doing against best practices?"
```
Expected: 11 and 12 flip to PASS → **8/12** on CRaC. Still FAIL: 3, 4 (CRaC heap bounds), 6 (CPU
request), 10 (grace period) — none of them a module in this run.

## 9. Item 10 (optional, one line)

`terminationGracePeriodSeconds: 45` in the pod spec → apply → score → item 10 PASS, **9/12**. Decide whether
this stays a participant discovery or moves into the baseline manifest.

---

## 10. Variance rule and verdict

Run §3–§8 three times, each on a fresh env. Anything that differs between runs other than prose —
tool choice, artifact content beyond measured values, an extra action after apply, a different checklist verdict on the same state — is a defect in a skill or a tool
description. Fix it, re-run.

Record per run: the twelve scores after each module, the CRaC `maxHeapMi`, the `-p` wall time per call.

Open decisions the run should inform: item 6 (lower the steady CPU request in a module, and
how to derive the number deterministically), items 3/4 on CRaC (pin the heap at checkpoint or
keep the trade-off visible), item 10 (fix in baseline or leave as a discovery).

Verdict: 3/3 runs pass §3–§8 with the expected flips → adopt the skill flow and rewrite the
content pages to it. Otherwise tighten the skills first.
