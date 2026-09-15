package com.example.perf.optimizer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Lazy;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

import java.time.Duration;
import java.time.Instant;

/**
 * The MCP-exposed optimization tool. One tool for the thin slice:
 * {@link #optimizeService}. It pulls live Pyroscope CPU + wall signals and
 * asks Amazon Bedrock (grounded by an optimization system prompt encoding the
 * validated heuristics) for a right-size / GC / startup plan, returned to the
 * MCP client (Claude Code) to implement.
 *
 * Later phases: emit applyable artifacts (deployment patch + AOT/CRaC
 * Dockerfile), add JFR heap/GC/container signals, and KB grounding.
 */
@Component
public class OptimizerTools {

    private static final Logger logger = LoggerFactory.getLogger(OptimizerTools.class);

    private static final String SYSTEM_PROMPT = """
        You are a Java-on-Kubernetes optimization engineer. Your job is to make a
        Spring Boot service on Amazon EKS lean and fast: right-size memory/CPU,
        pick the right GC, and cut startup — from live profiling signals.

        Hard-won rules for this class of workload (small heap, ~1 vCPU container),
        validated by measurement — apply them and say why:
          - The RSS floor is NON-HEAP dominated (metaspace + code cache + thread
            stacks + JVM base ~350-400MB) while the live heap is often only
            ~50-70MB. RIGHT-SIZE OFF cgroup RSS + non-heap, NOT heap alone.
            Requesting near the RSS floor and limiting with headroom is correct;
            sizing off heap under-sizes and OOMs under load.
          - KEEP SerialGC for small heaps on ~1 vCPU. G1GC REGRESSES here
            (measured ~+80MB RSS and ~20x worse max pause) because its concurrent
            threads contend for the single core. Do NOT recommend "upgrade to G1".
          - Set -XX:MaxRAMPercentage=75 (explicit) rather than relying on the 25%
            default.
          - Memory right-size and startup are INDEPENDENT: right-sizing does not
            speed startup. Startup is CPU/JIT-bound. To cut startup:
              * AOT cache (JDK 25, zero code change) ~= 4s (from ~13s),
              * CRaC/Warp ~= 0.2s AND ~half the RSS (leanest on both),
              * in-place CPU boost: boot at 2 vCPU then resize down to 1 (no restart).
          - CRaC GC/heap are baked at checkpoint (Dockerfile), not runtime env.

        NON-NEGOTIABLE:
          - NEVER recommend or emit -XX:+UseG1GC. The current and correct GC for
            this service is SerialGC (JVM ergonomic default at ~1 vCPU / small
            heap). "Keep G1" / "G1 is default" is WRONG here.
          - JIT/C2 compiler frames (PhaseChaitin, PhaseIdealLoop, PhaseLive,
            Compile::, CodeHeap::) plus a high futex/idle wall% indicate a COLD /
            WARM-UP window, NOT steady-state load. Do NOT size CPU or memory UP to
            feed the JIT storm — it disappears after warm-up. If the profile is
            JIT-dominated, SAY the window looks like warm-up, size for STEADY
            STATE (lean), and suggest re-profiling after a warm-up.
          - Do NOT invent JDK versions, base images, JVM flags, Linux capabilities,
            or CLI tools. Use only the Known ground truth given in the prompt.
          - This platform profiles via an async-profiler SIDECAR that pushes to
            Pyroscope automatically. Do NOT invent a Pyroscope Java agent or env
            vars like PYROSCOPE_APPLICATION_NAME — that is not how it works here.
          - If the Pyroscope tables show no samples, say so explicitly, but STILL
            give these VALIDATED defaults (do not fall back to generic advice):
            SerialGC; requests ~250m / 512Mi; limits ~1 vCPU / 768Mi;
            MaxRAMPercentage=75; and recommend AOT (~4s) or CRaC (~0.2s, also
            ~half the RSS) for startup. These are measured for this exact service.

        Read the CPU profile (what is computing) and the wall profile (what is
        waiting on locks/I/O). Cite specific functions and numbers. Be concrete
        and concise. Prefer a small number of high-impact, applyable changes.
        """;

    private final ChatClient.Builder chatClientBuilder;
    private final PyroscopeTool pyroscope;
    private final ObjectProvider<VectorStore> vectorStoreProvider;
    private final String referenceDocs;
    private volatile ChatClient chatClient;

    // @Lazy breaks the bean cycle: this tool object is registered as an MCP
    // ToolCallbackProvider, which the Bedrock chat model's tool resolver also
    // consumes. Injecting the builder lazily (and building the ChatClient on
    // first use, not in the constructor) defers that edge past context refresh.
    // vectorStoreProvider is optional: present only when a Bedrock KB id is
    // configured (bootstrap-provisioned) -> QuestionAnswerAdvisor grounds on it.
    public OptimizerTools(@Lazy ChatClient.Builder chatClientBuilder,
                          PyroscopeTool pyroscope,
                          ObjectProvider<VectorStore> vectorStoreProvider) {
        this.chatClientBuilder = chatClientBuilder;
        this.pyroscope = pyroscope;
        this.vectorStoreProvider = vectorStoreProvider;
        this.referenceDocs = loadReferenceDocs();
    }

