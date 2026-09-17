---
description: Measure this app's live facts on EKS (no findings, no LLM)
---
Call the `perf-optimizer` MCP tool **`measure`** for service `unicorn-store-spring`
(window ${ARGUMENTS:-15} minutes). Summarize the measured facts: image tag, replicas,
requests/limits, resizePolicy, JAVA_TOOL_OPTIONS, sidecars, HPA, working-set floor/peak,
heap, GC, effective CPUs, startup, restarts, and whether the profiling window is warm.
Do not recommend changes here — that is `analyze`.
