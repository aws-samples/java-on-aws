---
name: java-on-eks-checklist
description: Score a Java workload on EKS against cloud-native performance practices (memory, CPU, startup, latency) from its measured facts. Use when asked how a service is doing, for a score, or after applying an optimization.
---

# java-on-eks-checklist

Score a Java service on EKS against the twelve performance practices in
`references/checklist.md`. The score is computed by `perf-sensor`, not by you: the
sensor measures the service and evaluates the checklist rules over the facts, so the same
cluster state yields the same score and the same evidence. `references/checklist.md`
explains each practice, its bar and its sources.

## Procedure

Scoring needs a load run flowing (the operator's benchmark); five items are only decidable
under load.

1. Call `perf-sensor.checklist <service>` (default `minUptimeSeconds = 120`). A pod younger
   than that has no peak, steady CPU or throttle share yet, so the sensor waits in slices of
   ≤ 30 s: while `status` is `SETTLING`, write one line for the user ("pod is N s old —
   scoring at 120 s, M s to go", from `podUptimeSeconds` and `settleRemainingSeconds`) and
   call again with the same parameters.
2. When `status` is `OK`, print `markdown` verbatim: the score line and the table. Do not
   recompute, reorder or reword a verdict or an evidence cell.
3. If `note` is set (no load flowing), print it after the table, and say that the service's
   load (its repo documents how, e.g. a `scripts/load*.sh`) must be running. Do not start
   load yourself.

The same score is available to the operator with
`curl -sN "localhost:8090/api/v1/checklist/<service>?format=text&wait=true"`.

## Output format

No code fences. The `markdown` field as returned, icon first: ✅ PASS, ❌ FAIL, 🟡 UNKNOWN
(the evidence names the missing fact). No before/after comparison with earlier scores:
report the current state only.

This skill **scores; it does not prescribe.** Report the table only. Do **not** append
remediation steps, "how to fix", or "ask for X" next-step hints for FAIL/UNKNOWN items. If
the operator wants a fix, they ask the optimization skill for that specific improvement.
