package com.example.agent;

import io.micrometer.observation.ObservationFilter;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Sends the Spring AI observations as OpenTelemetry spans through the ADOT Java agent, which exports
 * them to CloudWatch on AgentCore Runtime.
 */
@Configuration
public class ObservabilityConfig {

    // >> The OpenTelemetry SDK of the ADOT Java agent (started with `-javaagent`) instead of a second SDK
    @Bean
    OpenTelemetry openTelemetry() {
        return GlobalOpenTelemetry.get();
    }
    // <<

    // >> AgentCore Evaluations reads GenAI spans from `opentelemetry.instrumentation.*` scopes (generic framework support)
    @Bean
    Tracer otelTracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer("opentelemetry.instrumentation.spring_ai");
    }
    // <<

    // >> Add the GenAI semantic convention attributes to the Spring AI observations
    @Bean
    ObservationFilter genAiObservationFilter() {
        return new GenAiObservationFilter();
    }
    // <<
}
