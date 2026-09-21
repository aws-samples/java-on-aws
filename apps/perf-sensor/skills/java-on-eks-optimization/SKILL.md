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

## 2. Procedure — every question follows these five steps

1. **Investigate.** `measure`, then the tool the question calls for (§4). Read the
   app's `pom.xml` / `k8s/` / `src/` only for what the change needs.
2. **Root cause.** One line: what the evidence shows and why it costs memory,
   startup time or latency. Name the tool and the signal
   (e.g. "from `sizeMemory`: rssPeak 366 Mi vs limit 2048 Mi").
3. **Solution.** Why this change resolves that root cause, 3–5 lines from the
   matching `references/*.md`. Link the reference file.
4. **Apply.** Edit the files in the working tree. Do not stage or commit — the
   operator reviews the change with `git diff`.
5. **Exit.** Report `Files changed: <paths>` and close with exactly:
   `Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect.`
   Then stop.

## 3. Hard rules

- **Every number comes from a tool result. Never estimate a size, share, or time.**
- Call `sizeMemory` with the policy parameters from **`references/sizing-policy.yaml`**
  (read the values from that file, pass them verbatim) — **never compute sizes yourself
  and never retype the numbers from prose.** `sizeMemory` returns `requests == limits`
  (Guaranteed memory QoS); keep them equal.
- If `sizeMemory` returns `BLOCKED`, report the reason and **stop** (do not size).
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

- `peakFactor` — limit over the observed load peak.
- `floorSafetyFactor` — protects against an under-observed peak.
- `roundMi` — scheduler-friendly granularity.
- `warmSeconds` — past the bulk of JIT warm-up; a 120 s load run after a restart satisfies it.
- `minSamples` — enough profile samples for a floor/peak.
- `minRequestRate` / `minDeltaMi` — what counts as "load observed".

## 4. Question → tools and reference

- **"reduce memory"** → `measure`, then `sizeMemory` (params above). Explain footprint
  vs heap from the evidence (working-set floor/peak vs heap committed vs observed
  `maxHeapMi`). Artifact: `deployment-resources.yaml` with the returned values. Say that
  a second pass after a load run is part of the method (the heap moves with the limit).
  Reference: `right-size-memory.md`.
- **"start faster without changing the image"** → `measure`, `startupLog`. Artifact:
  `startup-cpu-boost.yaml` `StartupCPUBoost` CR (the Kube Startup CPU Boost controller is
  platform-installed): boots the container at higher CPU and resizes it down automatically
  on Ready. Do not change the Deployment's CPU request or limit in this run. Reference
  `deployment-cpu-boost.yaml` only to explain the underlying in-place resize.
  Reference: `in-place-resize.md`.
- **"start faster without changing the application"** → `startupLog`, `profileTop cpu`
  (JIT / class-loading share). Artifact: `Dockerfile.aot` (Java 25) or CDS (older JDK) with
  placeholders filled. Reference: `build-time-cache.md`.
- **"start even faster / under a second"** → `startupLog`; CRaC. Artifact: `org.crac`
  dependency in `pom.xml` (not present by default), `Dockerfile.crac`, and a CRaC
  `Resource` hook for each class in `src/` holding network clients or file handles.
  Mention credentials-at-restore. **Remove `JAVA_TOOL_OPTIONS` (GC/heap flags) from the
  Deployment for the CRaC image** — those are baked into the checkpoint; leaving them
  crash-loops the restore. Reference: `crac.md`.
- **"fix latency under load"** → `diagnoseBlocking <service>`. It drives a bounded write
  load and samples the thread dump, so it names the blocking frame and `file:line`
  (`…CompletableFuture.get`) on **any image, including CRaC**. Do **not** use
  `profileTop wall` to find this. Artifact: the non-blocking change plus a pool size from
  evidence (`hikariPendingMax`). Reference: `blocking-calls.md`.
- **"how are we doing / score"** → run the `java-on-eks-checklist` skill.

## 5. Answer format

```
Root cause: <one line, with tool + signal>
Evidence:   <tool values, each named>
Solution:   <3–5 lines> — see references/<file>
Files changed: <paths>
Not deployed. Review the diff, roll out, and re-measure under load to confirm the effect.
```
