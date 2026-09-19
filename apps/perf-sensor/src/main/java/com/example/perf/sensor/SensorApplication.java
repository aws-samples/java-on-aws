package com.example.perf.sensor;

import org.springframework.ai.tool.ToolCallbackProvider;
import org.springframework.ai.tool.method.MethodToolCallbackProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * perf-sensor — deterministic performance sensors for a Java workload on EKS,
 * exposed over MCP (streamable-http) and REST. No LLM, no AWS SDK: it measures
 * (Kubernetes API, Prometheus, Pyroscope, profiler sidecar /dump) and owns one
 * computation, memory sizing, with a guard. All judgement lives in the
 * java-on-eks-optimization / java-on-eks-checklist skills.
 */
@SpringBootApplication
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
