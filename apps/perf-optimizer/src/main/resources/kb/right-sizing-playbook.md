# Java-on-EKS right-sizing & GC playbook (heuristics)

Authoritative RULES for right-sizing a Spring Boot service on Amazon EKS at ~1 vCPU (Spring Boot 4.1, JDK 25). These are decision heuristics — the ACTUAL sizes come from the MEASURED container working-set (floor/peak) for the service, which the optimizer reads live and the labs observe in Grafana. Do NOT hard-code MB/second values here; derive them from measurement.

## Memory: size off the container working-set (RSS + non-heap), never heap alone

- The live heap is a small fraction of the container footprint. The floor is NON-HEAP dominated: metaspace + JIT code cache + thread stacks + JVM base.
- Sizing off heap under-sizes the container and causes OOMKills under load.
- RULE: set `requests.memory` near the MEASURED working-set **floor** (idle) — the correct bin-packing signal. Set `limits.memory` at the MEASURED **peak** plus ~30–50% headroom. A limit at or below the measured peak is unsafe (OOMKill).
- `requests.cpu`: low — sustained CPU is low once JIT settles. `limits.cpu`: `1` (1 vCPU) for this class.
- `-XX:MaxRAMPercentage=75` (explicit). Do not rely on the 25% default. Remove any `-Xmx`/`-Xms` so `MaxRAMPercentage` governs heap off the container limit.

## GC: keep SerialGC, never G1GC on 1 vCPU

- The JVM ergonomic default at ~1 vCPU / small heap is **SerialGC** — keep it.
- **G1GC REGRESSES** on a single core: higher RSS and worse max GC pause, because G1's concurrent threads contend for the one core. Never recommend "upgrade to G1" for this workload.

## Reading the profile: JIT storm vs steady state

- JIT/C2 compiler frames (`PhaseChaitin`, `PhaseIdealLoop`, `PhaseLive`, `Compile::`, `CodeHeap::`) plus a high futex/idle wall% indicate a COLD / WARM-UP window, not steady-state load.
- Do NOT size CPU or memory UP to feed the JIT storm — it disappears after warm-up. If the profile is JIT-dominated, note the window looks like warm-up, size for steady state (lean), and re-profile after a warm-up. (This is why a baseline is captured after a warm-up.)

## In-place pod resize (EKS, K8s 1.27+)

- CPU can be resized in place with no restart; memory shrink needs a rolling restart.
- Startup CPU boost: boot at 2 vCPU (roughly halves startup), then in-place resize CPU down to 1 after ready — no restart. Send the FULL resources map (cpu AND memory) in the resize patch or the API rejects it.

## Applyable deployment snippet (fill sizes from the MEASURED working-set)

```yaml
resources:
  requests: { cpu: "<low>", memory: "<~measured floor>" }
  limits:   { cpu: "1",     memory: "<~measured peak + headroom>" }
env:
  - name: JAVA_TOOL_OPTIONS
    value: >-
      -XX:+UseSerialGC
      -XX:MaxRAMPercentage=75
      -XX:InitialRAMPercentage=50
```
