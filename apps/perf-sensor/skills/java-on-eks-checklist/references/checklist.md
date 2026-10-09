# Cloud-native Java on Kubernetes — performance checklist

Twelve practices for a Java service on Kubernetes that must **start fast, run lean
and stay responsive**. Each item pairs a declared intent with the runtime behaviour
that confirms it, so it is scored from **measured facts** (`perf-sensor.measure`, which
includes the JVM's own JFR ring as `jfr.*`, plus `perf-sensor.diagnoseBlocking` under load
for item 11), not from a YAML lint. Security, image
hygiene, availability and observability practices are real but out of this scope;
see the end.

Scoring: PASS / FAIL / UNKNOWN per item from the named evidence; a null fact makes the
item **UNKNOWN — never FAIL on a missing fact**. Score = `PASS / 12`. Items marked
*under load* need a load run flowing while scoring; otherwise they are UNKNOWN. Three
thresholds are stated bars, not constants: 5 s for startup (12-factor: "a few seconds"),
2.5× for the limit-to-working-set ratio (the sizing policy itself lands at up to ~2.1×), and
100 ms mean latency.

## Memory

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 1 | Memory is Guaranteed and honoured | `memRequestMi == memLimitMi`, both set; AND `restarts == 0` or `lastTerminationReason != OOMKilled` | `workload.memRequestMi`, `workload.memLimitMi`, `runtime.restarts`, `runtime.lastTerminationReason` |
| 2 | Limit sized from the measured working set | `memLimitMi / workingSetPeakMi ≤ 2.5` *under load* | `workload.memLimitMi`, `runtime.workingSetPeakMi`, `window.requestRatePerSec` |
| 3 | Heap follows the container | observed `maxHeapMi / memLimitMi` between 0.50 and 0.80. How the bound was set does not matter: `MaxRAMPercentage`, ergonomics, or an `-Xmx` derived from the limit (a CRaC checkpoint has to bake `-Xmx`) all pass if the ratio holds; note the mechanism from `jfr.jvmArgs` | `runtime.maxHeapMi`, `workload.memLimitMi`, `jfr.jvmArgs` |
| 4 | Heap starts near its steady size | observed `initialHeapMi / maxHeapMi ≥ 0.50` | `runtime.initialHeapMi`, `runtime.maxHeapMi` |

Why: the JVM sizes heap and GC from the cgroup limit; a request below the limit makes
the pod Burstable and the first OOM-kill candidate on a busy node (1). Node capacity
is reserved by the limit, so the limit must track what the pod uses (2). The default
heap ceiling is 25 % of the limit, which wastes the container; 75 % leaves room for
metaspace, threads and code cache (3). A tiny initial heap pays for repeated heap
growth during boot (4). Observed `MaxHeapSize`/`InitialHeapSize` come from `VM.flags` and
the arguments from the JVM's own `jdk.JVMInformation`, so they hold on any image, including
a CRaC restore where flags live in the checkpoint and not in the Deployment.
Sources: AWS Containers blog — *JVM memory, CPU, and classpath best practices for Java
containers on AWS*; Microsoft — *Containerize your Java applications for Kubernetes*;
JDK `java` tool reference (container support, `MaxRAMPercentage`, `InitialRAMPercentage`).

