# Cloud-native Java on EKS — checklist

Each item is scored PASS / FAIL / UNKNOWN from named evidence in `perf-sensor.measure`
(item 7 needs `perf-sensor.threadDump`). A null fact makes the item **UNKNOWN — never
FAIL on a missing fact**. The score is `passed / (PASS + FAIL)`; UNKNOWN is not counted.

Grouped by **AWS Well-Architected pillar**. Thresholds marked *(teaching bar)* are
workshop-chosen round numbers, not canonical constants — they give a clear PASS/FAIL for
the session. A defaults-only, unbounded JVM (the baseline) legitimately fails the
Performance and Cost items; each workshop module raises the score.

## Security

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 1 | runs as non-root, no privilege escalation | `workload.runAsNonRoot == true` AND `workload.allowPrivilegeEscalation == false` | `workload.runAsNonRoot`, `workload.allowPrivilegeEscalation` |

Security is job zero — AWS ships the sample hardened (non-root, no privilege escalation),
so this PASSes at baseline. The workshop optimizes performance, not security posture.
Source: Kubernetes Pod Security Standards (Restricted); EKS Best Practices — Security.
https://kubernetes.io/docs/concepts/security/pod-security-standards/
https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html

## Reliability

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 2 | readiness probe present | `workload.readinessProbe == true` | `workload.readinessProbe` |
| 3 | startup probe present | `workload.startupProbe == true` (lets a slow JVM boot without tripping liveness) | `workload.startupProbe` |

Source: Kubernetes liveness/readiness/startup probes — a startup probe is the recommended
way to protect slow-starting apps; EKS Best Practices — running applications.
https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
https://docs.aws.amazon.com/eks/latest/best-practices/application.html

## Performance Efficiency

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 4 | `MaxRAMPercentage` set, no `-Xmx` | `workload.javaToolOptions` contains `MaxRAMPercentage` and NOT `-Xmx` | `workload.javaToolOptions` |
| 5 | GC matches CPU shape | PASS iff the GC fits the container's CPU: with `workload.cpuLimitCores ≤ 1`, `runtime.gcName == SerialGC`. An **unbounded** container (no CPU limit) that runs **G1** FAILs — the JVM sizes GC threads/heap to the whole node, not the pod | `runtime.gcName`, `workload.cpuLimitCores` |
| 6 | startup under 2 s *(teaching bar)* | `runtime.startupSeconds < 2` | `runtime.startupSeconds` |
| 7 | no blocking call on the request path | `threadDump.requestThreadsBlockedInFutureGet == 0` (UNKNOWN without a dump) | `threadDump.requestThreadsBlockedInFutureGet` |

Source (4): `java` command / container support — MaxRAMPercentage.
https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html
Source (5): HotSpot GC ergonomics — SerialGC below ~2 CPUs / small heaps.
https://docs.oracle.com/en/java/javase/25/gctuning/
Source (6): Spring Boot — efficient deployments (CDS, AOT, CRaC).
https://docs.spring.io/spring-boot/reference/packaging/efficient.html
Source (7): Java virtual threads / non-blocking request handling. Note: on a virtual-thread
app a blocked request thread is found via a **thread dump**, not the wall flame graph.
https://docs.oracle.com/en/java/javase/25/core/virtual-threads.html

## Cost Optimization

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 8 | requests and limits set | `workload.cpuRequestCores`, `workload.memRequestMi`, `workload.cpuLimitCores`, `workload.memLimitMi` all present | `workload.*RequestCores/*RequestMi/*LimitCores/*LimitMi` |
| 9 | memory limit within 2× working set *(teaching bar)* | `workload.memLimitMi / runtime.rssPeakMi ≤ 2.0` | `workload.memLimitMi`, `runtime.rssPeakMi` |

Source: EKS Best Practices — cost optimization / right-sizing; Kubernetes resource management.
https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-compute.html
https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

## Operational Excellence

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 10 | image tag pinned | `workload.imageTag != latest` and not blank | `workload.imageTag` |

Source: Kubernetes image names — avoid `:latest`.
https://kubernetes.io/docs/concepts/containers/images/#image-names

---

## Out of scope for this session (further reading)

Genuine cloud-native practices the EKS Best Practices Guide covers, but outside a
single-service startup/memory/latency session — mention as "what to look at next",
don't score:

- Liveness probe, PodDisruptionBudget, topology spread / anti-affinity, HPA —
  https://docs.aws.amazon.com/eks/latest/best-practices/application.html
- Full Pod Security Standards "Restricted" (`readOnlyRootFilesystem`, `capabilities.drop`,
  `seccompProfile`) beyond non-root + no-privilege-escalation —
  https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Graceful shutdown (SIGTERM, `terminationGracePeriodSeconds`, `server.shutdown=graceful`) —
  https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html

Not scored (leaves the JVM): GraalVM native image — the real image-size/startup
step-change, at the cost of the dynamic JVM.

Not a scored practice (it's tooling): a continuous profiler sidecar. Attaching it is the
opening session step so the sensor has profile samples; it is not a checklist item.
