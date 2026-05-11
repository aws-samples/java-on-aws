package com.example.perf.collector;

import com.example.perf.collector.CollectorProperties.TargetJvm;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpRequest.BodyPublishers;
import java.net.http.HttpResponse;
import java.net.http.HttpResponse.BodyHandlers;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Attaches async-profiler to discovered JVMs and drives the push-to-Pyroscope
 * loop for continuous profiling.
 *
 * Why we push from the collector instead of letting async-profiler push itself:
 *   async-profiler 4.x repurposed {@code server=<url>} to start a *local HTTP
 *   management server* on the target JVM. It no longer pushes profiles to a
 *   remote endpoint. The collector picks up this responsibility: every 15 seconds
 *   it dumps collapsed stacks via jattach and POSTs them to Pyroscope {@code /ingest}.
 *
 * Flow per discovered JVM:
 *   1. attachIfNeeded(jvm) — copy libasyncProfiler.so into the target's /tmp
 *      (through /proc/&lt;pid&gt;/root/tmp, requires privileged on EKS),
 *      then start continuous wall-clock profiling via asprof.
 *   2. startJfr(pid) — also start a rolling in-memory JFR recording for on-demand
 *      deep dumps.
 *   3. Push loop — every 15 seconds, jattach dump,collapsed,wall → read file
 *      from target rootfs → HTTP POST to Pyroscope.
 *
 * On-demand: jfrDump(pid, jobId) and threadPrint(pid) are invoked by DumpService
 * when the analyzer asks for deep data via POST /dump.
 */
@Component
public class AsyncProfilerAttach {

    private static final Logger logger = LoggerFactory.getLogger(AsyncProfilerAttach.class);

    /**
     * Always-on JFR command applied at attach time. Same shape as what
     * {@code -XX:StartFlightRecording} would produce at JVM launch.
     */
    private static final String JFR_START_ARGS =
        "JFR.start name=perf settings=default maxage=10m maxsize=50m disk=false";

    /** Cadence of the collapsed-stacks push to Pyroscope. */
    private static final Duration PUSH_INTERVAL = Duration.ofSeconds(15);

    private final CollectorProperties props;
    private final Map<Long, TargetJvm> trackedJvms = new ConcurrentHashMap<>();
    private final ScheduledExecutorService pushExecutor =
        Executors.newSingleThreadScheduledExecutor(r -> {
            var t = new Thread(r, "pyroscope-push");
            t.setDaemon(true);
            return t;
        });
    private final HttpClient http = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .build();

    public AsyncProfilerAttach(CollectorProperties props) {
        this.props = props;
        installLibToHost();
        pushExecutor.scheduleAtFixedRate(this::pushAll,
            PUSH_INTERVAL.toMillis(), PUSH_INTERVAL.toMillis(), TimeUnit.MILLISECONDS);
    }

    /**
     * Copy libasyncProfiler.so from the image into the node-level
     * {@code hostPath} mount so every attach can reuse it without
     * re-pulling from the image layer.
     */
    private void installLibToHost() {
        try {
            var dest = Path.of(props.hostLibPath());
            Files.createDirectories(dest.getParent());
            Files.copy(Path.of(props.asyncProfilerLib()), dest,
                StandardCopyOption.REPLACE_EXISTING);
            dest.toFile().setExecutable(true, false);
            dest.toFile().setReadable(true, false);
            logger.info("Installed libasyncProfiler.so to host path {}", dest);
        } catch (Exception e) {
            logger.error("Failed to install libasyncProfiler.so to host path: {}", e.getMessage());
        }
    }

