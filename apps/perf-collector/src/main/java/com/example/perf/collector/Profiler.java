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
import java.net.http.HttpResponse.BodyHandlers;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

/**
 * Attaches async-profiler to discovered JVMs and ships the resulting JFR
 * recordings to Pyroscope.
 *
 * Why CPU + wall together:
 *   The two profile types answer different questions. CPU shows what is
 *   actually computing on a core (wrong tool for blocking I/O — a thread
 *   stuck in {@code Future.get} is off-CPU and disappears). Wall shows where
 *   every sampled thread spends time regardless of state (right tool for
 *   blocking I/O, locks, downstream calls). async-profiler's dual-mode
 *   {@code -e cpu --wall 10ms} samples both events from a single attach,
 *   and Pyroscope's JFR ingester splits the resulting file into the
 *   {@code process_cpu} and {@code wall} profile types automatically.
 *   One attach, one writer, one push per cycle, two lenses.
 *
 * Why JFR (and not collapsed stacks):
 *   Collapsed-stack output only carries one event per dump. JFR carries
 *   both events with typed metadata in a single file and is what
 *   Pyroscope's {@code /ingest?format=jfr} endpoint expects.
 *
 * Why the collector pushes instead of async-profiler pushing itself:
 *   async-profiler 4.x repurposed {@code server=&lt;url&gt;} to start a *local
 *   HTTP management server* on the target JVM. It no longer pushes profiles to
 *   a remote endpoint. async-profiler does, however, rotate JFR output files
 *   on a schedule via {@code --loop}, and each rotated file is properly
 *   finalized (metadata chunk included) and acceptable by Pyroscope. The
 *   collector watches for rotated files in the target container's {@code /tmp}
 *   via {@code /proc/&lt;pid&gt;/root/tmp/} and POSTs each completed file.
 *
 * Flow per discovered JVM:
 *   1. attachIfNeeded(jvm) — copy libasyncProfiler.so into the target's /tmp,
 *      then start CPU+wall profiling writing to {@code /tmp/perf-&lt;pid&gt;-%t.jfr}
 *      with {@code --loop 15s} so async-profiler rotates the file every 15 s.
 *   2. Push loop — every few seconds, scan the target's /tmp for completed
 *      (non-newest) rotated files, POST each one to Pyroscope as a JFR
 *      binary, then delete.
 *
 * On-demand: jfrDump(pid, jobId) asks async-profiler for a snapshot of the
 * *same running session* (using {@code asprof dump -o jfr -f ...}), which
 * produces a proper JFR file without interrupting continuous profiling.
 * threadPrint(pid) is unchanged — still uses {@code jattach jcmd Thread.print}.
 */
@Component
public class Profiler {

    private static final Logger logger = LoggerFactory.getLogger(Profiler.class);

    /** How often async-profiler rotates its output JFR file. */
    private static final Duration LOOP_INTERVAL = Duration.ofSeconds(15);

    /** How often the push thread looks for new completed JFR files. */
    private static final Duration SCAN_INTERVAL = Duration.ofSeconds(5);

    /** Prefix of rotated JFR files written by async-profiler's --loop. */
    private static String rotatedFilePrefix(long pid) {
        return "perf-" + pid + "-";
    }

    /** Suffix of rotated files (matches the %t expansion of --loop). */
    private static final String ROTATED_FILE_SUFFIX = ".jfr";

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

