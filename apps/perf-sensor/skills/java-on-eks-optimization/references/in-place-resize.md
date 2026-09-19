# In-place CPU resize: boot fast, run lean

## Introduction

A Java service needs far more CPU during startup (class loading, JIT) than at
steady state. Provisioning for the steady state makes startup slow; provisioning
for boot wastes CPU forever. In-place pod resize lets you boot at a high CPU and
scale CPU **down** once the pod is Ready — with no restart and no image change.

## How it works

- Kubernetes in-place pod resize (`resizePolicy` with `restartPolicy: NotRequired`
  for `cpu`) lets CPU change without recreating the pod.
- Boot the container at a high CPU (e.g. 2 vCPU) — startup roughly halves — then
  patch the pod's `resize` subresource down to the steady CPU after Ready.
- More CPU at boot also means the JVM sees more processors, so JIT and startup work
  parallelize.

## Key benefits

- Faster startup (and faster rollouts / scale-ups) with no image or code change.
- No steady-state CPU waste — you pay the boot premium only during boot.
- Zero restarts: the resize is in place.

## Trade-offs

- The manual `patch --subresource resize` is per-pod — fine for a demo, wrong for a
  fleet. In production use the **Kube Startup CPU Boost** controller
  (github.com/google/kube-startup-cpu-boost) to boost + scale down automatically
  across the Deployment. The `resizePolicy` is the prerequisite either way.
- The resize call must send the **full** resources map (cpu AND memory) or the API
  rejects it.
- GC/heap ergonomics are fixed at JVM start; this lever targets CPU/startup, not heap.

## Artifact

Apply `deployment-cpu-boost.yaml` (declares the `resizePolicy` + boot CPU), then the
manual resize command it documents. Verify with `perf-sensor.startupLog` (startup
seconds drop) and `measure` (restartCount stays 0 — resized without restart).

Immersion Day: Optimize containers → Pod resize.
