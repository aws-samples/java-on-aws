package com.example.perf.collector;

import com.example.perf.collector.CollectorProperties.DumpKind;
import com.example.perf.collector.CollectorProperties.Platform;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * POST /dump — analyzer trigger. Validates target is ours, validates the
 * workload is opted in (perf-profile/service label or tag), dispatches the
 * dump to a virtual thread, returns 202 immediately.
 *
 * 404 if the target isn't on this collector's node/task or isn't opted in.
 */
@RestController
public class DumpController {

    private static final Logger logger = LoggerFactory.getLogger(DumpController.class);

    private final DumpService dumpService;

    public DumpController(DumpService dumpService) {
        this.dumpService = dumpService;
    }

    @PostMapping("/dump")
    public ResponseEntity<Void> dump(@Valid @RequestBody DumpRequest body) {
        logger.info("Received /dump request jobId={} kind={} target={}",
            body.jobId(), body.kind(), body.target());
        return switch (dumpService.submit(body)) {
            case ACCEPTED -> ResponseEntity.accepted().build();
            case NOT_MY_TARGET, NOT_OPTED_IN -> ResponseEntity.status(404).build();
            case BAD_REQUEST -> ResponseEntity.badRequest().build();
        };
    }

    // === DTOs ===

    public record DumpRequest(
        @NotBlank String jobId,
        @NotBlank String s3Uri,
        @NotNull DumpKind kind,
        @NotNull DumpTarget target
    ) {}

    public record DumpTarget(Platform platform, String pod, String task) {

        @JsonCreator
        public static DumpTarget of(
            @JsonProperty("platform") String platformWire,
            @JsonProperty("pod") String pod,
            @JsonProperty("task") String task
        ) {
            return new DumpTarget(parsePlatform(platformWire), pod, task);
        }

        public String id() {
            return platform == Platform.ECS_FARGATE ? task : pod;
        }

        private static Platform parsePlatform(String s) {
            if (s == null || s.isBlank()) return null;
            return Platform.valueOf(s.toUpperCase().replace('-', '_'));
        }
    }
}