    // Golden playbook + exact AOT/CRaC Dockerfiles bundled in the image
    // (classpath kb/*.md). Injected into every prompt so artifacts are
    // copy-paste-correct. This is the grounding path where a Bedrock KB can't
    // be provisioned (participant creds lack IAM/S3-create). When the workshop
    // bootstrap provisions a Bedrock KB (elevated perms), swap this for a
    // QuestionAnswerAdvisor over the KB vector store.
    private static String loadReferenceDocs() {
        try {
            var resources = new PathMatchingResourcePatternResolver()
                .getResources("classpath:kb/*.md");
            var sb = new StringBuilder();
            for (var r : resources) {
                sb.append("\n### ").append(r.getFilename()).append("\n\n")
                  .append(r.getContentAsString(StandardCharsets.UTF_8)).append("\n");
            }
            return sb.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private ChatClient chat() {
        if (chatClient == null) {
            synchronized (this) {
                if (chatClient == null) {
                    var b = chatClientBuilder.defaultSystem(SYSTEM_PROMPT);
                    var vs = vectorStoreProvider.getIfAvailable();
                    if (vs != null) {
                        b = b.defaultAdvisors(QuestionAnswerAdvisor.builder(vs).build());
                        logger.info("KB grounding ENABLED (QuestionAnswerAdvisor over Bedrock KB)");
                    } else {
                        logger.info("No Bedrock KB configured — grounding on bundled kb/*.md only");
                    }
                    chatClient = b.build();
                }
            }
        }
        return chatClient;
    }

    @Tool(description = """
        Analyze a Java service running on EKS and return a prioritized
        optimization plan: right-sized CPU/memory requests & limits, GC choice,
        heap sizing, and startup levers (AOT / CRaC / in-place CPU boost).
        Grounded in live Pyroscope CPU + wall profiles for the service.
        The 'service' is the Pyroscope service_name, e.g. 'unicorn-store-spring-eks'.
        """)
    public String optimizeService(
        @ToolParam(description = "Pyroscope service_name, e.g. unicorn-store-spring-eks")
        String service,
        @ToolParam(description = "Look-back window in minutes (default 30 if <= 0)", required = false)
        Integer windowMinutes
    ) {
        var mins = (windowMinutes == null || windowMinutes <= 0) ? 30 : windowMinutes;
        var to = Instant.now();
        var from = to.minus(Duration.ofMinutes(mins));
        logger.info("optimizeService: service={} window={}m", service, mins);

        var cpu = pyroscope.topFunctions(service, "cpu", from.toString(), to.toString(), 20);
        var wall = pyroscope.topFunctions(service, "wall", from.toString(), to.toString(), 20);

        var userPrompt = """
            ## Target
            - service (Pyroscope service_name): **%s**
            - window: last %d minutes (%s .. %s)

            ## Pyroscope top functions — CPU (what is computing)
            %s

            ## Pyroscope top functions — wall (what is waiting)
            %s

            ## Known ground truth (measured for THIS service — do NOT contradict or invent alternatives)
            - Runtime: Amazon Corretto **JDK 25**, Spring Boot 4.1. (NOT 17/21.)
            - Current GC: **SerialGC** (ergonomic default at 1 vCPU / small heap). Keep it; never G1.
            - Baseline footprint: heap ~50MB used / ~67MB committed; RSS ~380MB idle, ~517MB under load.
              The RSS floor is NON-HEAP (metaspace/code cache/threads) — size off RSS, not heap.
            - Startup ~13s at 1 vCPU. Measured startup levers for THIS service:
              * AOT cache (JDK 25, zero code change): ~4s.
              * CRaC via **Azul Zulu 25 + Warp engine**: ~0.2s AND ~190MB RSS —
                userspace, **no privileged, no CHECKPOINT_RESTORE capability, no CRIU**.
              * in-place CPU boost: boot at 2 vCPU, resize down to 1 (no restart).
            - Validated right-size: requests ~250m/512Mi, limits ~1 vCPU/768Mi, MaxRAMPercentage=75.

            ---
            Produce:
            ## Verdict
            One line: over/under-provisioned? startup slow? contention?

            ## Right-size (EKS)
            Concrete requests/limits (cpu, memory), MaxRAMPercentage, GC choice —
            with the one-line reason for each, per the rules.

            ## Startup
            Recommend AOT vs CRaC vs in-place CPU boost for this service, with the
            expected number and the trade-off.

            ## Apply
            The exact changes to make (deployment env/resources + which Dockerfile),
            phrased so an engineer/agent can implement them directly.
            """.formatted(service, mins, from, to, cpu, wall);

        if (!referenceDocs.isBlank()) {
            userPrompt += "\n\n## Reference — golden playbook & EXACT Dockerfiles"
                + " (use these verbatim; do NOT invent tags, flags, or checkpoint steps)\n"
                + referenceDocs;
        }

        var out = chat().prompt().user(userPrompt).call().content();
        return out == null ? "Model returned no content." : out;
    }
}
