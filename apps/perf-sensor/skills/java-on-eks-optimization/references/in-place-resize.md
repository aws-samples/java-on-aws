# In-place CPU resize: boot fast, run lean

## Introduction

A Java service needs far more CPU during startup (class loading, JIT) than at
steady state. Provisioning for the steady state makes startup slow; provisioning
for boot wastes CPU forever. In-place pod resize lets you boot at a high CPU and
scale CPU **down** once the pod is Ready — with no restart and no image change.

## How it works

Kubernetes in-place pod resize lets a container's CPU change without recreating the
pod. Boot at a high CPU (e.g. 2 vCPU) — the JVM sees more processors, so JIT and
class loading parallelize and startup roughly halves — then drop CPU back to the
steady value once the pod is Ready. No image or code change, zero restarts.

## Production path — Kube Startup CPU Boost (use this)

The **Kube Startup CPU Boost** controller (github.com/google/kube-startup-cpu-boost)
is installed cluster-wide by the platform. A developer applies one namespaced
`StartupCPUBoost` CR (**`startup-cpu-boost.yaml`**): the controller boosts CPU at pod
admission and resizes it down in place automatically when the pod is Ready — for
every pod, every rollout, every scale-up. This is the answer to give: declarative,
fleet-wide, no per-pod action.

## Under the hood — manual in-place resize (mechanism only)

The controller drives the same primitive you can invoke by hand; show it once so the
CR isn't magic:

- `resizePolicy` with `restartPolicy: NotRequired` for `cpu` lets CPU change without
  restarting the container (default CPU resize is already NotRequired on current K8s).
- Set a high boot CPU in the Deployment, then patch the pod's `resize` subresource
  down after Ready. The resize call must send the **full** resources map (cpu AND
  memory) or the API rejects it.

`deployment-cpu-boost.yaml` documents this manual path. It is **per-pod** — fine to
demonstrate the mechanism, wrong for production (every new pod would need a hand
patch, and nothing scales it back down). Prefer the CR.

## Key benefits

- Faster startup (and faster rollouts / scale-ups) with no image or code change.
- No steady-state CPU waste — you pay the boot premium only during boot. With the
  boost in place, the steady-state `requests.cpu` can follow the measured demand
  (`cpuUsageP95Cores` from `measure`) instead of being sized for boot; the boost
  percentage then supplies the boot CPU on top of the lower request.
- Zero restarts: the resize is in place.

## Trade-off, and the flag that goes with the boost

- GC/heap ergonomics are fixed at JVM start; this lever targets CPU/startup, not heap.
- The JVM's processor count is also fixed at start. Without help it reads the **boosted**
  quota (e.g. 2 cores) and keeps GC, JIT and ForkJoin threads sized for it after the resize
  down to 1 — `jdk.ContainerConfiguration.effectiveCpuCount` in the JFR ring shows exactly
  what it read. Pin the steady-state count explicitly:
  `-XX:ActiveProcessorCount=<ceil(limits.cpu)>` in `JAVA_TOOL_OPTIONS`, and keep SerialGC
  explicit on one core. This is the container-JVM guidance for any environment where the
  CPU quota differs from what the JVM should assume (fractional limits, shares, boosts).
- Cost: with fewer compiler threads part of the boost's startup gain may shrink; the extra
  boot quota still removes CFS throttling during class loading and JIT. Measure both.

## What the operator verifies afterwards

`perf-sensor.startupLog` (startup seconds drop) and `measure` (restartCount stays 0 —
resized without restart; `cpuRequestCores` near `cpuUsageP95Cores`).


