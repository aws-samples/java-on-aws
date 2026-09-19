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

## Artifact

There is no golden file here — the change is in the app's source. Name the blocking
frame and `file:line` from `threadDump`, propose the non-blocking rewrite, and give a
pool size derived from the dump. Verify with `profileTop wall` (futexWallShare falls)
and `threadDump` (`requestThreadsBlockedInFutureGet` → 0) under the same load.
