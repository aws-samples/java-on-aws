# Blocking calls on the request path

## Introduction

A request thread that blocks on a synchronous `Future.get()` / `join()` — waiting
for an async client (event publish, downstream call) to finish — holds the thread
idle while latency climbs under load. The fix is to not block the request path:
return without waiting, or bound and size the work deliberately.

## How to see it: thread dump under load, not the flame graph

This app runs on **virtual threads** (`spring.threads.virtual.enabled`). A request that
calls a blocking `Future.get()` parks the virtual thread, which **unmounts from its
carrier** — so a *sampling* profiler has no thread to sample while it waits. The block is
therefore **invisible in the wall flame graph on every image** (plain, AOT, and CRaC), and
`futexWallShare` is at best a vague "something is parked" aggregate (carriers park
normally), not a pointer to the blocking line. On CRaC the wall profile degrades further
(the restored JVM's stacks collapse to the native leaf, e.g. `libc.so.6`) — a second
effect, not the cause.

JFR does not help either: `jdk.ThreadPark` is recorded for platform threads only (verified
on JDK 25), so a virtual thread parked in `Future.get()` leaves nothing in the ring. The tool
that **names** the block is a **JSON thread dump**: `jcmd Thread.dump_to_file -format=json`
lists virtual threads and their stacks whether mounted or not. Use **`perf-sensor.diagnoseBlocking`**
**while a load run is flowing** — it samples the thread dump over time and aggregates, so the
brief block is caught reliably on any image. It drives no traffic itself and returns BLOCKED
when no requests are flowing. The **CPU**
profile answers a different question (where cycles burn — startup/JIT/GC), and the **HTTP
latency metric** is the authoritative "it is slow" signal on every image.

## Reading the result

`perf-sensor.diagnoseBlocking` (and `threadDump`) summarize the dump:

- `requestThreadsBlockedInFutureGet` — request-path threads parked in a blocking
  `Future.get()/join()`. **> 0 under load is the defect.** From `diagnoseBlocking` this is
  the PEAK concurrent blocked across the samples it took while driving load.
- `topBlockingFrames` — the exact frame (`…CompletableFuture.get(...)`) and how many
  threads sat on it (summed across samples); trace it to the `file:line` in `src/`.
- `carriersParkedInPoolWait` — threads waiting on a connection pool; a sign the pool
  is undersized rather than the code blocking.
- `requestRatePerSec` (from `diagnoseBlocking`) — the load that was flowing while it sampled.

## Key benefits of fixing it

- Latency under load drops sharply — threads serve requests instead of waiting.
- Throughput rises without adding CPU; fewer threads are tied up.

## Trade-offs / how to fix

- Prefer **not waiting**: fire the async publish and return; handle failures on the
  async result, not on the request thread.
- If a result is genuinely needed, bound it (timeout) and **size the pool from
  evidence** — set the pool to the measured concurrency, not a guess.
- Virtual threads make blocking cheaper but do not make a needless block correct;
  remove the block first.

## Same procedure on every image

Diagnose the block the same way whatever image is deployed (plain, AOT, or CRaC): start the
load run, then call `perf-sensor.diagnoseBlocking <service>`. Because it reads the thread
dump — not the wall flame graph — it works identically on CRaC. There is no need to change
the deployed image to diagnose: the block is a property of the code, and the thread dump
names it on the CRaC-restored JVM just as on a plain one.

## Verify the fix

The **HTTP request-latency metric** is the authoritative before/after on every image
including CRaC: `http_server_requests_seconds` (avg `sum(rate(_sum))/sum(rate(_count))`,
or `_max`), filtered by the write method/URI. A blocking publish adds the downstream
round-trip to every write; removing it drops that latency sharply. Confirm the code change
with `diagnoseBlocking` again under the same load — `requestThreadsBlockedInFutureGet`
should fall to 0.

## Artifact

There is no golden file here — the change is in the app's source. Name the blocking
frame and `file:line` from `threadDump`, propose the non-blocking rewrite, and give a
pool size derived from the dump.
