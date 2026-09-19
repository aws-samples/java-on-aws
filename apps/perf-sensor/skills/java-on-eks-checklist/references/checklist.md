# Cloud-native Java on EKS — checklist

Each item is scored PASS / FAIL / UNKNOWN from one named evidence field in
`perf-sensor.measure` (item 10 from `perf-sensor.threadDump`). A null fact makes
the item UNKNOWN — never FAIL on a missing fact.

## Resources

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 1 | requests and limits set | `workload.cpuRequestCores`, `workload.memRequestMi`, `workload.cpuLimitCores`, `workload.memLimitMi` all present | `workload.*RequestCores/*RequestMi/*LimitCores/*LimitMi` |
| 2 | memory limit within 2× working set | `workload.memLimitMi / runtime.rssPeakMi ≤ 2.0` | `workload.memLimitMi`, `runtime.rssPeakMi` |
| 5 | CPU `resizePolicy` present | `workload.cpuResizePolicy == true` (restart `NotRequired`) | `workload.cpuResizePolicy`, `workload.cpuResizeRestartPolicy` |

Source: EKS Best Practices Guide — resource management and right-sizing.
https://docs.aws.amazon.com/eks/latest/best-practices/
Kubernetes in-place pod resize (item 5): https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/

## JVM ergonomics

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 3 | `MaxRAMPercentage` set, no `-Xmx` | `workload.javaToolOptions` contains `MaxRAMPercentage` and does NOT contain `-Xmx` | `workload.javaToolOptions` |
| 4 | GC matches CPU shape | `runtime.gcName == SerialGC` when `workload.cpuLimitCores ≤ 1` | `runtime.gcName`, `workload.cpuLimitCores` |

Source (item 3): `java` command / container support — MaxRAMPercentage.
https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html
Source (item 4): HotSpot GC tuning / ergonomics.
https://docs.oracle.com/en/java/javase/25/gctuning/

## Startup

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 6 | startup under 2 s | `runtime.startupSeconds < 2` | `runtime.startupSeconds` |

Source: Spring Boot — efficient deployments (CDS, AOT, CRaC).
https://docs.spring.io/spring-boot/reference/packaging/efficient.html

## Operability

| # | Item | Rule | Evidence (`measure`) |
|---|---|---|---|
| 7 | readiness probe present | `workload.readinessProbe == true` | `workload.readinessProbe` |
| 8 | continuous profiler attached | a profiler sidecar is present | `workload.sidecars` (sidecarsPresent) |
| 9 | image tag pinned | `workload.imageTag != latest` and not blank | `workload.imageTag` |

Source (item 7): Kubernetes readiness/liveness/startup probes.
https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
Source (item 8): continuous profiling (Grafana Pyroscope).
https://grafana.com/docs/pyroscope/latest/
Source (item 9): Kubernetes image names — avoid `:latest`.
https://kubernetes.io/docs/concepts/containers/images/#image-names

## Code

| # | Item | Rule | Evidence (`threadDump`) |
|---|---|---|---|
| 10 | no blocking call on the request path | `threadDump.requestThreadsBlockedInFutureGet == 0` (UNKNOWN without a dump) | `threadDump.requestThreadsBlockedInFutureGet` |

Source: Java virtual threads / non-blocking request handling.
https://docs.oracle.com/en/java/javase/25/core/virtual-threads.html
