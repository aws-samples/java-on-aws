---
name: java-on-eks-optimization
description: "Optimize a Java service on Amazon EKS: memory, startup, latency. Use when asked to reduce memory, speed up startup, or fix latency of a Java workload on EKS."
---

# java-on-eks-optimization

Optimize a Java service on EKS from measured facts. Every number comes from a
tool — never estimate. The `perf-sensor` tools measure; the EKS MCP Server covers
the non-scored surface (events, logs, ad-hoc resource reads, docs). You propose
the change and wait for confirmation before writing anything.

## 1. Tools

**perf-sensor** (deterministic measurement):
- `measure <service>` — workload + runtime + profile summary + window. Start here.
- `sizeMemory <service> …params` — memory requests/limits/GC with a guard. See Hard rules.
- `threadDump <service>` — summarized thread dump; request-path blocking, top frames.
- `diagnoseBlocking <service>` — drives a bounded write load at the pod and samples the thread
  dump over time; reports peak `requestThreadsBlockedInFutureGet` + summed `topBlockingFrames`.
  The reliable way to find a request-path block (virtual threads hide it from the wall profile);
  works on every image incl. CRaC and needs no benchmark timing.
- `profileTop <service> cpu|wall` — hottest frames; `cpu` → jit/gc share (startup), `wall` → futex
  share. Note: on a virtual-thread app `wall` does NOT reveal request-path blocking (parked
  vthreads unmount); use it for CPU/GC, not for blocking.
- `startupLog <service>` — last `Started`/`Restored` line; verifies a CRaC restore.

**EKS MCP Server** (everything not scored/gated):
- `read_k8s_resource` — resources the sensor does not model (HPA, ConfigMap, ad-hoc reads).
- `get_pod_logs` — logs beyond the startup line (errors, stack traces).
- `get_k8s_events` — restart/OOMKilled/scheduling narrative.
- `search_eks_documentation`, `search_eks_troubleshooting_guide` — EKS guidance.

Do not read desired-state that `measure` already returns via `read_k8s_resource` —
`measure` extracts it deterministically for scoring.

## 2. Hard rules

- **Every number comes from a tool result. Never estimate a size, share, or time.**
- Call `sizeMemory` with the policy parameters from **`references/sizing-policy.yaml`**
  (read the values from that file, pass them verbatim) — **never compute sizes yourself
  and never retype the numbers from prose.**
- If `sizeMemory` returns `BLOCKED`, report the reason and **stop** (do not size).
- **Never recommend G1GC on ≤ 1 vCPU.** `sizeMemory` returns SerialGC there; keep it.
- Use the reference Dockerfiles verbatim except the documented placeholders, filled
  from the app's `pom.xml` (`artifactId`, `version`, `build.finalName`, main class).
- Show the full change and **wait for confirmation** before writing any file.
- After the participant applies, call `measure` again and report **only the applied
  technique's before → after** delta — the metric it targeted (e.g. memory request/limit,
  startup seconds). Do **not** run the full `java-on-eks-checklist` here, and do **not**
  list other or remaining best-practice items or how to fix them: each is the participant's
  next question to discover. Run the checklist only when they explicitly ask
  "how are we doing / score".

**Policy parameters.** The authoritative values live in `references/sizing-policy.yaml`
(machine-readable, so they are used deterministically); the sensor owns the arithmetic.
Read the file and pass the values through. The *why* for each:

- `floorFactor` — requests near the non-heap floor plus headroom.
- `peakFactor` — limit over the observed load peak.
- `floorSafetyFactor` — protects against an under-observed peak.
- `roundMi` — scheduler-friendly granularity.
- `warmSeconds` — past the bulk of JIT warm-up; a 120 s load run after apply satisfies it.
- `minSamples` — enough profile samples for a floor/peak.
- `minRequestRate` / `minDeltaMi` — what counts as "load observed".

## 3. Question → procedure

- **"reduce memory"** → `measure`, then `sizeMemory` (params above). Explain footprint
  vs heap from the evidence (working-set floor/peak vs heap committed). Propose the
  `deployment-resources.yaml` fragment with the returned values. Expect a second pass
  after apply.
- **"start faster without changing the image"** → `measure`, `startupLog`. Propose
  the **`startup-cpu-boost.yaml`** `StartupCPUBoost` CR (the Kube Startup CPU Boost
  controller is platform-installed): boots the container at higher CPU and resizes it
  down automatically on Ready — the production path, one namespaced CR, no per-pod
  work. Reference `deployment-cpu-boost.yaml` only to explain the underlying in-place
  resize (and the manual `--subresource resize`) — that manual patch is for
  understanding the mechanism, not for production.
- **"start faster without changing the application"** → `startupLog`, `profileTop cpu`
  (JIT / class-loading share). Propose AOT (Java 25) or CDS (older JDK); render
  `Dockerfile.aot` with placeholders filled.
- **"start even faster / under a second"** → `startupLog`; propose CRaC. Add the
  `org.crac` dependency to `pom.xml` (not present by default), render `Dockerfile.crac`,
  and **scan `src/` for classes holding network clients or file handles** — propose a
  CRaC `Resource` hook for each. Mention credentials-at-restore. **Clear
  `JAVA_TOOL_OPTIONS` (GC/heap flags) from the Deployment for the CRaC image** — those
  are baked into the checkpoint; leaving them crash-loops the restore.
- **"fix latency under load"** → `diagnoseBlocking <service>`. It drives a bounded write
  load and samples the thread dump, so it names the blocking frame and `file:line`
  (`…CompletableFuture.get`) on **any image, including CRaC**, with no benchmark to time.
  Do **not** use `profileTop wall` to find this — on a virtual-thread app the parked
  request thread unmounts and never appears in the flame graph (and on CRaC the wall
  profile collapses to native). Propose the non-blocking change; size the pool from
  evidence. Verify with the **HTTP request-latency metric** (`http_server_requests_seconds`,
  every image) and a second `diagnoseBlocking` (blocked → 0). See `references/blocking-calls.md`.
- **"how are we doing / score"** → run the `java-on-eks-checklist` skill.

## 4. Answer format

- **Finding** — one line.
- **Evidence** — the tool values, and **name the tool and the specific signal** they came
  from (e.g. "from `diagnoseBlocking`: `requestThreadsBlockedInFutureGet`=3, frame
  `…CompletableFuture.get`" / "from `sizeMemory`: rssPeak 517Mi" / "from `profileTop cpu`:
  jitShare 42%"). Every decision must trace to a named signal — never an estimate.
- **Technique** — 2–4 lines from the matching `references/*.md`.
- **Change** — the full artifact (fragment / Dockerfile / diff).
- **Apply** — the commands from the app's `CLAUDE.md` (`scripts/build.sh`, `kubectl`).
- **Verify** — which tool to re-run and what should change.

Link the reference file and the matching Immersion Day page.
