package com.example.perf.collector;

import io.kubernetes.client.openapi.ApiClient;
import io.kubernetes.client.openapi.Configuration;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.util.ClientBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

import java.io.IOException;

/**
 * perf-collector — runs alongside target JVMs.
 *
 * On Amazon EKS: DaemonSet, hostPID=true, SYS_PTRACE. Discovers JVMs on the
 * node, attaches async-profiler for continuous Pyroscope push, serves /dump
 * on demand for JFR and Thread.print.
 *
 * On Amazon ECS Fargate: sidecar, pidMode=task, SYS_PTRACE. Sees sibling
 * Java container's JVM via /proc; same mechanics.
 *
 * AWS and Kubernetes client beans live here so the rest of the package stays
 * flat — one file per concept, no config folder.
 */
@SpringBootApplication
@EnableScheduling
@ConfigurationPropertiesScan
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @Bean
    S3Client s3Client(@Value("${AWS_REGION:us-east-1}") String region) {
        return S3Client.builder().region(Region.of(region)).build();
    }

    /** Kubernetes client — only on EKS. The ECS Fargate resolver uses no K8s API. */
    @Bean
    @ConditionalOnProperty(prefix = "perf.collector", name = "platform",
        havingValue = "eks", matchIfMissing = true)
    CoreV1Api coreV1Api() throws IOException {
        ApiClient client = ClientBuilder.cluster().build();
        Configuration.setDefaultApiClient(client);
        return new CoreV1Api(client);
    }
}
