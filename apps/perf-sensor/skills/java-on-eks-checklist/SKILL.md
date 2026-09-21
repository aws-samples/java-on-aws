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

Scoring needs a load run flowing (the operator's benchmark); five items are only decidable
under load and `diagnoseBlocking` samples live threads.

1. Call `perf-sensor.measure <service>`. It returns everything items 1–10 and 12 need
   (workload, runtime, profile summary, `jfr` ring facts, window).
2. Call `perf-sensor.diagnoseBlocking <service>` with `minRequestRate` from the optimization
   skill's `references/sizing-policy.yaml` for item 11. It samples the thread dump while the
   load flows and drives no traffic. If it returns BLOCKED, item 11 is UNKNOWN with its reason.
3. Evaluate every item in `references/checklist.md` as **PASS / FAIL / UNKNOWN**
   from the named evidence fields. A fact that is absent (null) makes its item
   UNKNOWN, not FAIL. Items marked *under load* are UNKNOWN when
   `window.requestRatePerSec` is null or below `minRequestRate` (probe traffic alone is
   ≈ 0.5 rps and does not count as load); say "no load in window" as the reason.
4. Report `Score: <passed>/12`, then the table in `references/checklist.md` order (1–12),
   each row with its icon, number, practice and **the named fact/signal and value that
   decided it** (e.g. `704 / peak 347 = 2.03× (bar 2.0)`). Every verdict must cite the
   signal it came from — never assert without one.

## Output format

No code fences. One markdown table, icon first: ✅ PASS, ❌ FAIL, 🟡 UNKNOWN (name the
missing fact in Evidence). Evidence is one short clause with the deciding values and the bar.

Score: 6/12

| | # | Practice | Evidence |
|---|---|---|---|
| ✅ | 1 | Memory Guaranteed and honoured | request 704 == limit 704, restarts 0 |
| ❌ | 2 | Limit sized from working set | 704 / peak 347 = 2.03× (bar 2.0) |
| ❌ | 3 | Heap follows the container | maxHeap 3906 / 704 = 5.55× (bar 0.5–0.8) |
| 🟡 | 12 | Pool not a bottleneck | hikariPendingMax null — metric not scraped |

No before/after comparison with earlier scores: report the current state only.

This skill **scores; it does not prescribe.** Report each item's verdict and the
deciding evidence only. Do **not** append remediation steps, "how to fix", or
"ask for X" next-step hints for FAIL/UNKNOWN items. If the operator wants a fix, they
ask the optimization skill for that specific improvement.
