# Right-size memory for a Java service on EKS

## Root cause pattern

A Java service on Kubernetes with a hand-picked, multi-GiB memory limit and JVM
defaults: the heap ceiling is 25 % of the limit, the working set is a few hundred
MiB, the limit is several times the working set. The node reserves what the pod
never uses.

## How it works

- The JVM is container-aware. With `-XX:MaxRAMPercentage` it sizes the heap as a
  percentage of the container memory limit — no fixed `-Xmx`. Change the limit and
  the heap follows. `-XX:InitialRAMPercentage` starts the heap near its steady size
  so boot does not pay for repeated heap growth.
- `perf-sensor.sizeMemory` reads the working-set **floor** (idle) and **peak**
  (load) from cAdvisor and computes
  `limits = roundUp(max(peak × peakFactor, floor × floorSafetyFactor))`,
  `requests = limits`.
- **Requests equal limits** (Guaranteed memory QoS): JVM memory is stable after
  warm-up, and a pod whose request is below its limit is the first OOM-kill
  candidate when a node runs short.
- GC follows CPU shape: on **≤ 1 vCPU / small heap**, SerialGC is the right
  collector; G1GC regresses there (more threads, more overhead). The tool returns
  `SerialGC` when `cpuLimit ≤ 1`.

## Why it works

- Density: a limit near the true working set packs more pods per node.
- The limit tracks the measured peak plus headroom, not a guess.
- No manual `-Xmx` to drift out of date when the limit changes.

## Trade-offs

- The window must be **warm and under load** or the numbers are meaningless — the
  tool BLOCKS until then. Honour it; do not force a size.
- A limit change requires a pod restart to take effect.
- Shrinking the limit shrinks the heap ceiling, so the working set moves; a second
  measurement under load after the change is part of the method, not optional.
- `MaxRAMPercentage` governs the heap only; non-heap (metaspace, threads, direct
  buffers) is why the limit sits well above the heap.

## Artifact

Apply `deployment-resources.yaml` with the values `sizeMemory` returned.
