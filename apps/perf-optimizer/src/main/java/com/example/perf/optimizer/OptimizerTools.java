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
 * {@link #optimizeService}. It pulls LIVE signals for the service — Pyroscope
 * CPU + wall profiles, and (from Prometheus) the container's measured memory
 * plus the app's measured startup (Micrometer application.ready.time) — and
 * asks Amazon Bedrock (grounded by an optimization system prompt + KB
 * heuristics/Dockerfiles) for a right-size / GC / startup plan, returned to the
 * MCP client (Claude Code) to implement.
 *
 * Measurement discipline: the model may only cite numbers that were MEASURED
 * here (fed in under "Measured now"); projected outcomes of a not-yet-applied
 * technique are qualitative. Real post-change numbers come from re-running.
 */
@Component
public class OptimizerTools {

    private static final Logger logger = LoggerFactory.getLogger(OptimizerTools.class);

    private static final String SYSTEM_PROMPT = """
        You are a Java-on-Kubernetes optimization engineer. Your job is to make a
        Spring Boot service on Amazon EKS lean and fast: right-size memory/CPU,
        pick the right GC, and cut startup — from LIVE signals measured on the
        running service.

        MEASUREMENT DISCIPLINE (critical):
          - The prompt gives you MEASURED values for THIS service under
            "## Measured now (live)": current startup time and container memory
            (working-set floor + peak). Use ONLY these measured numbers when you
            state the service's current state or derive requests/limits.
          - NEVER invent or recall numbers (no "~13s", "~380MB", "~4s") that are
            not in the measured block. If a measurement is marked unavailable,
            say so and give the shape of the recommendation without a fabricated
            number.
          - For a technique you have NOT yet measured (AOT / CRaC / boost
            outcome), describe the expected RELATIVE improvement qualitatively
            (e.g. "sub-second startup", "lower RSS") — do NOT state a projected
            number. Real post-change numbers come from RE-RUNNING this tool after
            the change is applied.

        Hard-won rules for this class of workload (small heap, ~1 vCPU
        container), validated by measurement — apply them and say why:
          - The container memory floor is NON-HEAP dominated (metaspace + code
            cache + thread stacks + JVM base), while the live heap is a fraction
            of it. RIGHT-SIZE OFF the measured container working-set, NOT heap
            alone. Set requests near the measured floor (correct bin-packing
            signal) and limits at the measured peak plus headroom; sizing off
            heap under-sizes and OOMs under load.
          - KEEP SerialGC for small heaps on ~1 vCPU. G1GC REGRESSES here (higher
            RSS and worse max pause) because its concurrent threads contend for
            the single core. Do NOT recommend "upgrade to G1".
          - Set -XX:MaxRAMPercentage=75 (explicit) rather than the 25% default.
          - Memory right-size and startup are INDEPENDENT: right-sizing does not
            speed startup. Startup is CPU/JIT-bound. To cut startup:
              * AOT cache (JDK 25): zero code change, cuts startup to a few seconds.
              * CRaC/Warp: sub-second startup AND the lowest RSS (leanest on both).
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
          - Do NOT invent JDK versions, base images, JVM flags, Linux
            capabilities, or CLI tools. Use only the Known ground truth and the
            Reference Dockerfiles given in the prompt.
          - This platform profiles via an async-profiler SIDECAR that pushes to
            Pyroscope automatically. Do NOT invent a Pyroscope Java agent or env
            vars like PYROSCOPE_APPLICATION_NAME — that is not how it works here.
          - If the Pyroscope tables show no samples, say so explicitly, but STILL
            give the VALIDATED shape (not generic advice): keep SerialGC;
            MaxRAMPercentage=75; requests near the measured working-set floor,
            limits at measured peak + headroom, CPU limit 1 vCPU; recommend AOT
            or CRaC for startup (CRaC also lowers RSS).

        Read the CPU profile (what is computing) and the wall profile (what is
        waiting on locks/I/O). Cite specific functions. Be concrete and concise.
        Prefer a small number of high-impact, applyable changes.
        """;

    private final ChatClient.Builder chatClientBuilder;
    private final PyroscopeTool pyroscope;
    private final PrometheusTool prometheus;
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
                          PrometheusTool prometheus,
                          ObjectProvider<VectorStore> vectorStoreProvider) {
        this.chatClientBuilder = chatClientBuilder;
        this.pyroscope = pyroscope;
        this.prometheus = prometheus;
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
        Grounded in LIVE measurements: Pyroscope CPU + wall profiles, the
        container's measured memory (Prometheus), and measured startup (Micrometer).
        The 'service' is the Pyroscope service_name, which equals the Kubernetes
        Deployment name, e.g. 'unicorn-store-spring'.
        """)
    public String optimizeService(
        @ToolParam(description = "Pyroscope service_name = Kubernetes Deployment name, e.g. unicorn-store-spring")
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

        // Live measurement (all via Prometheus). The Pyroscope service_name now
        // equals the K8s Deployment name (platform/cluster/namespace are labels,
        // not a name suffix), which for this workshop's service is also the
        // namespace and container name.
        var app = service;
        var startup = prometheus.startupSummary(app);
        var mem = prometheus.memorySummary(app, app, mins);
        var measured = new StringBuilder();
        measured.append(startup != null ? startup
            : "- startup: NOT MEASURABLE yet (app's application.ready.time not scraped — retry in ~1 min after deploy)\n");
        measured.append(mem != null ? mem
            : "- container memory: NOT MEASURABLE now (Prometheus has no working-set series for this container)\n");
        logger.info("measured: app={} startup={} memory={}", app, startup != null, mem != null);

        var userPrompt = """
            ## Target
            - service (Pyroscope service_name): **%s**
            - window: last %d minutes (%s .. %s)

            ## Pyroscope top functions — CPU (what is computing)
            %s

            ## Pyroscope top functions — wall (what is waiting)
            %s

            ## Known ground truth (facts — do NOT contradict or invent alternatives)
            - Runtime: Amazon Corretto **JDK 25**, Spring Boot 4.1. (NOT 17/21.)
            - Current GC: **SerialGC** (ergonomic default at 1 vCPU / small heap). Keep it; never G1.
            - The container memory floor is non-heap dominated (metaspace/code cache/threads) —
              size off the MEASURED container working-set, not heap.
            - Startup levers available for THIS service (pick one; state the expected
              outcome QUALITATIVELY, never a projected number):
              * AOT cache (JDK 25, zero code change) — cuts startup to a few seconds.
              * CRaC via **Azul Zulu 25 + Warp engine** — sub-second startup AND lowest RSS;
                userspace, **no privileged, no CHECKPOINT_RESTORE capability, no CRIU**.
              * in-place CPU boost — boot at 2 vCPU, resize down to 1 (no restart).

            ## Measured now (live) — the ONLY numbers you may cite for current state
            %s

            ---
            Produce:
            ## Verdict
            One line: over/under-provisioned? startup slow? contention? (Base it on the measured values.)

            ## Right-size (EKS)
            Concrete requests/limits (cpu, memory) DERIVED from the measured working-set
            (requests near the measured floor; limits at the measured peak + ~30-50%% headroom),
            MaxRAMPercentage, GC choice — with the one-line reason for each, per the rules.
            If memory was not measurable, say so and give the validated shape without inventing MB.

            ## Startup
            State the MEASURED current startup. Recommend AOT vs CRaC vs in-place CPU
            boost for this service, with the expected QUALITATIVE outcome (e.g.
            sub-second, lower RSS) and the trade-off — do NOT state a projected number.
            Note that re-running this tool after applying measures the real result.

            ## Apply
            The exact changes to make (deployment env/resources + which Dockerfile),
            phrased so an engineer/agent can implement them directly.
            """.formatted(service, mins, from, to, cpu, wall, measured.toString());

        if (!referenceDocs.isBlank()) {
            userPrompt += "\n\n## Reference — golden playbook & EXACT Dockerfiles"
                + " (use these verbatim; do NOT invent tags, flags, or checkpoint steps)\n"
                + referenceDocs;
        }

        var out = chat().prompt().user(userPrompt).call().content();
        return out == null ? "Model returned no content." : out;
    }
}
