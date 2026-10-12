# ws-test

Runs a workshop's content as a test: every code block of every page, in page order, in one
shell, on the workshop IDE. The content stays the source of truth: the test script is
generated from it, and the samples and screenshots in it are refreshed from a real run.

```
generate.mjs          content → <workshop>.sh (committed, regenerate after every content change)
runtime.sh            the harness the generated scripts source
remote/               operate a Workshop Studio environment from a laptop (SSM, S3)
samples/              put a run's real output into the content's "Sample" expands
capture/              Grafana panel and IDE screenshots (Playwright, headless Chrome)
analysis/             Pyroscope CPU shares per pod and window
```

## Generate and run on the IDE

```bash
node infra/scripts/ws-test/generate.mjs java-performance    # reads ../java-performance/content
bash infra/scripts/ws-test/java-performance.sh [--from WEIGHT[:BLOCK]] [--to ...] [--skip ...] [-v]
```

`generate.mjs` expects the content repository next to java-on-aws (`workshops.json` names
it). Blocks with `showCopyAction=false` or `test=false` are skipped, `testTimeout=<s>` sets a
block's timeout, `ws-test: false` in the front matter skips a page. A block fails on a
non-zero exit under `set -Eeuo pipefail`; there is no expected-failure attribute, so an
intended failure is written `cmd || echo "rejected, as intended"`.

A run writes `reports/<workshop>/<run>/` (git-ignored): `output.log` (each block's output
after a `Source: <page>:<lines>` line), `summary.md` (per-block status and duration),
`failure.md` for a failed block, `events.jsonl`, `junit.xml`.

## Operator loop from a laptop

The IDE clones java-on-aws `main` at bootstrap. To test a branch that is not pushed, the
scripts in `remote/` move the IDE to it and run there. They find the environment through
the AWS account alone: the IDE instance by its `Name=ide` tag, the bucket from the SSM
parameter `workshop-bucket-name`, the URL from the `workshop-stack` outputs. The operator
role needs SSM, S3, EC2 and CloudFormation read; every cluster command runs on the IDE.

```bash
export WS_ENV_FILE=~/path/to/.env     # git-ignored: export AWS_DEFAULT_REGION=... AWS_ACCESS_KEY_ID=...
cd infra/scripts/ws-test

node generate.mjs java-performance && git commit ...    # content changed: regenerate, commit
remote/sync-branch.sh [--skills] [--sensor]             # IDE ~/java-on-aws → this branch
remote/run-ws-test.sh java-performance                  # reset-app.sh, then the run (~20 min)
REPORT=$(remote/fetch-report.sh java-performance)       # → ~/.cache/ws-test/reports/...
samples/refresh.py java-performance "$REPORT" ../../../../java-performance/content
```

- `sync-branch.sh` ships only commits. `--skills` reinstalls the Claude Code skills and
  settings (`claude-code.sh`; reset-app does not), `--sensor` rebuilds and reinstalls the
  sensor (`perf-sensor.sh`).
- `run-ws-test.sh` runs detached on the IDE and polls every 30 s; `--no-wait` returns at
  once, `--status` shows the last lines later, `--no-reset` skips `reset-app.sh`, arguments
  after `--` go to the test script. Never use an interactive Claude on the IDE during a run:
  the run's `claude -c` resumes the most recent session.
- `run-on-ide.sh SCRIPT|-` runs any script on the IDE as `ec2-user` in a login shell. SSM
  keeps only the first 24 KB of output and marks a command Failed when its last command
  exits non-zero.
- `refresh.py` uses the per-workshop mapping `samples/<workshop>.py`, masks the account ID
  as `123456789012` and wraps Claude's answers at 110 columns. A block re-run by hand
  replaces its expand with that real output; the next refresh overwrites it. Review with
  `git diff`.

### Screenshots

```bash
cd capture && npm install    # once; uses the installed Chrome
node grafana-panels.mjs "$REPORT" '[{"name":"baseline-grafana","from":"2026-10-11T08:35:00Z","to":"2026-10-11T08:40:30Z"}]' OUT_DIR
node grafana-profiles.mjs "$REPORT" '[{"name":"x","pod":"<pod>","from":"<ISO>","to":"<ISO>","search":"CompileBroker"}]' OUT_DIR
./ide.sh tools OUT_DIR       # Claude lists the MCP tools (not during a run)
./ide.sh scm OUT_DIR         # Source Control diff of the module 2 commit
```

