package com.example.perf.optimizer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.stereotype.Component;

/**
 * The finding-driven MCP tools: {@code measure} and {@code analyze} compute
 * everything in Java (no LLM); {@code explain} adds a Bedrock rationale +
 * ready-to-apply artifact for one finding. Claude Code (the MCP client) calls
 * these from the app repo and implements the returned artifacts.
 */
@Component
public class OptimizerMcpTools {

    private static final Logger logger = LoggerFactory.getLogger(OptimizerMcpTools.class);

    private final OptimizerService service;
    private final MarkdownRenderer markdown;

    public OptimizerMcpTools(OptimizerService service, MarkdownRenderer markdown) {
        this.service = service;
        this.markdown = markdown;
    }

    @Tool(description = """
        Measure a Java service on EKS: its Kubernetes desired-state (image, replicas,
        requests/limits, resizePolicy, JAVA_TOOL_OPTIONS, sidecars, HPA) and measured
        runtime (working-set floor/peak, heap, GC, effective CPUs, startup, restarts)
        plus a CPU/wall profile summary. No LLM — just facts. 'service' is the
        Pyroscope service_name = Kubernetes Deployment name, e.g. 'unicorn-store-spring'.
        """)
    public String measure(
        @ToolParam(description = "Pyroscope service_name = Deployment name, e.g. unicorn-store-spring") String service,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes) {
        logger.info("MCP measure service={} window={}", service, windowMinutes);
        return markdown.measure(this.service.measure(service, orDefault(windowMinutes)));
    }

    @Tool(description = """
        Analyze a Java service on EKS and return RANKED findings with status
        (OPEN/BLOCKED/RESOLVED/NOT_APPLICABLE/NOT_EVALUABLE), measured evidence, and
        Java-computed values (right-sized requests/limits, GC, startup levers). No LLM
        is used — repeated runs on the same state are identical. Sizing findings are
        BLOCKED until the profiling window is warm. A re-analyze after a fix reports
        the finding RESOLVED with a measured before→after delta. Use 'explain' for a
        rationale + ready-to-apply artifact for a specific finding.
        """)
    public String analyze(
        @ToolParam(description = "Pyroscope service_name = Deployment name, e.g. unicorn-store-spring") String service,
        @ToolParam(description = "Look-back window in minutes (default 15)", required = false) Integer windowMinutes) {
        logger.info("MCP analyze service={} window={}", service, windowMinutes);
        return markdown.analyze(this.service.analyze(service, orDefault(windowMinutes)));
    }

    private static int orDefault(Integer windowMinutes) {
        return windowMinutes == null || windowMinutes <= 0 ? 15 : windowMinutes;
    }
}
