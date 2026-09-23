---
name: java-on-eks-optimization
description: "Optimize a Java service on Amazon EKS: memory, startup, latency. Use when asked to reduce memory, speed up startup, or fix latency of a Java workload on EKS."
---

# java-on-eks-optimization

Optimize a Java service on EKS from measured facts. Every number comes from a
tool — never estimate. The `perf-sensor` tools measure; the EKS MCP Server covers
the non-scored surface (events, logs, ad-hoc resource reads, docs). You investigate,
name the root cause, explain the change, apply it to the working tree, and stop.
Rollout and verification belong to the operator.

## 1. Tools

**perf-sensor** (deterministic measurement):
- `measure <service>` — workload + runtime + profile summary + `jfr` (the JVM's own 10-min
  ring: container limits as the JVM read them, `jvmArgs`, GC pauses, pinning, monitors,
  safepoints, JIT compilation) + window. Start here.
- `sizeMemory <service> …params` — memory requests/limits/GC with a guard. See Hard rules.
- `sizeCpu <service> …params` — steady-state CPU request from measured p95 usage, same guard;
  limit unchanged.
- `threadDump <service>` — summarized thread dump; request-path blocking, top frames.
- `diagnoseBlocking <service> minRequestRate` — samples the JSON thread dump over time **while
  the operator's load run is flowing** (the sensor drives no traffic); reports peak
  `requestThreadsBlockedInFutureGet` + summed `topBlockingFrames`. Returns BLOCKED when no load
  is flowing right now — then ask the operator to start the load run and call again during it.
  The only way to find a request-path block on virtual threads: the wall profile cannot see a
  parked virtual thread and JFR records `ThreadPark` only for platform threads. Works on every
  image incl. CRaC.
- `profileTop <service> cpu|wall` — hottest frames; `cpu` → jit/gc share (startup), `wall` → futex
  share. Note: on a virtual-thread app `wall` does NOT reveal request-path blocking (parked
  vthreads unmount); use it for CPU/GC, not for blocking.
- `startupLog <service>` — last `Started`/`Restored` line; verifies a CRaC restore.

**EKS MCP Server** (read tools only; everything not scored/gated):
- `list_k8s_resources` — resources the sensor does not model (HPA, ConfigMap, StartupCPUBoost, ad-hoc reads).
- `get_pod_logs` — logs beyond the startup line (errors, stack traces).
- `get_k8s_events` — restart/OOMKilled/scheduling narrative.
- `search_eks_troubleshoot_guide`, `get_eks_insights` — EKS guidance.
- Its write tools (`apply_yaml`, `manage_k8s_resource`, `manage_eks_stacks`, `add_inline_policy`,
  `generate_app_manifest`) are denied and the server runs without `--allow-write`: never call them.

Do not read desired-state that `measure` already returns via `list_k8s_resources` —
`measure` extracts it deterministically for scoring.

## 2. Procedure — every question follows these five steps

1. **Investigate.** `measure`, then the tool the question calls for (§4). Read the
   app's `pom.xml` / `k8s/` / `src/` only for what the change needs.
2. **Root cause.** One line: what the evidence shows and why it costs memory,
   startup time or latency. Name the tool and the signal
   (e.g. "from `sizeMemory`: workingSetPeak 366 Mi vs limit 2048 Mi").
3. **Solution.** Why this change resolves that root cause, 3–5 lines from the
   matching `references/*.md`. Link the reference file.
4. **Apply.** Edit the files in the working tree. Do not stage or commit — the
   operator reviews the change with `git diff`.
5. **Exit.** Report `Files changed: <paths>` and close with exactly:
   `Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect.`
   Then stop.

## 3. Hard rules

- **Every number comes from a tool result. Never estimate a size, share, or time.**
- Call `sizeMemory`, `sizeCpu` and `diagnoseBlocking` with the policy parameters from
  **`references/sizing-policy.yaml`** (read the values from that file, pass them verbatim) —
  **never compute sizes yourself and never retype the numbers from prose.** `sizeMemory`
  returns `requests == limits` (Guaranteed memory QoS); keep them equal. `sizeCpu` changes
  the request only; keep the limit. If `sizeCpu.clampedToLimit` is true, use `requestsCpu`
  as returned (it equals the limit) and quote `note`: the container is CPU-bound at this
  load, the request can't express headroom, and the real fix is a cheaper request path or a
  higher limit — say which, don't change the limit on your own.
- If a tool returns `BLOCKED`, report the reason and **stop** (do not size, do not guess).
- **Never recommend G1GC on ≤ 1 vCPU.** `sizeMemory` returns SerialGC there; keep it.
- Use the reference Dockerfiles verbatim except the documented placeholders, filled
  from the app's `pom.xml` (`artifactId`, `version`, `build.finalName`, main class).
- **After step 4 you do not build, deploy, patch, drive load, or re-measure.** If asked
  to deploy or verify, answer with the step-5 closing line. A new question starts a new
  five-step run.
- **If the measured state already matches the solution** (e.g. `sizeMemory` returns the
  values the Deployment already carries, or the artifact is already present), report the
  root cause as resolved with the evidence and stop. No edit.
- Do not run the `java-on-eks-checklist` inside an optimization run, and do not list
  other or remaining improvements: each is the operator's next question. Run the
  checklist only when explicitly asked "how are we doing / score".
- Do not repeat the theory the references hold beyond the 3–5 lines of step 3.

**Policy parameters.** The authoritative values live in `references/sizing-policy.yaml`
(machine-readable, so they are used deterministically); the sensor owns the arithmetic.
Read the file and pass the values through. The *why* for each:

