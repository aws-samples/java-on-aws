# Blocking calls on the request path

## Introduction

A request thread that blocks on a synchronous `Future.get()` / `join()` — waiting
for an async client (event publish, downstream call) to finish — holds the thread
idle while latency climbs under load. The fix is to not block the request path:
return without waiting, or bound and size the work deliberately.

## The wall-vs-CPU lens

- A **CPU** profile shows where cycles burn. A **wall** profile shows where time
  passes, including *off-CPU* waiting (parked threads, lock/futex waits).
- High latency with low CPU is the signature of blocking: `perf-sensor.profileTop
  wall` shows a large `futexWallShare` (time parked in `Unsafe.park` / futex), while
  the CPU profile looks idle. That gap is the tell.

## Reading ThreadFacts

`perf-sensor.threadDump` summarizes the live dump:

- `requestThreadsBlockedInFutureGet` — request-path threads parked in a blocking
  `Future.get()/join()`. **> 0 under load is the defect.**
- `topBlockingFrames` — the exact frame (`…CompletableFuture.get(...)`) and how many
  threads sit on it; trace it to the `file:line` in `src/`.
- `carriersParkedInPoolWait` — threads waiting on a connection pool; a sign the pool
  is undersized rather than the code blocking.

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

## Diagnose on the plain-JVM image, not on CRaC

`profileTop wall` and `threadDump` resolve Java frames on a normal JVM (Corretto/plain
or AOT), so that is where you diagnose latency — before switching the workload to CRaC.
On a **CRaC-restored (Azul Zulu) JVM** the wall profiler cannot unwind the Java stack:
frames collapse to the native leaf (e.g. `libc.so.6`), so `futexWallShare` reads ~0 and
gives no `Unsafe.park`/futex signal — and `threadDump` may be empty depending on the
image. A `futexWallShare` of 0 on a CRaC pod means "not measurable here", **not** "no
blocking". Do the latency diagnosis on the plain JVM; the blocking call is a property of
the code, so the finding carries over to the CRaC build unchanged.

## Verify

Prefer the **HTTP request-latency metric** as the authoritative before/after — it works
on every image including CRaC: `http_server_requests_seconds` (avg
`sum(rate(_sum))/sum(rate(_count))`, or `_max`), filtered by the write method/URI. A
blocking publish adds the downstream round-trip to every write; removing it drops that
latency sharply.

On a plain/AOT JVM you can also confirm with the profiler: `profileTop wall`
(`futexWallShare` falls) and `threadDump` (`requestThreadsBlockedInFutureGet` → 0) under
the same load. On CRaC, rely on the HTTP-latency metric instead.

## Artifact

There is no golden file here — the change is in the app's source. Name the blocking
frame and `file:line` from `threadDump`, propose the non-blocking rewrite, and give a
pool size derived from the dump.