    public Profiler(CollectorProperties props) {
        this.props = props;
        installLibToHost();
        pushExecutor.scheduleAtFixedRate(this::pushAll,
            SCAN_INTERVAL.toMillis(), SCAN_INTERVAL.toMillis(), TimeUnit.MILLISECONDS);
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

    /** Attach async-profiler (CPU+wall, rotating JFR) to a newly-discovered JVM. */
    public void attachIfNeeded(TargetJvm jvm) {
        if (trackedJvms.containsKey(jvm.pid())) return;
        try {
            copyLibIntoTargetTmp(jvm.pid());
            startAsprof(jvm.pid());
            trackedJvms.put(jvm.pid(), jvm);
            logger.info("Attached async-profiler (cpu+wall, JFR/15s) to pid {} service={} version={} target={}",
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
     * Start CPU+wall sampling writing JFR with file rotation.
     *
     * async-profiler requirements we're relying on:
     *   - {@code -e cpu --wall 10ms} samples both events simultaneously
     *     (async-profiler's native multi-event mode). This is not allowed
     *     for collapsed output, only JFR.
     *   - {@code -o jfr -f /tmp/perf-&lt;pid&gt;-%t.jfr --loop 15s} rotates the output
     *     file every 15 seconds. Each rotation finalizes the previous file with a
     *     proper metadata chunk — critical for Pyroscope's JFR parser.
     *   - A stray previous-collector session gets cleared via {@code asprof stop}
     *     first so {@code start} doesn't fail with "Profiler already started".
     *
     * The same async-profiler session also serves on-demand JFR dumps via
     * {@link #jfrDump(long, String)} — no separate {@code jcmd JFR.start} is
     * needed.
     */
    private void startAsprof(long pid) throws IOException, InterruptedException {
        try {
            run(props.asprofBinary(),
                "stop",
                "--libpath", "/tmp/libasyncProfiler.so",
                Long.toString(pid));
        } catch (IOException e) {
            // No previous session — normal case.
            logger.debug("asprof stop (pre-start) returned: {}", e.getMessage());
        }
        var outFilePattern = "/tmp/" + rotatedFilePrefix(pid) + "%t" + ROTATED_FILE_SUFFIX;
        run(props.asprofBinary(),
            "start",
            "-e", "cpu",
            "--wall", "10ms",
            "-i", "10ms",
            "-o", "jfr",
            "-f", outFilePattern,
            "--loop", LOOP_INTERVAL.toSeconds() + "s",
            "--libpath", "/tmp/libasyncProfiler.so",
            Long.toString(pid));
    }

    /** Scan every tracked JVM's target-tmp for completed JFR files and push each one. */
    private void pushAll() {
        for (var entry : trackedJvms.entrySet()) {
            var pid = entry.getKey();
            var jvm = entry.getValue();
            if (!Files.exists(Path.of("/proc", Long.toString(pid)))) {
                detach(pid);
                continue;
            }
            try {
                pushRotatedFiles(pid, jvm);
            } catch (Exception e) {
                logger.warn("Push failed for pid {} ({}): {}",
                    pid, jvm.serviceName(), e.getMessage());
            }
        }
    }

    /**
     * Find rotated JFR files in the target JVM's /tmp, skip the newest (still
     * being written by async-profiler), POST each finalized file to Pyroscope,
     * then delete it.
     */
    private void pushRotatedFiles(long pid, TargetJvm jvm) throws IOException, InterruptedException {
        var targetTmp = Path.of("/proc", Long.toString(pid), "root", "tmp");
        if (!Files.isDirectory(targetTmp)) return;

        var prefix = rotatedFilePrefix(pid);
        List<Path> rotated;
        try (Stream<Path> entries = Files.list(targetTmp)) {
            rotated = entries
                .filter(p -> {
                    var name = p.getFileName().toString();
                    return name.startsWith(prefix) && name.endsWith(ROTATED_FILE_SUFFIX);
                })
                .sorted(Comparator.comparing(p -> p.getFileName().toString()))
                .collect(java.util.stream.Collectors.toCollection(ArrayList::new));
        }
        if (rotated.size() < 2) {
            // Only the in-flight file exists; nothing to push yet.
            return;
        }
        // The last entry (alphabetically == chronologically for %t timestamps) is
        // the file currently being written. Leave it alone.
        var completed = rotated.subList(0, rotated.size() - 1);
        for (var file : completed) {
            try {
                pushFile(file, pid, jvm);
            } catch (Exception e) {
                logger.warn("Push of {} failed: {}", file, e.getMessage());
            } finally {
                try { Files.deleteIfExists(file); } catch (Exception _) {}
            }
        }
    }

    private void pushFile(Path file, long pid, TargetJvm jvm) throws IOException, InterruptedException {
        long size;
        try { size = Files.size(file); }
        catch (IOException e) { return; }
        if (size <= 0) return;

        var bytes = Files.readAllBytes(file);

        // Pyroscope /ingest: format=jfr + spyName=javaspy is the canonical
        // format for async-profiler's JFR output. Labels live inside curly
        // braces immediately after the application name in the `name` query
        // param: name=my-service-eks{version=1,pod=abc,...}.
        // Service name is suffixed with the platform (-eks or -ecs) so each
        // runtime gets its own entry in Grafana Profiles Drilldown. The
        // underlying workload (what the user set with perf-profile/service) is
        // published as a `workload` label for cross-platform pivoting.
        var platformTag = jvm.platform().name().toLowerCase().replace('_', '-');
        var platformSuffix = jvm.platform() == CollectorProperties.Platform.ECS_FARGATE
            ? "ecs"
            : "eks";
        var pyroscopeServiceName = jvm.serviceName() + "-" + platformSuffix;
        var nameWithLabels = pyroscopeServiceName + "{"
            + "version=" + nz(jvm.version())
            + ",pod=" + nz(jvm.idLabel())
            + ",platform=" + platformTag
            + ",workload=" + jvm.serviceName()
            + "}";
        var url = "%s/ingest?name=%s&format=jfr&spyName=javaspy"
            .formatted(
                props.pyroscopeUrl().replaceAll("/$", ""),
                urlEnc(nameWithLabels));

        var req = HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofSeconds(30))
            .header("Content-Type", "application/octet-stream")
            .POST(BodyPublishers.ofByteArray(bytes))
            .build();
        var resp = http.send(req, BodyHandlers.ofString());
        if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
            logger.info("Pushed {} bytes for pid {} service={} file={}",
                bytes.length, pid, pyroscopeServiceName, file.getFileName());
        } else {
            throw new IOException("Pyroscope /ingest returned "
                + resp.statusCode() + ": " + resp.body());
        }
    }

    /** Stop tracking a PID. async-profiler dies with the JVM. */
    private void detach(long pid) {
        trackedJvms.remove(pid);
        logger.info("Stopped tracking pid {}", pid);
    }

    /**
     * On-demand: ask async-profiler to dump the live session to a new JFR file.
     * The running session is not disturbed — dump only flushes current state.
     * Pyroscope's parser requires proper metadata, which async-profiler's dump
     * produces inside its own rotating file, so we dump to a dedicated path
     * and immediately return it.
     */
    public Path jfrDump(long pid, String jobId) throws IOException, InterruptedException {
        var fileInTarget = "/tmp/perf-ondemand-" + jobId + ".jfr";
        run(props.asprofBinary(),
            "dump",
            "-o", "jfr",
            "-f", fileInTarget,
            "--libpath", "/tmp/libasyncProfiler.so",
            Long.toString(pid));
        return Path.of("/proc", Long.toString(pid), "root", "tmp",
            "perf-ondemand-" + jobId + ".jfr");
    }

    /** jcmd Thread.print -e; jattach writes stack output to stdout. Unchanged. */
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

    /** Run a generic external command (asprof etc.). */
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
