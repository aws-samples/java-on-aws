// perf-profiler /dump endpoint — a tiny single-file HTTP server (run in JDK 25 source mode:
// `java DumpServer.java [port]`). It exposes on-demand JVM diagnostics for the APP process
// across the shared PID namespace via `jcmd`, so perf-sensor can build thread/heap/JFR facts
// without a collector or `kubectl exec`.
//
//   GET /dump?kind=threads  -> jcmd <pid> Thread.dump_to_file -format=json  (virtual threads
//                              included) -> the JSON file; 503 if jcmd failed or wrote no file
//   GET /dump?kind=heap     -> jcmd <pid> GC.heap_info + VM.flags (text); 503 if jcmd failed
//   GET /dump?kind=jfr      -> jcmd <pid> JFR.dump name=perf (the 10-min ring started by
//                              profile-loop.sh) -> the .jfr file bytes (application/octet-stream)
//   GET /healthz            -> ok
//
// Runs in the sidecar (same UID as the app + SYS_PTRACE + shareProcessNamespace), so jcmd can
// attach to the app JVM. JAVA_TOOL_OPTIONS is nulled for each jcmd call — otherwise the app's
// flags (e.g. -Xlog:gc) contaminate jcmd's own output.
//
// Files the TARGET writes (thread dump JSON, on-demand JFR) go to PERF_DIR (/perf), the
// dedicated emptyDir the inject policy mounts in both containers — read here at the same
// path. Fallback when the volume is absent: the target's /tmp via /proc/<pid>/root. Every
// request writes its own file and deletes it after reading, and a non-zero jcmd exit is a
// 503: a failed dump never serves an earlier one. Requests run on a small pool, so a slow
// dump does not hold up /healthz or the next request; each jcmd has a 25 s deadline.
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Stream;

public class DumpServer {

    private static final long JCMD_TIMEOUT_SECONDS = 25;
    private static final AtomicLong REQUESTS = new AtomicLong();

    /** jcmd's exit code (-1: did not finish or did not start) and its combined output. */
    record Jcmd(int exit, String output) {
        boolean ok() {
            return exit == 0;
        }
    }

    public static void main(String[] args) throws IOException {
        int port = args.length > 0 ? Integer.parseInt(args[0]) : 9100;
        var server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/healthz", ex -> respond(ex, 200, "ok\n"));
        server.createContext("/dump", DumpServer::handleDump);
        // The default executor runs every handler on the dispatcher thread: one 25 s jcmd would
        // block /healthz and every other request behind it.
        server.setExecutor(Executors.newFixedThreadPool(4));
        System.out.println("[dump-server] listening on :" + port);
        server.start();
    }

    /** Directory the target writes to; the same path is mounted here when the scratch volume exists. */
    private static String perfDir() {
        String d = System.getenv("PERF_DIR");
        d = (d == null || d.isBlank()) ? "/perf" : d;
        return Files.isDirectory(Path.of(d)) ? d : "/tmp";
    }

    /** Where WE can read a file the target wrote at {@code targetPath}. */
    private static Path readable(long pid, String targetPath) {
        var direct = Path.of(targetPath);
        if (Files.isReadable(direct) && !targetPath.startsWith("/tmp")) {
            return direct;
        }
        return Path.of("/proc/" + pid + "/root" + targetPath);
    }

    private static void handleDump(HttpExchange ex) throws IOException {
        String kind = query(ex.getRequestURI().getRawQuery()).getOrDefault("kind", "threads");
        long pid = targetPid();
        if (pid < 0) {
            respond(ex, 503, "no target JVM found in the shared PID namespace\n");
            return;
        }
        String body;
        switch (kind) {
            case "threads" -> {
                body = threadDumpJson(pid);
                if (body == null) {
                    respond(ex, 503, "Thread.dump_to_file produced no JSON file (is the app JVM attachable?)\n");
                    return;
                }
            }
            case "heap" -> {
                var heap = jcmd(pid, "GC.heap_info");
                var flags = heap.ok() ? jcmd(pid, "VM.flags") : heap;
                if (!flags.ok()) {
                    respond(ex, 503, "jcmd failed (exit " + flags.exit() + "): " + flags.output());
                    return;
                }
                body = heap.output() + "\n" + flags.output();
            }
            case "jfr" -> {
                jfrDump(ex, pid);
                return;
            }
            default -> {
                respond(ex, 400, "unknown kind: " + kind + " (threads|heap|jfr)\n");
                return;
            }
        }
        ex.getResponseHeaders().add("Content-Type",
            "threads".equals(kind) ? "application/json; charset=utf-8" : "text/plain; charset=utf-8");
        respondRaw(ex, 200, body);
    }

    /**
     * Dump the JVM-native JFR ring (recording "perf", started by profile-loop.sh with
     * maxage=10m) into PERF_DIR, stream the file bytes back, then delete it. 503 with jcmd's
     * output when there is no such recording.
     */
    private static void jfrDump(HttpExchange ex, long pid) throws IOException {
        String path = uniquePath("perf-ondemand-" + pid, ".jfr");
        var out = jcmd(pid, "JFR.dump", "name=perf", "filename=" + path);
        var onSidecar = readable(pid, path);
        if (!out.ok() || !Files.isReadable(onSidecar)) {
            Files.deleteIfExists(onSidecar);
            respond(ex, 503, "JFR.dump failed (exit " + out.exit() + "): " + out.output());
            return;
        }
        try {
            byte[] bytes = Files.readAllBytes(onSidecar);
            ex.getResponseHeaders().add("Content-Type", "application/octet-stream");
            ex.sendResponseHeaders(200, bytes.length);
            try (var os = ex.getResponseBody()) {
                os.write(bytes);
            }
        } finally {
            try {
                Files.deleteIfExists(onSidecar);
            } catch (IOException ignored) {
                // best-effort cleanup in the target's /tmp
            }
        }
    }

