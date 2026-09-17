package com.example.perf.optimizer.api;

import com.example.perf.optimizer.OptimizerService;
import com.example.perf.optimizer.OptimizerService.AnalyzeResult;
import com.example.perf.optimizer.OptimizerService.MeasureResult;
import com.example.perf.optimizer.explain.Explanation;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * REST facade exposing the SAME operations as the MCP tools, returning structured
 * JSON (the records) rather than Markdown. measure/analyze compute in Java with no
 * LLM; explain (added with the explainer) is the only LLM path.
 *
 * <p>Note: {@code perf-analyzer} owns {@code POST /api/v1/analyze} in a different
 * app; this optimizer uses path-style GETs and is not deployed alongside it.
 */
@RestController
@RequestMapping("/api/v1")
public class OptimizerController {

    private final OptimizerService optimizer;

    public OptimizerController(OptimizerService optimizer) {
        this.optimizer = optimizer;
    }

    @GetMapping("/measure/{service}")
    public MeasureResult measure(@PathVariable String service,
                                 @RequestParam(defaultValue = "15") int windowMinutes) {
        return optimizer.measure(service, windowMinutes);
    }

    @GetMapping("/analyze/{service}")
    public AnalyzeResult analyze(@PathVariable String service,
                                 @RequestParam(defaultValue = "15") int windowMinutes) {
        return optimizer.analyze(service, windowMinutes);
    }

    /** The only LLM path: explain one finding (artifact + values are Java-computed). */
    @GetMapping("/explain/{service}/{findingId}")
    public Explanation explain(@PathVariable String service, @PathVariable String findingId) {
        return optimizer.explain(service, findingId);
    }
}
