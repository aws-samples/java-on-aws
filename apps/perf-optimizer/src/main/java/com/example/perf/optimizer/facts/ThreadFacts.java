package com.example.perf.optimizer.facts;

import java.util.Map;

/**
 * Thread-dump-derived facts from the sidecar {@code /dump?kind=threads}
 * ({@code jcmd Thread.print}). Used by the blocking-call finding to confirm that
 * a high wall/futex share is a request-path blocking call (not benign idle).
 *
 * @param threadCountByState    thread count per state (e.g. RUNNABLE, WAITING, TIMED_WAITING)
 * @param poolWaitCarriers      carrier/request threads parked in connection-pool waits
 * @param futureGetOnRequestPath true if a blocking {@code Future.get()/join()} frame is on a request thread
 */
public record ThreadFacts(
    Map<String, Integer> threadCountByState,
    Integer poolWaitCarriers,
    Boolean futureGetOnRequestPath
) {}