    /** The app JVM: TARGET_PID if set, else PID 1 when it is a JVM, else the lowest JVM pid that is not us. */
    private static long targetPid() {
        String override = System.getenv("TARGET_PID");
        if (override != null && !override.isBlank()) {
            return Long.parseLong(override.trim());
        }
        long self = ProcessHandle.current().pid();
        if (isJava(1) && 1 != self) {
            return 1;
        }
        try (Stream<Path> procs = Files.list(Path.of("/proc"))) {
            return procs.map(p -> p.getFileName().toString())
                .filter(n -> n.chars().allMatch(Character::isDigit))
                .mapToLong(Long::parseLong)
                .filter(pid -> pid != self && isJava(pid))
                .min().orElse(-1);
        } catch (IOException e) {
            return -1;
        }
    }

    // Detect a JVM by libjvm.so in its memory map, not by comm=="java": a CRaC-restored
    // process comes back with comm=exe (and empty cmdline), so a comm match misses it,
    // making jcmd/thread-dump return null on CRaC even though jcmd itself works.
    private static boolean isJava(long pid) {
        try {
            return Files.readString(Path.of("/proc/" + pid + "/maps")).contains("libjvm.so");
        } catch (IOException e) {
            return false;
        }
    }

    /**
     * Full JSON thread dump (jcmd Thread.dump_to_file -format=json) — enumerates VIRTUAL
     * threads and their stacks, unlike Thread.print. jcmd writes the file in the TARGET's
     * filesystem; we read it back at the shared /perf path (or /proc/&lt;pid&gt;/root/&lt;path&gt;).
     * Returns null when jcmd failed or the JVM wrote no file: the caller answers 503 so the
     * sensor reports UNKNOWN instead of parsing a non-JSON fallback as "no blocked threads".
     * The file is this request's own and is deleted after reading.
     */
    private static String threadDumpJson(long pid) {
        String path = uniquePath("perf-threads-" + pid, ".json");
        try {
            var out = jcmd(pid, "Thread.dump_to_file", "-format=json", path);
            var onSidecar = readable(pid, path);   // after jcmd: which path exists depends on the file
            return out.ok() && Files.isReadable(onSidecar) ? Files.readString(onSidecar) : null;
        } catch (Exception e) {
            return null;
        } finally {
            for (var f : List.of(Path.of(path), Path.of("/proc/" + pid + "/root" + path))) {
                try {
                    Files.deleteIfExists(f);
                } catch (IOException ignored) {
                    // best-effort cleanup
                }
            }
        }
    }

    /** A file name in PERF_DIR no other request uses. */
    private static String uniquePath(String prefix, String suffix) {
        return perfDir() + "/" + prefix + "-" + System.nanoTime() + "-" + REQUESTS.incrementAndGet() + suffix;
    }

    /**
     * Run jcmd against the target with JAVA_TOOL_OPTIONS nulled (per the gotcha). The output is
     * drained on its own thread so the deadline holds even when jcmd keeps stdout open.
     */
    static Jcmd jcmd(long pid, String... command) {
        Process proc = null;
        try {
            var full = new java.util.ArrayList<String>(List.of("jcmd", String.valueOf(pid)));
            full.addAll(List.of(command));
            var pb = new ProcessBuilder(full);
            pb.environment().remove("JAVA_TOOL_OPTIONS");
            pb.redirectErrorStream(true);
            proc = pb.start();
            var out = new java.io.ByteArrayOutputStream();
            InputStream in = proc.getInputStream();
            var drain = Thread.ofVirtual().start(() -> {
                try (in) {
                    in.transferTo(out);
                } catch (IOException ignored) {
                    // the process was destroyed
                }
            });
            if (!proc.waitFor(JCMD_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                proc.destroyForcibly();
                drain.join(1000);
                return new Jcmd(-1, "jcmd " + String.join(" ", command) + " timed out after " + JCMD_TIMEOUT_SECONDS + " s\n");
            }
            drain.join(5000);
            return new Jcmd(proc.exitValue(), out.toString(StandardCharsets.UTF_8));
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            if (proc != null) proc.destroyForcibly();
            return new Jcmd(-1, "jcmd " + String.join(" ", command) + " interrupted\n");
        } catch (Exception e) {
            if (proc != null) proc.destroyForcibly();
            return new Jcmd(-1, "jcmd " + String.join(" ", command) + " failed: " + e + "\n");
        }
    }

    private static Map<String, String> query(String raw) {
        var map = new java.util.HashMap<String, String>();
        if (raw == null) {
            return map;
        }
        for (var pair : raw.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0) {
                map.put(pair.substring(0, eq), pair.substring(eq + 1));
            }
        }
        return map;
    }

    private static void respond(HttpExchange ex, int code, String body) throws IOException {
        ex.getResponseHeaders().add("Content-Type", "text/plain; charset=utf-8");
        respondRaw(ex, code, body);
    }

    private static void respondRaw(HttpExchange ex, int code, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.sendResponseHeaders(code, bytes.length);
        try (var os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
