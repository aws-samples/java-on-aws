# Right-size memory for a Java service on EKS

## Introduction

Java services on Kubernetes are routinely over-provisioned: a multi-GB memory
limit for a service whose working set is a few hundred MiB. Right-sizing sets
requests/limits from the **measured** working set and lets the JVM use the
container it is given, instead of a hand-picked heap.

## How it works

- The JVM is container-aware. With `-XX:MaxRAMPercentage` it sizes the heap as a
  percentage of the container memory limit — no fixed `-Xmx`. Change the limit and
  the heap follows.
- `perf-sensor.sizeMemory` reads the working-set **floor** (idle) and **peak**
  (load) from cAdvisor and computes: `requests = roundUp(floor × floorFactor)`,
  `limits = roundUp(max(peak × peakFactor, floor × floorSafetyFactor))`.
- GC follows CPU shape: on **≤ 1 vCPU / small heap**, SerialGC is the right
  collector; G1GC regresses there (more threads, more overhead). The tool returns
  `SerialGC` when `cpuLimit ≤ 1`.

## Key benefits

- Density: a limit near the true working set packs more pods per node.
- Fewer surprises: the limit tracks the measured peak plus headroom, not a guess.
- No manual `-Xmx` to drift out of date when the limit changes.

## Trade-offs

- The window must be **warm and under load** or the numbers are meaningless — the
  tool BLOCKS until then. Honour it; do not force a size.
- A limit shrink requires a pod restart to take effect.
- `MaxRAMPercentage` governs the heap only; non-heap (metaspace, threads, direct
  buffers) is why `requests` sits above the heap and near the working-set floor.

## Artifact

Apply `deployment-resources.yaml` with the values `sizeMemory` returned:

```yaml
resources:
  requests: { memory: "<sizeMemory.requests.memory>" }   # near the working-set floor
  limits:   { memory: "<sizeMemory.limits.memory>" }      # over the observed peak
env:
  - name: JAVA_TOOL_OPTIONS
    value: >-
      -XX:+Use<sizeMemory.gc>                     # SerialGC on <=1 vCPU
      -XX:MaxRAMPercentage=<sizeMemory.maxRamPercentage>   # heap as % of the limit
      -XX:InitialRAMPercentage=50
```

Immersion Day: Optimize containers → Baseline / Results.
