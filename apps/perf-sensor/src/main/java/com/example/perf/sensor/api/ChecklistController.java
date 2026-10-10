package com.example.perf.sensor.api;

import com.example.perf.sensor.checklist.ChecklistEngine;
import com.example.perf.sensor.checklist.ChecklistService;
import com.example.perf.sensor.checklist.ChecklistService.ChecklistResult;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/**
 * The checklist score over REST, for {@code curl} next to what Claude sees over MCP.
 * {@code format}: json (default), markdown (the table Claude prints) or text (aligned, for a
 * terminal). Without {@code wait}, a pod younger than minUptimeSeconds answers 503 with
 * Retry-After. With {@code wait=true} the call waits for the pod and for the measurement; as
 * text or markdown it prints a dot every 5 s meanwhile, so one {@code curl -N} shows progress.
 */
@RestController
@RequestMapping("/api/v1")
public class ChecklistController {

    private static final ObjectMapper MAPPER = JsonMapper.builder().build();
    private static final int MAX_WAIT_SECONDS = 300;
    private static final int TICK_SECONDS = 5;

    private final ChecklistService checklist;

    public ChecklistController(ChecklistService checklist) {
        this.checklist = checklist;
    }

    @GetMapping("/checklist/{service}")
    public void checklist(@PathVariable String service,
                          @RequestParam(defaultValue = "json") String format,
                          @RequestParam(defaultValue = "" + ChecklistService.DEFAULT_MIN_UPTIME_SECONDS) int minUptimeSeconds,
                          @RequestParam(defaultValue = "false") boolean wait,
                          HttpServletResponse resp) throws IOException {
        boolean json = !"markdown".equals(format) && !"text".equals(format);
        resp.setCharacterEncoding("UTF-8");
        resp.setContentType(json ? "application/json" : "text/plain");
        if (!wait) {
            var r = checklist.checklist(service, minUptimeSeconds, 0);
            if ("SETTLING".equals(r.status())) {
                resp.setStatus(503);
                resp.setHeader("Retry-After", String.valueOf(Math.min(TICK_SECONDS, r.settleRemainingSeconds())));
            }
            resp.getWriter().print(json ? MAPPER.writeValueAsString(r) : body(r, format));
            return;
        }
        PrintWriter out = resp.getWriter();
        boolean progress = !json;
        var s = checklist.settle(service, minUptimeSeconds);
        int waited = 0;
        if (s.remainingSeconds() > 0) {
            emit(out, progress, "Pod is " + s.uptimeSeconds() + " s old, scoring at " + minUptimeSeconds + " s ");
            while (s.remainingSeconds() > 0 && waited < MAX_WAIT_SECONDS) {
                sleep(Math.min(TICK_SECONDS, s.remainingSeconds()));
                waited += TICK_SECONDS;
                emit(out, progress, ".");
                s = checklist.settle(service, minUptimeSeconds);
            }
            emit(out, progress, "\n");
        }
        String note = s.note();
        emit(out, progress, "Measuring ");
        var task = new FutureTask<>(() -> checklist.score(service, note));
        Thread.ofVirtual().name("checklist-" + service).start(task);
        ChecklistResult r;
        while (true) {
            try {
                r = task.get(TICK_SECONDS, TimeUnit.SECONDS);
                break;
            } catch (TimeoutException e) {
                emit(out, progress, ".");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (ExecutionException e) {
                emit(out, progress, "\n");
                out.print(json ? MAPPER.writeValueAsString(java.util.Map.of("status", "ERROR",
                    "reason", String.valueOf(e.getCause()))) : "checklist failed: " + e.getCause() + "\n");
                return;
            }
        }
        emit(out, progress, "\n\n");
        out.print(json ? MAPPER.writeValueAsString(r) : body(r, format));
        out.flush();
    }

    private static String body(ChecklistResult r, String format) {
        if (!"OK".equals(r.status())) {
            return r.note() + ", " + r.settleRemainingSeconds() + " s to go\n";
        }
        String table = "text".equals(format) ? ChecklistEngine.text(r.items()) : r.markdown();
        return r.note() == null ? table : table + "\n" + r.note() + "\n";
    }

    private static void emit(PrintWriter out, boolean progress, String s) {
        if (progress) {
            out.print(s);
            out.flush();
        }
    }

    private static void sleep(int seconds) {
        try {
            Thread.sleep(seconds * 1000L);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
