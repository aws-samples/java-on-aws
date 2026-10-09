# perf-sensor — acceptance criteria

What a passing run of the CON405 flow looks like: the skills (investigate → root cause →
solution → apply → exit), the page-side rollout/verify loop, and the twelve-item checklist
moving as expected on a clean environment. The commands live in the workshop content
(`java-on-amazon-eks/content/*/index.en.md`); this file holds only the criteria to judge a run
by. When the two disagree, the content is the source of truth.

## Run it

The content is executable through ws-test, which runs every code block in page order, in one
shell, on the IDE:

```bash
cd ~/java-on-aws && git pull -q
node infra/scripts/ws-test/generate.mjs java-on-amazon-eks
bash infra/scripts/ws-test/java-on-amazon-eks.sh
```

Read `infra/scripts/ws-test/reports/java-on-amazon-eks/<run>/output.log` (`Source:` lines point
at content line ranges), `summary.md` (per-block durations) and `failure.md` if a block failed.
Block output goes only to `output.log`; add `--verbose` (`-v`) to also stream it on the console.
`claude` runs non-interactively (`-p`, then `-c -p`); the interactive blocks and all sample
blocks are skipped. For a repeat on the same environment run
`~/java-on-aws/infra/scripts/deploy/java-on-amazon-eks/reset-app.sh` first (hard-resets the app
repo, deletes the boost CR, redeploys `:latest`).

Load runs at 50 writes/s for the whole session and is never started by Claude. The sensor is
read-only; its cAdvisor facts are scoped to the pods that are Ready now. Floor and latency skip
the pod's first minute; steady CPU and throttle ratio use the steady window after readiness and
JIT warm-up; steady CPU is the mean over it minus the JIT compiler threads' share of the CPU
profile, so a pod asked at 2 min and at 10 min reads the same. A score asked on a pod younger than
2 min waits inside `measure`; asked later it returns at once.

## Skill-boundary checks, every optimization turn

Fail the module if any is violated:

- Edits only the files the module names; no `git add`/`commit`; no shell command (no Bash).
- Ends with the exact line "Not deployed. Review the diff, roll out, and re-measure under load
  to confirm the effect."
- No checklist score and no "other improvements" inside an optimization run.
- Every number in the answer comes from a named tool result.

## Expected flips

Numbers vary with the measured working set (the sizing policy is `max(1.4 × peak, 1.5 × floor)`
rounded up to 128 MiB; CPU `steady × 1.5` rounded up to 50m). The verdicts must not.

| Step | Tool cited | Files changed | Score after | Items that move |
|---|---|---|---|---|
| Baseline | `measure`, `diagnoseBlocking` | — | 5/12 | ❌ 2 3 4 6 8 10 11 (6: a 1-core request is several times the steady CPU) |
| Right-size memory | `sizeMemory` | `k8s/deployment.yaml` | 8/12 | 2 3 4 → ✅ |
| Boost startup CPU | `sizeCpu`, `jfr.compilation` | `k8s/startup-cpu-boost.yaml`, `k8s/deployment.yaml` | 9/12 | 6 → ✅ (request from steady CPU); 8 halves (≈ 16 s → ≈ 8 s); `jfr.container.effectiveCpuCount` 1 with `cpuQuotaCores` 2.0 |
| Cache startup (AOT) | `profileTop cpu` (JIT share) | `Dockerfile.aot` | 10/12 | 8 → ✅ (≈ 2.6 s); 11 must still be ❌, else the dump sampling missed the block |
| Restore (CRaC) | `startupLog`, `measure` | `pom.xml`, one Java file, `Dockerfile.crac`, `k8s/deployment.yaml` | 10/12 | 8 ✅ (Restored, < 0.1 s); 3 4 5 stay ✅ from the checkpoint; 6 stays ✅ (steady CPU excludes the JIT, so it reads as on the cold image) |
| Unblock the request path | `diagnoseBlocking`, `sizeMemory`, `sizeCpu` | `UnicornService.java`, `application.yaml` (pool to `poolSizeTarget`), `k8s/deployment.yaml`, `Dockerfile.crac` | 12/12 | 10 11 → ✅ (blocked 0, in-transaction 0, pool waits 0); memory 768 → 512 MiB, new heap baked into the checkpoint, rebuild stated; mean latency drops to single digits |

Record per run: the twelve verdicts after each step, memory limit after step 1 (768 or 1024),
`jfr.container` after step 2 (must not be `null`), the file count after step 5, the `-p` wall
time per call, and the build logs free of `AccessDeniedException` (the IDE role needs
`events:PutEvents` on `event-bus/*` for the checkpoint warm-up).

## Variance rule

Run the flow three times on a fresh or reset environment. Anything that differs between runs
other than prose and measured values — tool choice, artifact content, an extra action after
apply, a different verdict on the same state — is a defect in a skill or a tool description.
Fix it in `skills/` and re-run. 3/3 passing with the expected flips is the acceptance.
