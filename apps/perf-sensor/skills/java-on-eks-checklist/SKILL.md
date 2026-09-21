---
name: java-on-eks-checklist
description: Score a Java workload on EKS against cloud-native performance practices (memory, CPU, startup, latency) from its measured facts. Use when asked how a service is doing, for a score, or after applying an optimization.
---

# java-on-eks-checklist

Score a Java service on EKS against the twelve performance practices in
`references/checklist.md`, using only measured facts from `perf-sensor`.
Deterministic: the same cluster state yields the same score. Never guess a missing
fact — mark it UNKNOWN.

## Procedure

1. Call `perf-sensor.measure <service>`. It returns everything items 1–10 and 12 need
   (workload, runtime, profile summary, window).
2. Call `perf-sensor.diagnoseBlocking <service>` for item 11: it drives a bounded write
   load and samples the thread dump. If the tool is unavailable, item 11 is UNKNOWN.
3. Evaluate every item in `references/checklist.md` as **PASS / FAIL / UNKNOWN**
   from the named evidence fields. A fact that is absent (null) makes its item
   UNKNOWN, not FAIL. Items marked "under load" are UNKNOWN when
   `window.requestRatePerSec` is 0 or null.
4. Report `Score: <passed>/12`, then the UNKNOWN count, then the items grouped as in
   `references/checklist.md` (Memory, CPU, Startup, Latency), each with its verdict and
   **the named fact/signal and value that decided it** (e.g.
   `workload.memLimitMi=2048 / runtime.rssPeakMi=366 = 5.6x`). Every verdict must cite
   the signal it came from — never assert without one.

## Output format

```
Score: <passed>/12   (<n> UNKNOWN)

Memory
  [PASS] 1 memory Guaranteed and honoured — memRequestMi=2048 == memLimitMi=2048, restarts=0
  [FAIL] 2 limit sized from working set — memLimitMi=2048 / rssPeakMi=366 = 5.6x (bar 2.0x)
  …
CPU
  …
Startup
  …
Latency
  …
```

Report only what the facts support. When re-scoring after an applied change, run the
identical procedure and show before → after per item that changed.

This skill **scores; it does not prescribe.** Report each item's verdict and the
deciding evidence only. Do **not** append remediation steps, "how to fix", or
"ask for X" next-step hints for FAIL/UNKNOWN items. If the operator wants a fix, they
ask the optimization skill for that specific improvement.
