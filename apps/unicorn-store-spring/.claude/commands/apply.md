---
description: Apply one optimization finding (takes a finding id), then verify
argument-hint: <finding-id>
---
Apply the finding **`$ARGUMENTS`** for `unicorn-store-spring`:

1. Call `perf-optimizer` tool **`explain unicorn-store-spring $ARGUMENTS`** to get the
   rationale, the ready-to-apply **artifact**, and the exact **apply command(s)**.
2. `git checkout -b opt/$ARGUMENTS`.
3. Edit ONLY the file(s) the finding lists, using the artifact **verbatim** — do not
   change any computed value, flag, size, or image tag. Show me the `git diff` and wait
   for my confirmation.
4. After I confirm, run the apply command(s) (kubectl apply + rollout restart, or build +
   push + set image for image/source changes) and wait for the rollout to complete.
5. Run **`analyze unicorn-store-spring`** again and report this finding's new status —
   it should be **RESOLVED** — with its measured before→after delta.

If the finding is BLOCKED or NOT_EVALUABLE, stop and explain what is missing instead of
applying anything.
