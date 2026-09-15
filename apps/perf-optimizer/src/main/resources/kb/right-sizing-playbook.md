# Java-on-EKS right-sizing & GC playbook (measured)

Authoritative rules for right-sizing a Spring Boot service on Amazon EKS at ~1 vCPU.
These numbers are MEASURED for `unicorn-store-spring` (Spring Boot 4.1, Amazon Corretto JDK 25) and generalize to this class of small-heap, single-core Java microservice.

## Memory: size off RSS + non-heap, never heap alone

- The live heap is tiny (~50 MB used / ~67 MB committed) but the container RSS floor is ~380 MB idle and ~517 MB under load.
- The floor is **non-heap**: metaspace + JIT code cache + thread stacks + JVM base. Sizing off heap under-sizes the container and causes OOMKills under load.
- **Validated values:** `requests.memory: 512Mi` (near the RSS floor, correct bin-packing signal), `limits.memory: 768Mi` (peak RSS + headroom). A 512Mi *limit* is unsafe — peak RSS hit ~517 MB.
- `requests.cpu: 250m`, `limits.cpu: 1` (1 vCPU). Sustained CPU is low once JIT settles.
- `-XX:MaxRAMPercentage=75` (explicit). On a 768Mi limit → ~576 MB max heap, far above the ~67 MB committed, while leaving room for the non-heap floor. Do not rely on the 25% default. Remove any `-Xmx`/`-Xms` so `MaxRAMPercentage` governs.

## GC: keep SerialGC, never G1GC on 1 vCPU

- The JVM ergonomic default at ~1 vCPU / small heap is **SerialGC** — keep it.
- **G1GC REGRESSES here** (measured): ~+80 MB RSS and ~20x worse max GC pause, because G1's concurrent threads contend for the single core. Never recommend "upgrade to G1" for this workload.
- SerialGC on this service: young pauses ~3 ms, no full GCs under load.

## Reading the profile: JIT storm vs steady state

- JIT/C2 compiler frames (`PhaseChaitin`, `PhaseIdealLoop`, `PhaseLive`, `Compile::`, `CodeHeap::`) plus a high futex/idle wall% indicate a COLD / WARM-UP window, not steady-state load.
- Do NOT size CPU or memory UP to feed the JIT storm — it disappears after warm-up. If the profile is JIT-dominated, note the window looks like warm-up, size for steady state (lean), and re-profile after a warm-up. (This is why a baseline is captured after a warm-up.)

## In-place pod resize (EKS, K8s 1.27+)

- CPU can be resized in place with no restart; memory shrink needs a rolling restart.
- Startup CPU boost: boot at 2 vCPU (halves startup), then in-place resize CPU down to 1 after ready — no restart. Send the FULL resources map (cpu AND memory) in the resize patch or the API rejects it.

## Applyable deployment snippet

```yaml
resources:
  requests: { cpu: "250m", memory: "512Mi" }
  limits:   { cpu: "1",    memory: "768Mi" }
env:
  - name: JAVA_TOOL_OPTIONS
    value: >-
      -XX:+UseSerialGC
      -XX:MaxRAMPercentage=75
      -XX:InitialRAMPercentage=50
```
