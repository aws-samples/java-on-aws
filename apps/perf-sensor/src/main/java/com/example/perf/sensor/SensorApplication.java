package com.example.perf.sensor;

import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * perf-sensor — deterministic performance sensors for Java workloads on EKS, exposed over
 * MCP (streamable-http) and REST. No LLM, no AWS SDK: it measures (Kubernetes API,
 * Prometheus, Pyroscope, profiler sidecar /dump) and owns the sizing arithmetic and its
 * guards. All judgement lives in the java-on-eks-optimization / java-on-eks-checklist skills.
 */
@SpringBootApplication
@EnableScheduling   // StartupMetrics polls the profiled pods and publishes their startup gauge
public class SensorApplication {

    public static void main(String[] args) {
        SpringApplication.run(SensorApplication.class, args);
    }

    /** Register the sensor tools with the MCP server. */
    @Bean
    ToolCallbackProvider sensorToolCallbacks(SensorMcpTools sensorTools) {
        return MethodToolCallbackProvider.builder()
            .toolObjects(sensorTools)
            .build();
    }
}
