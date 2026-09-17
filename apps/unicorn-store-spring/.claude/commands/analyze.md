---
description: Analyze this app on EKS and rank optimization findings
---
Call the `perf-optimizer` MCP tool **`analyze`** for service `unicorn-store-spring`
(window ${ARGUMENTS:-15} minutes). Present the ranked findings table, then for each
OPEN finding give its measured evidence and the Java-computed values (do not restate
them as your own advice). Note any BLOCKED finding and why. Do not apply anything —
recommend the highest-ranked OPEN finding and offer to `/apply <finding-id>`.

Reminder: all values come from the tool; never invent sizes, flags, or image tags.
