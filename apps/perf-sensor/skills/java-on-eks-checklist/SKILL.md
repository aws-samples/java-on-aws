---
name: java-on-eks-checklist
description: Score a Java workload on EKS against cloud-native best practices from its measured facts. Use when asked how a service is doing, for a score, or after applying an optimization.
---

# java-on-eks-checklist

Score a Java service on EKS against cloud-native best practices, using only
measured facts from `perf-sensor`. Deterministic: the same cluster state yields
the same score. Never guess a missing fact — mark it UNKNOWN.

## Procedure

1. Call `perf-sensor.measure <service>`. This returns everything items 1–9 need
   (workload, runtime, profile summary, window).
2. If a thread dump is wanted for item 10, also call `perf-sensor.threadDump <service>`.
   Without a dump, item 10 is UNKNOWN.
3. Evaluate every item in `references/checklist.md` as **PASS / FAIL / UNKNOWN**
   from the named evidence field. A fact that is absent (null) makes its item
   UNKNOWN, not FAIL.
4. Report `score/total`, where total counts only PASS+FAIL items (UNKNOWN is not
   counted). Then list the items grouped as in `references/checklist.md`, each with
   its verdict, the evidence value(s) that decided it, and the source link for the
   group.

## Output format

```
Score: <passed>/<total>   (<n> UNKNOWN, not counted)

Resources
  [PASS] 1 requests and limits set — requests.cpu=…, requests.memory=…Mi, limits=…
  [FAIL] 2 memory limit within 2× working set — limits.memory=…Mi / rssPeak=…Mi = …×
  …
  source: <url>

JVM ergonomics
  …
```

Report only what the facts support. When re-scoring after an applied change,
run the identical procedure and show before → after per item.
