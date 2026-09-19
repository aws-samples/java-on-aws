package com.example.perf.sensor.facts;

import java.util.List;
import java.util.Map;

/**
 * Thread-dump-derived facts from the sidecar {@code /dump?kind=threads}
 * ({@code jcmd Thread.dump_to_file -format=json}), summarized — never the raw
 * dump. A "request-path" thread is one whose stack runs the app's request
 * package or a Tomcat http-nio worker. No MCP server can reach an in-pod endpoint,
 * so the sensor is the only source.
 *
 * @param pod                              pod the dump was taken from
 * @param timestamp                        ISO-8601 instant the dump was taken
 * @param total                            total threads in the dump
 * @param byState                          thread count per {@code Thread.State}
 * @param virtualThreads                   count of virtual threads
 * @param requestThreadsBlockedInFutureGet request-path threads parked in a blocking Future.get()/join()
 * @param carriersParkedInPoolWait         carrier/request threads parked in a connection-pool wait
 * @param topBlockingFrames                most common frames on blocked request-path threads
 * @param sample                           a small sample of request-path threads (name, state, top frames)
 */
public record ThreadFacts(
    String pod,
    String timestamp,
    int total,
    Map<String, Integer> byState,
    int virtualThreads,
    int requestThreadsBlockedInFutureGet,
    int carriersParkedInPoolWait,
    List<FrameCount> topBlockingFrames,
    List<ThreadSample> sample
) {
    /** A frame and how many blocked request-path threads showed it. */
    public record FrameCount(String frame, int count) {}

    /** One sampled thread: its name, state, and the top of its stack. */
    public record ThreadSample(String name, String state, List<String> stack) {}
}