    /** Attach async-profiler + JFR to a newly-discovered JVM (once per PID). */
    public void attachIfNeeded(TargetJvm jvm) {
        if (trackedJvms.containsKey(jvm.pid())) return;
        try {
            copyLibIntoTargetTmp(jvm.pid());
            startAsprof(jvm.pid());
            startJfr(jvm.pid());
            trackedJvms.put(jvm.pid(), jvm);
            logger.info("Attached async-profiler + JFR to pid {} service={} version={} target={}",
                jvm.pid(), jvm.serviceName(), jvm.version(), jvm.idLabel());
        } catch (Exception e) {
            logger.warn("Failed attaching to pid {}: {}", jvm.pid(), e.getMessage());
        }
    }

    /** Copy libasyncProfiler.so from the node's hostPath into the target container's /tmp. */
    private void copyLibIntoTargetTmp(long pid) throws IOException {
        var targetTmp = Path.of("/proc", Long.toString(pid), "root", "tmp");
        var libDest = targetTmp.resolve("libasyncProfiler.so");
        if (!Files.exists(libDest)) {
            Files.copy(Path.of(props.hostLibPath()), libDest);
            logger.info("Copied libasyncProfiler.so to pid {} at {}", pid, libDest);
        }
    }

    /**
     * Start continuous wall-clock sampling. The library path is
     * the target JVM's /tmp (not the collector's) because the agent
     * runs inside the target JVM's mount namespace.
     */
    private void startAsprof(long pid) throws IOException, InterruptedException {
        run(props.asprofBinary(),
            "start", "-e", "wall", "-i", "10ms",
            "--libpath", "/tmp/libasyncProfiler.so",
            Long.toString(pid));
    }

    /**
     * Start a rolling in-memory JFR recording. Idempotent — if a recording
     * named {@code perf} already exists (e.g. collector restarted while the
     * JVM kept running), JFR returns an "already in use" error that we treat
     * as a no-op.
     */
    public void startJfr(long pid) throws IOException, InterruptedException {
        try {
            runJattach(pid, List.of(
                props.jattachBinary(), Long.toString(pid),
                "jcmd", JFR_START_ARGS));
            logger.info("Started JFR recording 'perf' on pid {}", pid);
        } catch (IOException e) {
            var msg = e.getMessage() == null ? "" : e.getMessage();
            if (msg.contains("already in use") || msg.contains("already started")
                || msg.contains("Name 'perf'")) {
                logger.info("JFR recording 'perf' already running on pid {} — skipping", pid);
                return;
            }
            throw e;
        }
    }

    /** Periodic dump-and-push loop. */
    private void pushAll() {
        for (var entry : trackedJvms.entrySet()) {
            var pid = entry.getKey();
            var jvm = entry.getValue();
            try {
                pushJfr(pid, jvm);
            } catch (Exception e) {
                logger.warn("Push failed for pid {} ({}): {}",
                    pid, jvm.serviceName(), e.getMessage());
                // If the process is gone, stop tracking it.
                if (!Files.exists(Path.of("/proc", Long.toString(pid)))) {
                    detach(pid);
                }
            }
        }
    }

