# Cloud-native Java on Kubernetes — performance checklist

Twelve practices for a Java service on Kubernetes that must **start fast, run lean
and stay responsive**. Each item pairs a declared intent with the runtime behaviour
that confirms it, so it is scored from **measured facts** (`perf-sensor.measure`,
plus `perf-sensor.threadDump` for item 11), not from a YAML lint. Security, image
hygiene, availability and observability practices are real but out of this scope;
see the end.

Scoring: PASS / FAIL / UNKNOWN per item from the named evidence; a null fact makes the
item **UNKNOWN — never FAIL on a missing fact**. Score = `PASS / 12`; list UNKNOWN
items separately. Two thresholds are stated bars, not constants: 5 s for startup
(12-factor: "a few seconds") and 2× for the limit-to-working-set ratio.

## Memory

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 1 | Memory is Guaranteed and honoured | `memRequestMi == memLimitMi`, both set; AND `restarts == 0` or `lastTerminationReason != OOMKilled` | `workload.memRequestMi`, `workload.memLimitMi`, `runtime.restarts`, `runtime.lastTerminationReason` |
| 2 | Limit sized from the measured working set | `memLimitMi / rssPeakMi ≤ 2.0` (peak observed under load: `window.requestRatePerSec > 0`) | `workload.memLimitMi`, `runtime.rssPeakMi`, `window.requestRatePerSec` |
| 3 | Heap follows the container | observed `maxHeapMi / memLimitMi` between 0.50 and 0.80; AND `javaToolOptions` does not contain `-Xmx` | `runtime.maxHeapMi`, `workload.memLimitMi`, `workload.javaToolOptions` |
| 4 | Heap starts near its steady size | observed `initialHeapMi / maxHeapMi ≥ 0.50` | `runtime.initialHeapMi`, `runtime.maxHeapMi` |

Why: the JVM sizes heap and GC from the cgroup limit; a request below the limit makes
the pod Burstable and the first OOM-kill candidate on a busy node (1). Node capacity
is reserved by the limit, so the limit must track what the pod uses (2). The default
heap ceiling is 25 % of the limit, which wastes the container; 75 % leaves room for
metaspace, threads and code cache (3). A tiny initial heap pays for repeated heap
growth during boot (4). Observed `MaxHeapSize`/`InitialHeapSize` come from `VM.flags`,
so they hold on any image, including a CRaC restore where flags live in the checkpoint.
Sources: AWS Containers blog — *JVM memory, CPU, and classpath best practices for Java
containers on AWS*; Microsoft — *Containerize your Java applications for Kubernetes*;
JDK `java` tool reference (container support, `MaxRAMPercentage`, `InitialRAMPercentage`).

## CPU

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 5 | JVM sees its CPU and the GC fits it | `cpuLimitCores` set AND `effectiveCpuCount == ceil(cpuLimitCores)`; AND (`effectiveCpuCount ≤ 1` → `gcName == SerialGC`) | `workload.cpuLimitCores`, `runtime.effectiveCpuCount`, `runtime.gcName` |
| 6 | CPU request reflects steady state, not boot | `cpuRequestCores / cpuUsageP95Cores ≤ 2.0` (under load: `window.requestRatePerSec > 0`) | `workload.cpuRequestCores`, `runtime.cpuUsageP95Cores`, `window.requestRatePerSec` |
| 7 | Not CFS-throttled under load | `cpuThrottledRatio ≤ 0.05` | `runtime.cpuThrottledRatio` |

Why: GC, JIT and ForkJoin thread counts are fixed at JVM start from the processor
count; a JVM that sees more cores than its quota over-threads and gets throttled, and
G1's concurrent threads compete with the application on a single core (5). Java needs
several times more CPU during boot than at steady state; a request sized for boot is
paid forever — use a startup boost / in-place resize for the boot spike instead (6).
CFS throttling stretches GC pauses and trips liveness probes (7).
Sources: AWS Containers blog (as above; CFS throttling, `ActiveProcessorCount`);
HotSpot GC tuning guide (ergonomics: Serial below two CPUs); learnk8s — *Kubernetes
production readiness checklist* (right-sizing); Kube Startup CPU Boost.

## Startup

| # | Practice | Rule | Evidence |
|---|---|---|---|
| 8 | Fast startup | `startupSeconds ≤ 5` | `runtime.startupSeconds` |
| 9 | Probe budgets match observed behaviour | `startupProbe` present AND `startupBudgetSeconds ≥ 2 × startupSeconds` AND `startupInitialDelaySeconds == 0` AND `readinessInitialDelaySeconds == 0`; AND `livenessBudgetSeconds ≥ 30`; AND `livenessPath != readinessPath` | `workload.startupProbe`, `workload.startupBudgetSeconds`, `workload.startupInitialDelaySeconds`, `workload.readinessInitialDelaySeconds`, `workload.livenessBudgetSeconds`, `workload.livenessPath`, `workload.readinessPath`, `runtime.startupSeconds` |
| 10 | Shutdown budget is consistent | `terminationGracePeriodSeconds ≥ preStopSleepSeconds + 30` (30 = Spring Boot's default graceful-shutdown timeout) | `workload.terminationGracePeriodSeconds`, `workload.preStopSleepSeconds` |

Why: a disposable process starts in seconds so rollouts and scale-outs are fast (8).
A startup probe gives the JVM its boot budget via `failureThreshold × periodSeconds`,
not via `initialDelaySeconds` padding that delays every pod equally; the liveness budget
must outlast a GC pause or the pod restarts for nothing; liveness and readiness answer
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
| 11 | Request path does not block on downstream calls | `threadDump.requestThreadsBlockedInFutureGet == 0` while `diagnoseBlocking` drives load (UNKNOWN without a dump under load) | `threadDump.requestThreadsBlockedInFutureGet`, `threadDump.topBlockingFrames` |
| 12 | Connection pool is not a bottleneck | `hikariPendingMax == 0` under load (`window.requestRatePerSec > 0`) | `runtime.hikariPendingMax`, `window.requestRatePerSec` |

Why: a request thread parked in `Future.get()` adds the downstream round-trip to every
request and, on virtual threads, is invisible to a sampling profiler — only a thread
dump under load names it (11). Threads queuing for a pooled connection is latency the
database never sees; size the pool to the measured concurrency (12).
Sources: JDK *Virtual Threads* guide; HikariCP — *About pool sizing*; learnk8s
(long-lived connections and pools).

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