## CPU

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 5 | JVM sees its CPU and the GC fits it | `cpuLimitCores` set AND `effectiveCpuCount == ceil(cpuLimitCores)` (`effectiveCpuCount` is the JVM's own `jdk.ContainerConfiguration` value when the ring is present); AND (`effectiveCpuCount ≤ 1` → `gcName == SerialGC`) | `workload.cpuLimitCores`, `runtime.effectiveCpuCount`, `jfr.container`, `runtime.gcName` |
| 6 | CPU request reflects steady state, not boot | `cpuRequestCores ≤ roundUp(2.5 × cpuSteadyCores, roundMillicores)` *under load*; null → 🟡 "no steady-state CPU: less than 60 s of steady state after readiness, or no cAdvisor series" | `workload.cpuRequestCores`, `runtime.cpuSteadyCores`, `runtime.cpuMeanCores`, `runtime.cpuJitShare`, `runtime.steadyWindowSeconds`, `window.requestRatePerSec` |
| 7 | Not CFS-throttled under load | `cpuThrottledRatio ≤ 0.25` (throttled seconds / CPU seconds used over the steady window, capped at 5 min) *under load*; null → 🟡 "no steady-state CPU: less than 60 s of steady state after readiness, or no cAdvisor series" | `runtime.cpuThrottledRatio`, `runtime.steadyWindowSeconds`, `window.requestRatePerSec` |

Why: GC, JIT and ForkJoin thread counts are fixed at JVM start from the processor
count; a JVM that sees more cores than its quota over-threads and gets throttled, and
G1's concurrent threads compete with the application on a single core (5). Java needs
several times more CPU during boot than at steady state; a request sized for boot is
paid forever — use a startup boost / in-place resize for the boot spike instead (6).
CFS throttling stretches GC pauses and trips liveness probes; the share is time-based
(throttled seconds over CPU seconds used) because the classic throttled-periods ratio marks
a whole 100 ms period as throttled when a bursty request used the quota in 5 ms, so it
reads 20–30 % for a low-quota JVM that lost almost no wall time (7).

**Steady CPU (6, 7).** Both read the steady window: it starts after readiness and after the
JIT settled (`runtime.steadyStartSeconds`), so boot never counts. `cpuSteadyCores` is the
window's mean minus the JIT compiler threads' share of the CPU profile (`cpuMeanCores`,
`cpuJitShare`): minutes after a restart the JIT still compiles, and that CPU ends; the load's
CPU stays, so a pod measured at 2 min and one measured at 10 min read about the same. Name both in
the evidence (e.g. `steady 0.21 = mean 0.30 − JIT 30 % over 60 s`). The bars leave room for the
variance of a short window: a 2-minute estimate lands within about 40 % of the settled value
either way, so the estimate `sizeCpu` sized from and the one the checklist reads can differ by
up to 2×. Item 6 fails a request sized for boot (3× steady and more) and passes one `sizeCpu`
wrote from the same load (1.5×, rounded) at either end of that range; `roundMillicores` is
in `references/sizing-policy.yaml` of the optimization skill (50 m), e.g. request 0.35 ≤
roundUp(2.5 × 0.21 = 0.525, 50 m) = 0.55. Item 7 reads the throttling as it is, JIT included,
because it is real; 0.25 is the share at which the common Kubernetes `CPUThrottlingHigh` alert
fires (that alert counts throttled periods, which reads higher than this time-based ratio).
Sources: AWS Containers blog (as above; CFS throttling, `ActiveProcessorCount`);
HotSpot GC tuning guide (ergonomics: Serial below two CPUs); learnk8s — *Kubernetes
production readiness checklist* (right-sizing); Kube Startup CPU Boost.

## Startup

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 8 | Fast startup | `startupSeconds ≤ 5` | `runtime.startupSeconds` |
| 9 | Probe budgets match observed behaviour | `startupProbe` present AND `startupBudgetSeconds ≥ 2 × startupSeconds` AND `startupInitialDelaySeconds == 0` AND `readinessInitialDelaySeconds == 0`; AND `livenessBudgetSeconds ≥ 30` AND `livenessBudgetSeconds × 1000 ≥ 3 × jfr.gc.maxMs` (when the ring has GC pauses); AND `livenessPath != readinessPath` | `workload.startupProbe`, `workload.startupBudgetSeconds`, `workload.startupInitialDelaySeconds`, `workload.readinessInitialDelaySeconds`, `workload.livenessBudgetSeconds`, `jfr.gc.maxMs`, `workload.livenessPath`, `workload.readinessPath`, `runtime.startupSeconds` |
| 10 | Shutdown budget is consistent | `terminationGracePeriodSeconds ≥ preStopSleepSeconds + 30` (30 = Spring Boot's default graceful-shutdown timeout) | `workload.terminationGracePeriodSeconds`, `workload.preStopSleepSeconds` |

Why: a disposable process starts in seconds so rollouts and scale-outs are fast (8).
A startup probe gives the JVM its boot budget via `failureThreshold × periodSeconds`,
not via `initialDelaySeconds` padding that delays every pod equally; the liveness budget
must outlast the worst GC pause the JVM actually recorded (`jdk.GCPhasePause`) or the pod
restarts for nothing; liveness and readiness answer
different questions and need different endpoints (9). Kubernetes sends SIGTERM after
`preStop` and kills at the grace period; if the app's graceful drain does not fit in the
remainder, in-flight requests die on every rollout (10).
Sources: The Twelve-Factor App — IX. Disposability; Spring Boot reference — *Efficient
deployments* (CDS, AOT, CRaC) and *Graceful shutdown*; Kubernetes — *Configure liveness,
readiness and startup probes*, *Pod lifecycle (termination)*; AWS Containers blog (GC
pauses vs probe timing); learnk8s (SIGTERM handling, probe semantics).

## Latency

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 11 | Request path does not block on downstream calls | `diagnoseBlocking` status OK and `threads.requestThreadsBlockedInFutureGet == 0` and `threads.requestThreadsWaitingForConnection == 0` *under load* (UNKNOWN when BLOCKED); cite `blockedInsideTransaction` when > 0 — the block holds a DB connection | `diagnoseBlocking.threads.requestThreadsBlockedInFutureGet`, `blockedInsideTransaction`, `requestThreadsWaitingForConnection`, `topBlockingFrames` |
| 12 | Latency under load is bounded | `latencyMeanMs ≤ 100` *under load*; cite `jfr.pinned`, `jfr.monitorTop`, `jfr.safepointTotalMs`, `jfr.gc.maxMs` as the in-JVM context | `runtime.latencyMeanMs`, `runtime.latencyMaxMs`, `window.requestRatePerSec`, `jfr.*` |

Why: a request thread parked in `Future.get()` adds the downstream round-trip to every
request and, on virtual threads, is invisible to a sampling profiler AND to JFR (which
records `ThreadPark` only for platform threads) — only a JSON thread dump taken under load
names it; a block that sits inside a transaction also holds a pooled connection for the
round-trip, so the pool caps throughput and every request queues on it (11). Mean latency
under a steady load is the symptom every request-path defect
shares — a blocking call, a starved connection pool, GC pauses, pinning, contention,
safepoints, CFS throttling; the thread dump and the ring say which (12).
Sources: JDK *Virtual Threads* guide; Spring Boot Actuator — `http.server.requests` metrics;
learnk8s (long-lived connections and pools).

---

## Out of scope here (further reading)

Practices a full production review covers but this performance checklist does not score:

- Security: `readOnlyRootFilesystem`, `capabilities.drop: [ALL]`, `seccompProfile` —
  Kubernetes Pod Security Standards (Restricted); EKS Best Practices — Security.
- Image hygiene: pinned tags / digests, runtime-only images — learnk8s; Kubernetes images.
- Availability: ≥ 2 replicas, PodDisruptionBudget, topology spread — EKS Best Practices —
  Reliability.
- Observability: structured logs to stdout, metrics, traces — EKS Best Practices —
  Observability.
- Beyond the JVM: GraalVM native image — the step-change in image size and startup, at
  the cost of the dynamic JVM.

A continuous profiler sidecar is tooling, not a practice: attaching it is how the
sensor gets profile samples; it is not an item.
