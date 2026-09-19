package com.example.perf.sensor.api;

import com.example.perf.sensor.SensorService;
import com.example.perf.sensor.SensorService.MeasureResult;
import com.example.perf.sensor.SensorService.ProfileTop;
import com.example.perf.sensor.SensorService.SizeParams;
import com.example.perf.sensor.SensorService.SizeResult;
import com.example.perf.sensor.SensorService.StartupResult;
import com.example.perf.sensor.facts.ThreadFacts;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * REST facade exposing the same operations as the MCP tools, returning structured
 * JSON records. Deterministic; no LLM. Used for the implementer verification
 * (spec 4a) and as a fallback surface. Health is served by Actuator at
 * {@code /actuator/health}.
 */
@RestController
@RequestMapping("/api/v1")
public class SensorController {

    private final SensorService sensor;

    public SensorController(SensorService sensor) {
        this.sensor = sensor;
    }

    @GetMapping("/measure/{service}")
    public MeasureResult measure(@PathVariable String service,
                                 @RequestParam(defaultValue = "15") int windowMinutes) {
        return sensor.measure(service, windowMinutes);
    }

    @GetMapping("/sizeMemory/{service}")
    public SizeResult sizeMemory(@PathVariable String service,
                                 @RequestParam(defaultValue = "15") int windowMinutes,
                                 @RequestParam double floorFactor,
                                 @RequestParam double peakFactor,
                                 @RequestParam double floorSafetyFactor,
                                 @RequestParam int roundMi,
                                 @RequestParam int warmSeconds,
                                 @RequestParam int minSamples,
                                 @RequestParam double minRequestRate,
                                 @RequestParam double minDeltaMi) {
        return sensor.sizeMemory(service, windowMinutes,
            new SizeParams(floorFactor, peakFactor, floorSafetyFactor, roundMi, warmSeconds,
                minSamples, minRequestRate, minDeltaMi));
    }

    @GetMapping("/threadDump/{service}")
    public ThreadFacts threadDump(@PathVariable String service,
                                  @RequestParam(defaultValue = "1") int sampleN) {
        return sensor.threadDump(service, sampleN);
    }

    @GetMapping("/profileTop/{service}")
    public ProfileTop profileTop(@PathVariable String service,
                                 @RequestParam(defaultValue = "cpu") String type,
                                 @RequestParam(defaultValue = "15") int windowMinutes,
                                 @RequestParam(defaultValue = "15") int limit) {
        return sensor.profileTop(service, type, windowMinutes, limit);
    }

    @GetMapping("/startupLog/{service}")
    public StartupResult startupLog(@PathVariable String service) {
        return sensor.startupLog(service);
    }

    /** List the sensor tools for the fallback page blocks. */
    @GetMapping("/tools")
    public List<Map<String, String>> tools() {
        return List.of(
            Map.of("name", "measure",
                "input", "service, windowMinutes=15",
                "output", "WorkloadFacts (incl. readyPods) + RuntimeFacts + ProfileFacts summary + window + per-pod breakdown"),
            Map.of("name", "sizeMemory",
                "input", "service, windowMinutes, floorFactor, peakFactor, floorSafetyFactor, roundMi, warmSeconds, minSamples, minRequestRate, minDeltaMi",
                "output", "{status, reason, requests.memory, limits.memory, maxRamPercentage, gc, evidence, params}"),
            Map.of("name", "threadDump",
                "input", "service, sampleN=1",
                "output", "ThreadFacts {pod, total, byState, virtualThreads, requestThreadsBlockedInFutureGet, carriersParkedInPoolWait, topBlockingFrames, sample}"),
            Map.of("name", "profileTop",
                "input", "service, type=cpu|wall, windowMinutes=15, limit=15",
                "output", "{frames, jitShare, gcShare, futexWallShare, samples}"),
            Map.of("name", "startupLog",
                "input", "service",
                "output", "{pod, line, seconds, kind}"));
    }
}
