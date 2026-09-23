package com.example.perf.sensor.collect;

import io.kubernetes.client.openapi.ApiClient;
import io.kubernetes.client.openapi.apis.AppsV1Api;
import io.kubernetes.client.openapi.apis.CoreV1Api;
import io.kubernetes.client.util.ClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Read-only Kubernetes API client wiring. Uses the in-cluster service-account token when
 * running as a pod (the {@code perf-sensor} ClusterRole grants get/list/watch on
 * deployments, pods and pods/log — no write verbs). Falls back to an unconnected
 * {@link ApiClient} outside a cluster so the Spring context still starts; collectors
 * degrade to null facts when the API is unreachable.
 */
@Configuration
public class K8sClientConfig {

    private static final Logger logger = LoggerFactory.getLogger(K8sClientConfig.class);

    @Bean
    ApiClient k8sApiClient() {
        try {
            return ClientBuilder.cluster().build();
        } catch (Exception e) {
            logger.warn("Not in-cluster ({}); K8s facts will be unavailable", e.getMessage());
            return new ApiClient();
        }
    }

    @Bean
    CoreV1Api coreV1Api(ApiClient client) {
        return new CoreV1Api(client);
    }

    @Bean
    AppsV1Api appsV1Api(ApiClient client) {
        return new AppsV1Api(client);
    }
}