- Grafana: the URL and password come from the report's "Open Grafana" block. For a module's
  shot, end the window about 150 s after its commit and start it shortly before the run:
  `git -C ~/environment/unicorn-store-spring log --format='%cI %s'` on the IDE.
- IDE: `ide.sh` turns `terminal.integrated.gpuAcceleration` off on the IDE for the capture
  (headless Chrome renders the terminal blank otherwise) and restores the settings file;
  `scm` detaches the app repo at the baseline commit with the target commit's worktree and
  switches back afterwards. Before each shot notifications are cleared, the mouse parked on
  the activity bar, and the account ID replaced in the page text. Terminal rename prompts do
  not work headless.

### CPU profile shares

```bash
analysis/pyroscope-shares.sh "baseline first 60s|vqlh7|2026-10-11T08:36:05Z|2026-10-11T08:37:05Z"
```

Prints the share of the pod's CPU samples in the JIT compiler threads, class loading, GC and
the interpreter. Start windows at the pod's first upload. Use the shares, not the CPU
totals (uploads arrive in 15 s buckets).

## Judging a java-performance run

`run-ws-test.sh` passing means every block exited 0. The flow also has to behave the same
way every time. Load runs at 50 writes/s for the whole run and is never started by Claude.
The sensor is read-only and scopes its facts to the pods that are Ready now; a checklist
asked on a pod younger than 2 min waits inside `measure`.

### Skill boundary, every optimization answer

Fail the module if any is violated:

- Edits only the files the module names; no `git add`/`commit`; no shell command (no Bash).
- Ends with the exact line "Not deployed. Review the diff, roll out, and re-measure under load
  to confirm the effect."
- No checklist score and no "other improvements" inside an optimization run.
- Every number in the answer comes from a named tool result.

### Expected flips

Numbers vary with the measured working set (memory `max(1.4 × peak, 1.5 × floor)` rounded up to
128 MiB, CPU `steady × 1.5` rounded up to 50m). The verdicts must not.

| Module | Tool cited | Files changed | Score after | Items that move |
|---|---|---|---|---|
| Measure the baseline | `checklist` | — | 5/12 | ❌ 2 3 4 6 8 10 11 (6: a 1-core request is several times the steady CPU) |
| Improve the manifest | `sizeMemory`, `sizeCpu`, `startupLog` | `k8s/deployment.yaml`, `k8s/startup-cpu-boost.yaml` | 9/12 | 2 3 4 6 → ✅; 8 halves (≈ 15 s → ≈ 8 s); `jfr.container` effectiveCpuCount 1 with `cpuQuotaCores` 2.0; `cpu.max` 1 core after the resize |
| Improve the image, AOT | `startupLog`, `profileTop` | `Dockerfile.aot` | (no checklist) | startup line *Started* in about a third of the boosted cold start |
| Improve the image, CRaC | `startupLog`, `measure` | `pom.xml`, one Java file, `Dockerfile.crac`, `k8s/deployment.yaml` | 10/12 | 8 → ✅ (Restored, < 0.1 s); 3 4 5 stay ✅ from the checkpoint; 2 may sit near its bar (the restored pod's working set is lower under a limit sized for the cold one) |
| Improve the code | `diagnoseBlocking`, `sizeMemory`, `sizeCpu` | `UnicornService.java`, `k8s/deployment.yaml` (sizes, `terminationGracePeriodSeconds`), `Dockerfile.crac` | 12/12 | 10 11 → ✅ (blocked 0, in-transaction 0; pool waits shown, not scored); memory steps down, new heap baked into the checkpoint, rebuild stated |
| Enforce the practices | `measure` | `k8s/policy.yaml` | 12/12 | none; the policy matches `references/kyverno-policy.yaml`; the PolicyReport shows the running Deployment passing; an apply with `-Xmx` is denied with the item 3 message |

Record per run: the twelve verdicts after each module, the memory limit after module 2 (768 or
1024), `jfr.container` after module 2 (must not be `null`), the files changed in module 4, the
`claude -p` wall time per call (`summary.md`), and build logs free of `AccessDeniedException`
(the IDE role needs `events:PutEvents` on `event-bus/*` for the checkpoint warm-up).

### Variance rule

Run the flow three times on a fresh or reset environment. Anything that differs between runs
other than prose and measured values (tool choice, artifact content, an extra action after
apply, a different verdict on the same state) is a defect in a skill or a tool description.
Fix it in `apps/perf-sensor/skills/` and run again. 3/3 passing with the expected flips is the
acceptance.
