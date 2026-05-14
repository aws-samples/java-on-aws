package com.example.perf.collector;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Dispatches /dump work to a virtual thread, returns 202 immediately to
 * the caller. Worker:
 *   1. Validates target is ours (via TargetResolver).
 *   2. Validates workload is opted in (perf-profile/service).
 *   3. Runs jcmd JFR.dump or Thread.print (via AsyncProfilerAttach).
 *   4. Uploads to the requested s3Uri directly through S3Client.
 *
 * Errors are caught per-job; a short failure marker is uploaded to the
 * s3Uri so the analyzer's HeadObject poll returns 200 instead of hanging.
 */
@Service
public class CollectorService {

    public enum Result { ACCEPTED, NOT_MY_TARGET, NOT_OPTED_IN, BAD_REQUEST }

    private static final Logger logger = LoggerFactory.getLogger(CollectorService.class);

    private final TargetResolver resolver;
    private final Profiler profiler;
    private final S3Client s3;

    private final ExecutorService workers = Executors.newVirtualThreadPerTaskExecutor();

    public CollectorService(TargetResolver resolver, Profiler profiler, S3Client s3) {
        this.resolver = resolver;
        this.profiler = profiler;
        this.s3 = s3;
    }

    public Result submit(CollectorController.DumpRequest req) {
        if (req.target() == null || req.target().id() == null || req.target().id().isBlank()) {
            return Result.BAD_REQUEST;
        }
        var targetId = req.target().id();
        if (!resolver.handles(targetId)) {
            logger.info("Not my target: {}", targetId);
            return Result.NOT_MY_TARGET;
        }
        if (resolver.serviceNameFor(targetId) == null) return Result.NOT_OPTED_IN;
        var pid = resolver.pidFor(targetId);
        if (pid < 0) return Result.NOT_OPTED_IN;
        workers.submit(() -> run(req, pid));
        return Result.ACCEPTED;
    }

    private void run(CollectorController.DumpRequest req, long pid) {
        var s3Uri = URI.create(req.s3Uri());
        try {
            switch (req.kind()) {
                case JFR -> {
                    var jfr = profiler.jfrDump(pid, req.jobId());
                    var bytes = Files.readAllBytes(jfr);
                    put(s3Uri, bytes, "application/octet-stream");
                    try { Files.deleteIfExists(jfr); } catch (Exception _) {}
                    logger.info("Uploaded JFR jobId={} to {}", req.jobId(), s3Uri);
                }
                case THREAD_DUMP -> {
                    var out = profiler.threadPrint(pid);
                    put(s3Uri, out.getBytes(StandardCharsets.UTF_8), "text/plain");
                    logger.info("Uploaded thread dump jobId={} to {}", req.jobId(), s3Uri);
                }
            }
        } catch (Exception e) {
            logger.error("Dump failed jobId={} pid={}: {}", req.jobId(), pid, e.getMessage());
            try {
                put(s3Uri, ("Dump failed: " + e.getMessage()).getBytes(StandardCharsets.UTF_8), "text/plain");
            } catch (Exception se) {
                logger.error("Also failed to upload failure marker: {}", se.getMessage());
            }
        }
    }

    private void put(URI s3Uri, byte[] bytes, String contentType) {
        var bucket = s3Uri.getHost();
        var key = s3Uri.getPath().startsWith("/") ? s3Uri.getPath().substring(1) : s3Uri.getPath();
        s3.putObject(
            PutObjectRequest.builder().bucket(bucket).key(key).contentType(contentType).build(),
            RequestBody.fromBytes(bytes));
    }
}
