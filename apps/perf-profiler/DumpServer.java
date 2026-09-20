// perf-profiler /dump endpoint — a tiny single-file HTTP server (run in JDK 25
// source mode: `java DumpServer.java [port]`). It exposes on-demand JVM diagnostics
// for the APP process across the shared PID namespace via `jcmd`, so the optimizer
// can collect ThreadFacts/heap without a collector or `kubectl exec`.
//
//   GET /dump?kind=threads  -> jcmd <pid> Thread.print -e
//   GET /dump?kind=heap     -> jcmd <pid> GC.heap_info + VM.flags
//   GET /dump?kind=jfr      -> jcmd <pid> JFR.dump (best-effort; needs an active recording)
//   GET /healthz            -> ok
//
// Runs in the sidecar (root + SYS_PTRACE + shareProcessNamespace), so jcmd can
// attach to the app JVM (PID 1). JAVA_TOOL_OPTIONS is nulled for each jcmd call —
// otherwise the app's flags (e.g. -Xlog:gc) contaminate jcmd's own output.
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
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

public class DumpServer {

    public static void main(String[] args) throws IOException {
        int port = args.length > 0 ? Integer.parseInt(args[0]) : 9100;
        var server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/healthz", ex -> respond(ex, 200, "ok\n"));
        server.createContext("/dump", DumpServer::handleDump);
        server.setExecutor(null);
        System.out.println("[dump-server] listening on :" + port);
        server.start();
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
            case "threads" -> body = threadDumpJson(pid);
            case "heap" -> body = jcmd(pid, "GC.heap_info") + "\n" + jcmd(pid, "VM.flags");
            case "jfr" -> body = jcmd(pid, "JFR.dump", "filename=/tmp/ondemand-" + pid + ".jfr");
            default -> {
                respond(ex, 400, "unknown kind: " + kind + " (threads|heap|jfr)\n");
                return;
            }
        }
        respond(ex, 200, body);
    }

    /** The app JVM: prefer PID 1 (the container entrypoint), else the lowest java pid that is not us. */
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
     * Full JSON thread dump (jcmd Thread.dump_to_file -format=json) — enumerates
     * VIRTUAL threads and their stacks, unlike Thread.print. jcmd writes the file in
     * the TARGET's filesystem; we read it back across the shared mount namespace at
     * /proc/&lt;pid&gt;/root/&lt;path&gt;. Falls back to Thread.print if anything fails.
     */
    private static String threadDumpJson(long pid) {
        String path = "/tmp/po-threads-" + pid + ".json";
        String out = jcmd(pid, "Thread.dump_to_file", "-overwrite", "-format=json", path);
        try {
            var onSidecar = Path.of("/proc/" + pid + "/root" + path);
            if (Files.isReadable(onSidecar)) {
                return Files.readString(onSidecar);
            }
        } catch (Exception e) {
            // fall through
        }
        // Fallback: platform-thread text dump (jcmd output + a marker).
        return "{\"fallback\":\"Thread.print\",\"note\":" + jsonString(out) + "}\n" + jcmd(pid, "Thread.print", "-e");
    }

    private static String jsonString(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").trim() + "\"";
    }

    /** Run jcmd against the target with JAVA_TOOL_OPTIONS nulled (per the gotcha). */
    private static String jcmd(long pid, String... command) {
        try {
            var full = new java.util.ArrayList<String>(List.of("jcmd", String.valueOf(pid)));
            full.addAll(List.of(command));
            var pb = new ProcessBuilder(full);
            pb.environment().remove("JAVA_TOOL_OPTIONS");
            pb.redirectErrorStream(true);
            var proc = pb.start();
            byte[] out;
            try (InputStream in = proc.getInputStream()) {
                out = in.readAllBytes();
            }
            if (!proc.waitFor(25, TimeUnit.SECONDS)) {
                proc.destroyForcibly();
                return "jcmd " + String.join(" ", command) + " timed out\n";
            }
            return new String(out, StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "jcmd " + String.join(" ", command) + " failed: " + e + "\n";
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
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        ex.getResponseHeaders().add("Content-Type", "text/plain; charset=utf-8");
        ex.sendResponseHeaders(code, bytes.length);
        try (var os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
