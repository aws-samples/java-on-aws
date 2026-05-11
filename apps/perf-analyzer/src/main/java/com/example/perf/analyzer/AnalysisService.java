package com.example.perf.analyzer;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.kubernetes.client.openapi.ApiException;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import software.amazon.awssdk.services.ecs.EcsClient;
import software.amazon.awssdk.services.ecs.model.DescribeTasksRequest;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * Virtual-thread orchestrator. Each submitted analysis runs on its own
 * virtual thread, launching three parallel sub-lanes for JFR, thread dump,
 * and Pyroscope top functions. Results are stitched together, handed to
 * AiService, and the Markdown report lands in S3 alongside the raw artifacts.
 *
 * Collector locating (pod -> node -> DaemonSet pod IP on EKS; task ARN ->
 * ENI IP on ECS) lives here too. It's a single-responsibility concern —
 * "find the right collector and ask it for data".
 *
 * Domain types (Platform, TriggerSource, AnalysisRequest, AnalysisHandle,
 * AnalysisContext) are inner records matching the flat layout convention.
 */
@Service
public class AnalysisService {

    private static final Logger logger = LoggerFactory.getLogger(AnalysisService.class);
    private static final DateTimeFormatter TS =
        DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneOffset.UTC);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final int COLLECTOR_PORT = 8080;

    private final CoreV1Api k8s;
    private final EcsClient ecs;
    private final S3Repository s3;
    private final JfrParser jfrParser;
    private final AiService ai;
    private final PyroscopeTool pyroscope;
    private final String collectorNamespace;
    private final String collectorPodLabel;

    private final RestClient restClient = RestClient.builder().build();
    private final ExecutorService laneExecutor = Executors.newVirtualThreadPerTaskExecutor();

    public AnalysisService(
        CoreV1Api k8s,
        EcsClient ecs,
        S3Repository s3,
        JfrParser jfrParser,
        AiService ai,
        PyroscopeTool pyroscope,
        @Value("${perf.analyzer.collector.namespace:monitoring}") String collectorNamespace,
        @Value("${perf.analyzer.collector.pod-label:app=perf-collector}") String collectorPodLabel
    ) {
        this.k8s = k8s;
        this.ecs = ecs;
        this.s3 = s3;
        this.jfrParser = jfrParser;
        this.ai = ai;
        this.pyroscope = pyroscope;
        this.collectorNamespace = collectorNamespace;
        this.collectorPodLabel = collectorPodLabel;
    }

    /** Submit for async processing; returns immediately with the analysisId + S3 prefix. */
    public AnalyzeController.AnalysisHandle submit(AnalysisRequest request) {
        var analysisId = TS.format(Instant.now()) + "-" + shortRandom();
        var prefix = s3.analysisPrefix(request, analysisId);
        var handle = new AnalyzeController.AnalysisHandle(
            analysisId, "s3://" + s3.bucketName() + "/" + prefix);
        runAsync(request, analysisId, prefix);
        return handle;
    }

    @Async
    void runAsync(AnalysisRequest request, String analysisId, String prefix) {
        CompletableFuture.runAsync(() -> run(request, analysisId, prefix), laneExecutor)
            .exceptionally(ex -> {
                logger.error("Analysis {} failed: {}", analysisId, ex.getMessage(), ex);
                return null;
            });
    }

    private void run(AnalysisRequest request, String analysisId, String prefix) {
        logger.info("Analysis {} starting: service={} platform={} target={}",
            analysisId, request.service(), request.platform(), request.target());

        try {
            s3.putString(
                s3.analysisObjectUri(prefix, "request.json"),
                MAPPER.writerWithDefaultPrettyPrinter().writeValueAsString(request),
                "application/json");
        } catch (Exception e) {
            logger.warn("Could not persist request.json: {}", e.getMessage());
        }

        URI collectorUrl;
        WorkloadMetadata metadata;
        try {
            var located = locateCollector(request);
            collectorUrl = located.url();
            metadata = located.metadata();
        } catch (Exception e) {
            writePartialFailure(request, analysisId, prefix,
                "Collector locate failed: " + e.getMessage(), null, null, null);
            return;
        }

        var jfrDumpUri = s3.profilingDumpUri(request, analysisId, "jfr");
        var threadDumpUri = s3.profilingDumpUri(request, analysisId, "json");

        var jfrLane = CompletableFuture.supplyAsync(
            () -> captureJfr(request, analysisId, collectorUrl, jfrDumpUri), laneExecutor);
        var threadLane = CompletableFuture.supplyAsync(
            () -> captureThreadDump(request, analysisId, collectorUrl, threadDumpUri), laneExecutor);
        var pyroLane = CompletableFuture.supplyAsync(
            () -> pyroscope.topFunctions(
                request.service(),
                Instant.now().minus(Duration.ofMinutes(5)).toString(),
                Instant.now().toString(),
                20),
            laneExecutor);

        String jfrMarkdown = null;
        String threadDumpText = null;
        String pyroscopeMarkdown = null;

        try { jfrMarkdown = jfrLane.get(3, TimeUnit.MINUTES); }
        catch (Exception e) { logger.warn("JFR lane failed: {}", e.getMessage()); }
        try { threadDumpText = threadLane.get(60, TimeUnit.SECONDS); }
        catch (Exception e) { logger.warn("Thread dump lane failed: {}", e.getMessage()); }
        try { pyroscopeMarkdown = pyroLane.get(30, TimeUnit.SECONDS); }
        catch (Exception e) { logger.warn("Pyroscope lane failed: {}", e.getMessage()); }

        var ctx = new AnalysisContext(
            request, analysisId, jfrMarkdown, threadDumpText, pyroscopeMarkdown,
            metadata.githubRepo(), metadata.githubPath());

        String analysisMd;
        try {
            analysisMd = ai.analyze(ctx);
        } catch (Exception e) {
            writePartialFailure(request, analysisId, prefix,
                "Bedrock analysis failed: " + e.getMessage(),
                jfrMarkdown, threadDumpText, pyroscopeMarkdown);
            return;
        }

        if (jfrMarkdown != null) {
            s3.putString(s3.analysisObjectUri(prefix, "events.md"), jfrMarkdown, "text/markdown");
        }
        if (threadDumpText != null) {
            s3.putString(s3.analysisObjectUri(prefix, "threaddump.json"),
                "{\"raw\":" + MAPPER.valueToTree(threadDumpText).toString() + "}",
                "application/json");
        }
        s3.putString(s3.analysisObjectUri(prefix, "analysis.md"), analysisMd, "text/markdown");

        logger.info("Analysis {} complete: s3://{}/{}", analysisId, s3.bucketName(), prefix);
    }

    // --- Collector location ---

    /**
     * Collector endpoint plus the target workload's metadata — repo/path
     * for the source-code tool. We read that from pod annotations (EKS)
     * or task tags (ECS) during the same API call that locates the
     * collector, so the analyzer stays workload-agnostic.
     */
    private record LocatedCollector(URI url, WorkloadMetadata metadata) {}

    record WorkloadMetadata(String githubRepo, String githubPath) {
        static WorkloadMetadata empty() { return new WorkloadMetadata(null, null); }
    }

    private static final String ANN_REPO = "perf-profile/github-repo";
    private static final String ANN_PATH = "perf-profile/github-path";

    private LocatedCollector locateCollector(AnalysisRequest request) {
        return switch (request.platform()) {
            case EKS -> locateCollectorEks(request);
            case ECS_FARGATE -> locateCollectorEcs(request);
        };
    }

    private LocatedCollector locateCollectorEks(AnalysisRequest request) {
        try {
            var pod = k8s.readNamespacedPod(request.pod(), request.service()).execute();
            var nodeName = pod.getSpec() == null ? null : pod.getSpec().getNodeName();
            if (nodeName == null || nodeName.isBlank()) {
                throw new IllegalStateException(
                    "Pod %s has no nodeName (not yet scheduled?)".formatted(request.pod()));
            }
            var list = k8s.listNamespacedPod(collectorNamespace)
                .fieldSelector("spec.nodeName=" + nodeName)
                .labelSelector(collectorPodLabel)
                .execute();
            if (list.getItems() == null || list.getItems().isEmpty()) {
                throw new IllegalStateException("No collector pod on node " + nodeName);
            }
            var ip = list.getItems().getFirst().getStatus().getPodIP();
            if (ip == null || ip.isBlank()) {
                throw new IllegalStateException("Collector pod has no IP yet");
            }
            var annotations = pod.getMetadata().getAnnotations();
            var metadata = annotations == null
                ? WorkloadMetadata.empty()
                : new WorkloadMetadata(annotations.get(ANN_REPO), annotations.get(ANN_PATH));
            return new LocatedCollector(
                URI.create("http://%s:%d".formatted(ip, COLLECTOR_PORT)), metadata);
        } catch (ApiException e) {
            throw new RuntimeException(
                "K8s API error resolving collector for pod " + request.pod() + ": " + e.getResponseBody(), e);
        }
    }

    private LocatedCollector locateCollectorEcs(AnalysisRequest request) {
        var cluster = extractEcsClusterFromTaskArn(request.task());
        var response = ecs.describeTasks(DescribeTasksRequest.builder()
            .cluster(cluster)
            .tasks(request.task())
            .include(software.amazon.awssdk.services.ecs.model.TaskField.TAGS)
            .build());
        if (response.tasks().isEmpty()) {
            throw new IllegalStateException("ECS task not found: " + request.task());
        }
        var task = response.tasks().getFirst();
        var ip = task.attachments().stream()
            .flatMap(a -> a.details().stream())
            .filter(d -> "privateIPv4Address".equals(d.name()))
            .map(d -> d.value())
            .filter(v -> v != null && !v.isBlank())
            .findFirst()
            .orElseThrow(() -> new IllegalStateException(
                "Task " + request.task() + " has no privateIPv4Address"));
        String repo = null;
        String path = null;
        for (var t : task.tags()) {
            if ("perf-profile:github-repo".equals(t.key())) repo = t.value();
            else if ("perf-profile:github-path".equals(t.key())) path = t.value();
        }
        return new LocatedCollector(
            URI.create("http://%s:%d".formatted(ip, COLLECTOR_PORT)),
            new WorkloadMetadata(repo, path));
    }


    private static String extractEcsClusterFromTaskArn(String taskArn) {
        var idx = taskArn.indexOf(":task/");
        if (idx < 0) throw new IllegalArgumentException("Invalid ECS task ARN: " + taskArn);
        var tail = taskArn.substring(idx + ":task/".length());
        var slash = tail.indexOf('/');
        if (slash < 0) throw new IllegalArgumentException("Task ARN missing cluster segment: " + taskArn);
        return tail.substring(0, slash);
    }

    // --- Collector RPC + data capture ---

    private String captureJfr(AnalysisRequest request, String analysisId, URI collectorUrl, URI s3Uri) {
        requestDump(collectorUrl, analysisId, s3Uri, DumpKind.JFR, request);
        waitForS3(s3Uri, Duration.ofMinutes(2));
        var bytes = s3.getBytes(s3Uri);
        Path tmp;
        try {
            tmp = Files.createTempFile("perf-analysis-", ".jfr");
            Files.write(tmp, bytes);
        } catch (Exception e) {
            throw new RuntimeException("Failed writing temp JFR: " + e.getMessage(), e);
        }
        try {
            return jfrParser.formatForModel(jfrParser.parse(tmp));
        } catch (Exception e) {
            throw new RuntimeException("JFR parse failed: " + e.getMessage(), e);
        } finally {
            try { Files.deleteIfExists(tmp); } catch (Exception _) {}
        }
    }

    private String captureThreadDump(AnalysisRequest request, String analysisId, URI collectorUrl, URI s3Uri) {
        requestDump(collectorUrl, analysisId, s3Uri, DumpKind.THREAD_DUMP, request);
        waitForS3(s3Uri, Duration.ofSeconds(30));
        return new String(s3.getBytes(s3Uri));
    }

    private void requestDump(URI collectorUrl, String jobId, URI s3Uri,
                             DumpKind kind, AnalysisRequest target) {
        var body = Map.of(
            "jobId", jobId,
            "s3Uri", s3Uri.toString(),
            "kind", kind.wire,
            "target", Map.of(
                "platform", target.platform().name().toLowerCase().replace('_', '-'),
                "pod", target.pod() == null ? "" : target.pod(),
                "task", target.task() == null ? "" : target.task()));
        try {
            var response = restClient.post()
                .uri(collectorUrl.resolve("/dump"))
                .body(body)
                .retrieve()
                .toBodilessEntity();
            logger.info("Collector /dump accepted: status={} url={} kind={}",
                response.getStatusCode(), collectorUrl, kind);
        } catch (RestClientException e) {
            throw new RuntimeException(
                "Collector " + collectorUrl + " /dump (" + kind + ") failed: " + e.getMessage(), e);
        }
    }

    private void waitForS3(URI s3Uri, Duration maxWait) {
        var deadline = Instant.now().plus(maxWait);
        while (Instant.now().isBefore(deadline)) {
            if (s3.exists(s3Uri)) return;
            try { Thread.sleep(2000); }
            catch (InterruptedException _) { Thread.currentThread().interrupt(); return; }
        }
        throw new RuntimeException("Timed out waiting for S3 object: " + s3Uri);
    }

    private void writePartialFailure(AnalysisRequest request, String analysisId, String prefix,
                                     String reason, String jfr, String tdump, String pyro) {
        var sb = new StringBuilder();
        sb.append("# Analysis (partial failure)\n\n");
        sb.append("**Reason:** ").append(reason).append("\n\n");
        sb.append("- analysisId: ").append(analysisId).append('\n');
        sb.append("- service: ").append(request.service()).append('\n');
        sb.append("- platform: ").append(request.platform()).append('\n');
        sb.append("- target: ").append(request.target()).append('\n');
        sb.append("- source: ").append(request.source()).append("\n\n");
        if (pyro != null) sb.append("## Pyroscope (collected)\n\n").append(pyro).append("\n\n");
        if (jfr != null) sb.append("## JFR (collected)\n\n").append(jfr).append("\n\n");
        if (tdump != null) sb.append("## Thread dump (head)\n\n```\n").append(tdump).append("\n```\n\n");
        s3.putString(s3.analysisObjectUri(prefix, "analysis.md"), sb.toString(), "text/markdown");
    }

    private static String shortRandom() {
        return Long.toHexString(Double.doubleToLongBits(Math.random())).substring(0, 6);
    }

    // === Domain types ===

    public enum Platform { EKS, ECS_FARGATE }

    public enum TriggerSource { ON_DEMAND, GRAFANA_WEBHOOK }

    public enum DumpKind {
        JFR("jfr"),
        THREAD_DUMP("threaddump");
        final String wire;
        DumpKind(String wire) { this.wire = wire; }
    }

    public record AnalysisRequest(
        String service, Platform platform, String pod, String task, String reason, TriggerSource source
    ) {
        public String target() { return platform == Platform.ECS_FARGATE ? task : pod; }
    }

    public record AnalysisContext(
        AnalysisRequest request,
        String analysisId,
        String jfrSummaryMarkdown,
        String threadDumpText,
        String pyroscopeTopFunctionsMarkdown,
        String githubRepo,     // e.g. "aws-samples/java-on-aws", null if not configured
        String githubPath      // e.g. "apps/unicorn-store-spring"
    ) {}
}
