package com.example.perf.collector;

import com.example.perf.collector.CollectorProperties.TargetJvm;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

/**
 * All the jattach-based work lives here:
 *
 *   attachIfNeeded(jvm) → copy libasyncProfiler.so into /proc/&lt;pid&gt;/root/tmp/
 *                        + jattach load with server=&lt;pyroscope-url&gt; once per JVM.
 *   jfrDump(pid, job)   → jattach &lt;pid&gt; jcmd "JFR.dump name=perf ..."
 *   threadPrint(pid)    → jattach &lt;pid&gt; jcmd "Thread.print -e" → stdout
 *
 * async-profiler self-pushes to Pyroscope every ~10 seconds via its native
 * server= flag. The session persists for the JVM's lifetime.
 */
@Component
public class AsyncProfilerAttach {

    private static final Logger logger = LoggerFactory.getLogger(AsyncProfilerAttach.class);

    private final CollectorProperties props;
    private final Set<Long> attachedPids = ConcurrentHashMap.newKeySet();

    public AsyncProfilerAttach(CollectorProperties props) {
        this.props = props;
    }

    public void attachIfNeeded(TargetJvm jvm) {
        if (attachedPids.contains(jvm.pid())) return;
        try {
            loadAsyncProfiler(jvm.pid(), buildProfilerArgs(jvm));
            attachedPids.add(jvm.pid());
            logger.info("Attached async-profiler to pid {} service={} version={} target={}",
                jvm.pid(), jvm.serviceName(), jvm.version(), jvm.idLabel());
        } catch (Exception e) {
            logger.warn("Failed attaching async-profiler to pid {}: {}", jvm.pid(), e.getMessage());
        }
    }

    /** Load async-profiler into the target JVM with the given args. Idempotent-ish —
     *  if already loaded, jattach returns an error which we surface as an exception. */
    public void loadAsyncProfiler(long pid, String profilerArgs)
            throws IOException, InterruptedException {
        var targetTmp = Path.of("/proc", Long.toString(pid), "root", "tmp");
        Files.createDirectories(targetTmp);
        var libDest = targetTmp.resolve("libasyncProfiler.so");
        if (!Files.exists(libDest)) {
            Files.copy(Path.of(props.asyncProfilerLib()), libDest);
            logger.info("Copied libasyncProfiler.so to pid {} at {}", pid, libDest);
        }
        runJattach(pid, List.of(
            props.jattachBinary(), Long.toString(pid),
            "load", "/tmp/libasyncProfiler.so", "true", profilerArgs));
    }

    /** Invoke `jcmd JFR.dump` and return the path to the dump file in the target's /tmp. */
    public Path jfrDump(long pid, String jobId) throws IOException, InterruptedException {
        var fileName = "perf-" + jobId + ".jfr";
        runJattach(pid, List.of(
            props.jattachBinary(), Long.toString(pid),
            "jcmd", "JFR.dump name=perf filename=/tmp/" + fileName));
        return Path.of("/proc", Long.toString(pid), "root", "tmp", fileName);
    }

    /** Invoke `jcmd Thread.print -e`; jattach writes the result to stdout. */
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

    private String buildProfilerArgs(TargetJvm jvm) {
        var tags = "version=%s;pod=%s;platform=%s".formatted(
            nz(jvm.version()), nz(jvm.idLabel()),
            jvm.platform().name().toLowerCase().replace('_', '-'));
        return "start,event=wall,server=%s,service=%s,tags=%s".formatted(
            props.pyroscopeUrl(), jvm.serviceName(), tags);
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

    private static String nz(String s) { return s == null || s.isBlank() ? "unknown" : s; }
}