- `peakFactor` — memory limit over the observed load peak.
- `floorSafetyFactor` — protects against an under-observed peak.
- `roundMi` — scheduler-friendly granularity.
- `cpuFactor` / `roundMillicores` — CPU request as headroom over measured p95 steady-state usage.
- `cracHeap` — `-Xmx`/`-Xms` baked into a CRaC checkpoint as a share of the pod memory limit.
- `warmSeconds` — past the bulk of JIT warm-up; a 120 s load run after a restart satisfies it.
- `minSamples` — enough profile samples for a floor/peak.
- `minRequestRate` / `minDeltaMi` — what counts as "load observed".

## 4. Question → tools and reference

- **"reduce memory"** → `measure`, then `sizeMemory` (params above). Explain footprint
  vs heap from the evidence (working-set floor/peak vs heap committed vs observed
  `maxHeapMi`). Artifact: `deployment-resources.yaml` with the returned values. Say that
  a second pass after a load run is part of the method (the heap moves with the limit).
  Reference: `right-size-memory.md`.
- **"start faster without changing the image"** → `measure`, `startupLog`, `sizeCpu`.
  Three edits in one change: (a) `startup-cpu-boost.yaml` `StartupCPUBoost` CR (the Kube
  Startup CPU Boost controller is platform-installed) — boots the container at higher CPU
  and resizes it down automatically on Ready; (b) `requests.cpu` in the Deployment set to
  `sizeCpu.requestsCpu`, `limits.cpu` unchanged — the boost supplies the boot CPU, so the
  steady request no longer has to; (c) `-XX:ActiveProcessorCount=<ceil(limits.cpu)>` appended
  to `JAVA_TOOL_OPTIONS` — the JVM sizes GC/JIT/ForkJoin threads once at start and would
  otherwise keep the boosted count after the resize down (`jfr.container.effectiveCpuCount`
  shows what it read). Reference `deployment-cpu-boost.yaml` only to explain the underlying
  in-place resize. Reference: `in-place-resize.md`.
- **"start faster without changing the application"** → `startupLog`, `profileTop cpu`
  (JIT / class-loading share). Artifact: `Dockerfile.aot` (Java 25) or CDS (older JDK) with
  placeholders filled. Reference: `build-time-cache.md`.
- **"start even faster / under a second"** → `measure` (`jfr.compilation` shows the JIT
  volume a cold start pays), `startupLog`; CRaC. Artifact:
  `org.crac` dependency in `pom.xml` (not present by default), `Dockerfile.crac` with
  `JAR_FILE` from `pom.xml`, `WARMUP_CMD` = one `curl` on the app's hot request path (the
  checkpoint is taken after a warm-up), `JAVA_HEAP_OPTS` from `workload.memLimitMi` × `cracHeap`
  shares (whole MiB, e.g. 640 → `-Xmx480m -Xms320m`), `JAVA_CPU_OPTS` =
  `-XX:ActiveProcessorCount=<ceil(workload.cpuLimitCores)>`, and a CRaC `Resource` hook for each
  class in `src/` holding network clients or file handles. Mention credentials-at-restore
  and that a later memory-limit change needs a rebuild. **Remove `JAVA_TOOL_OPTIONS` (GC/heap flags) from the
  Deployment for the CRaC image** — those are baked into the checkpoint; leaving them
  crash-loops the restore. Reference: `crac.md`.
- **"fix latency under load" / "some requests take seconds" / "slow writes" / "tail latency"** →
  `diagnoseBlocking <service>` while the operator's load
  run is flowing (if BLOCKED: say "the service's load must be running — start it and ask
  again while it runs" and stop; do not start load yourself);
  `measure` for the in-JVM context (`jfr.pinned`, `jfr.monitorTop`, `jfr.gc.maxMs`,
  `jfr.safepointTotalMs`, `latencyMeanMs`).
  It names the blocking frame and `file:line` (`…CompletableFuture.get`) on **any image,
  including CRaC**. Do **not** use `profileTop wall` to find this. Artifact: the
  non-blocking change; if `blockedInsideTransaction > 0`, also move the remote call out of
  the transaction (after commit — the connection is held for the round-trip otherwise; read
  the `@Transactional` method in `src/` to show it); if `requestThreadsWaitingForConnection > 0`, also
  size the connection pool to the observed concurrency. Reference: `blocking-calls.md`.
- **"right-size again" / "re-size" / "re-measure after the change" / "the sizing is stale"** →
  `measure`, `sizeMemory` and `sizeCpu` in one pass (a code or runtime change moves the
  working set and the CPU demand; the earlier numbers were right for the earlier code).
  One change with everything the two tools returned: memory `requests == limits`, CPU
  `requests` (limit unchanged), `MaxRAMPercentage`/`InitialRAMPercentage` when the image
  reads them; on a CRaC image the heap bounds live in the checkpoint, so update
  `JAVA_HEAP_OPTS` in `Dockerfile.crac` from the new limit and say the image must be
  rebuilt. Cite old → new for each value. Reference: `right-size-memory.md`.
- **"item 11 still fails" / "pool waits" / "connection pool"** → `diagnoseBlocking`. If
  `requestThreadsBlockedInFutureGet == 0` and `blockedInsideTransaction == 0` but
  `requestThreadsWaitingForConnection > 0`, the pool is smaller than the request concurrency: set the
  pool's maximum size (Hikari `maximum-pool-size` in the app config) to
  `requestThreadsActive` (peak in-flight request threads across the samples), not a round
  number; say which value you read. If blocking is still > 0, fix that first
  (previous bullet). Reference: `blocking-calls.md`.
- **"how are we doing / score"** → run the `java-on-eks-checklist` skill.

## 5. Answer format

```
Root cause: <one line, with tool + signal>
Evidence:   <tool values, each named>
Solution:   <3–5 lines> — see references/<file>
Files changed: <paths>
Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect.
```
