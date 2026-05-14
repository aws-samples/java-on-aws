package com.example.perf.analyzer;

import io.kubernetes.client.openapi.ApiClient;
import io.kubernetes.client.openapi.Configuration;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.util.ClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.ecs.EcsClient;
import software.amazon.awssdk.services.s3.S3Client;

import java.io.IOException;

/**
 * perf-analyzer — the brain of the agentic performance platform.
 *
 * Receives triggers (developer /api/v1/analyze + Grafana /api/v1/grafana-webhook),
 * orchestrates collector-side JFR and thread-dump capture, queries Pyroscope
 * for top functions, calls Amazon Bedrock via Spring AI, writes the Markdown
 * report to Amazon S3.
 *
 * AWS SDK and Kubernetes client beans are wired here so the rest of the
 * package stays flat — one file per concept, no config folder.
 */
@SpringBootApplication
@EnableAsync
@EnableScheduling
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @Bean
    S3Client s3Client(@Value("${AWS_REGION:us-east-1}") String region) {
        return S3Client.builder().region(Region.of(region)).build();
    }

    @Bean
    EcsClient ecsClient(@Value("${AWS_REGION:us-east-1}") String region) {
        return EcsClient.builder().region(Region.of(region)).build();
    }

    @Bean
    CoreV1Api coreV1Api() throws IOException {
        ApiClient client = ClientBuilder.cluster().build();
        Configuration.setDefaultApiClient(client);
        return new CoreV1Api(client);
    }
}