    private void pushJfr(long pid, TargetJvm jvm) throws IOException, InterruptedException {
        var fileInTarget = "/tmp/perf-dump-" + pid + ".collapsed";
        runJattach(pid, List.of(
            props.jattachBinary(), Long.toString(pid),
            "load", "/tmp/libasyncProfiler.so", "true",
            "dump,collapsed,wall,file=" + fileInTarget));

        var src = Path.of("/proc", Long.toString(pid), "root", "tmp",
            "perf-dump-" + pid + ".collapsed");
        if (!Files.exists(src) || Files.size(src) == 0) {
            logger.debug("No collapsed stacks yet for pid {}", pid);
            return;
        }
        var bytes = Files.readAllBytes(src);
        Files.deleteIfExists(src);

        // Pyroscope /ingest: format=collapsed + spyName=javaspy is the canonical
        // format used by Pyroscope agent clients. Labels are attached as URL-encoded
        // "k=v,k=v" in the `labels` query param.
        var labels = "version=" + urlEnc(nz(jvm.version()))
            + ",pod=" + urlEnc(nz(jvm.idLabel()))
            + ",platform=" + urlEnc(jvm.platform().name().toLowerCase().replace('_', '-'));
        var url = "%s/ingest?name=%s&format=collapsed&spyName=javaspy&sampleRate=100&labels=%s"
            .formatted(
                props.pyroscopeUrl().replaceAll("/$", ""),
                urlEnc(jvm.serviceName()),
                labels);

        var req = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofSeconds(10))
            .header("Content-Type", "text/plain")
            .POST(BodyPublishers.ofByteArray(bytes))
            .build();
        var resp = http.send(req, BodyHandlers.ofString());
        if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
            logger.info("Pushed {} bytes for pid {} service={}", bytes.length, pid, jvm.serviceName());
        } else {
            throw new IOException("Pyroscope /ingest returned "
                + resp.statusCode() + ": " + resp.body());
        }
    }

    /** Stop tracking a PID. async-profiler/JFR die with the JVM. */
    private void detach(long pid) {
        trackedJvms.remove(pid);
        logger.info("Stopped tracking pid {}", pid);
    }

    /** Dump the current in-memory JFR ring to a file in the target JVM's /tmp. */
    public Path jfrDump(long pid, String jobId) throws IOException, InterruptedException {
        var fileName = "perf-" + jobId + ".jfr";
        runJattach(pid, List.of(
            props.jattachBinary(), Long.toString(pid),
            "jcmd", "JFR.dump name=perf filename=/tmp/" + fileName));
        return Path.of("/proc", Long.toString(pid), "root", "tmp", fileName);
    }

    /** jcmd Thread.print -e; jattach writes stack output to stdout. */
    public String threadPrint(long pid) throws IOException, InterruptedException {
        var proc = new ProcessBuilder(
            props.jattachBinary(), Long.toString(pid), "jcmd", "Thread.print -e")
            .redirectErrorStream(true)
            .start();
        var out = new String(proc.getInputStream().readAllBytes());
        boolean ok = proc.waitFor(30, TimeUnit.SECONDS);
        if (!ok) {
            proc.destroyForcibly();
            throw new IOException("jattach Thread.print timed out for pid " + pid);
        }
        if (proc.exitValue() != 0) {
            throw new IOException(
                "jattach Thread.print exit=%d output=%s".formatted(proc.exitValue(), out));
        }
        return out;
    }

    private void runJattach(long pid, List<String> command)
            throws IOException, InterruptedException {
        var proc = new ProcessBuilder(command).redirectErrorStream(true).start();
        var stdout = new String(proc.getInputStream().readAllBytes());
        var ok = proc.waitFor(30, TimeUnit.SECONDS);
        if (!ok) {
            proc.destroyForcibly();
            throw new IOException("jattach timed out for pid " + pid + ": " + command);
        }
        if (proc.exitValue() != 0) {
            throw new IOException("jattach exit=%d pid=%d cmd=%s output=%s"
                .formatted(proc.exitValue(), pid, command, stdout));
        }
        logger.debug("jattach pid={} cmd={} ok ({} bytes)", pid, command, stdout.length());
    }

    /** Run a generic external command (used for asprof). */
    private void run(String... command) throws IOException, InterruptedException {
        var proc = new ProcessBuilder(command).redirectErrorStream(true).start();
        var stdout = new String(proc.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        var ok = proc.waitFor(30, TimeUnit.SECONDS);
        if (!ok) {
            proc.destroyForcibly();
            throw new IOException("command timed out: " + List.of(command));
        }
        if (proc.exitValue() != 0) {
            throw new IOException("command exit=%d cmd=%s output=%s"
                .formatted(proc.exitValue(), List.of(command), stdout));
        }
    }

    private static String urlEnc(String s) {
        return java.net.URLEncoder.encode(s == null ? "" : s, StandardCharsets.UTF_8);
    }

    private static String nz(String s) {
        return s == null || s.isBlank() ? "unknown" : s;
    }
}
