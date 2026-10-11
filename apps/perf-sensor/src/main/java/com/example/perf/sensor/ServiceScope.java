package com.example.perf.sensor;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * The workloads this sensor answers for ({@code SENSOR_SERVICES}, comma-separated), checked at
 * the one boundary every REST and MCP call passes. Two reasons:
 * <ul>
 *   <li>Classification: a thread counts as request path when {@code REQUEST_PACKAGE} is on its
 *       stack. That package belongs to the configured workloads; another workload's stacks
 *       would all be skipped and its blocking counts would read 0, which looks like "nothing
 *       blocks". Refusing it is the honest answer.</li>
 *   <li>Query safety: the service name goes into PromQL and Pyroscope label matchers. Only a
 *       Kubernetes DNS label (RFC 1123: lowercase alphanumerics and '-', at most 63) can be a
 *       namespace and Deployment name, so nothing else reaches a query.</li>
 * </ul>
 */
@Component
public class ServiceScope {

    private static final Pattern DNS_LABEL = Pattern.compile("[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?");

    private final Set<String> services;

    public ServiceScope(@Value("${SENSOR_SERVICES}") String services) {
        this.services = Arrays.stream(services == null ? new String[0] : services.split(","))
            .map(String::strip).filter(s -> !s.isEmpty()).collect(Collectors.toUnmodifiableSet());
        if (this.services.isEmpty()) {
            throw new IllegalStateException("SENSOR_SERVICES must name the workloads this sensor serves (e.g. shop)");
        }
        this.services.forEach(ServiceScope::requireDnsLabel);
    }

    public static ServiceScope of(String... services) {
        return new ServiceScope(String.join(",", services));
    }

    /** Throws IllegalArgumentException unless {@code service} is a configured workload. */
    public void check(String service) {
        requireDnsLabel(service);
        if (!services.contains(service)) {
            throw new IllegalArgumentException("service '" + service + "' is not served by this sensor (SENSOR_SERVICES="
                + String.join(",", services.stream().sorted().toList())
                + "): its request package is unknown, so blocking counts would read 0");
        }
    }

    private static void requireDnsLabel(String service) {
        if (service == null || !DNS_LABEL.matcher(service).matches()) {
            throw new IllegalArgumentException("service must be a Kubernetes name (RFC 1123 label), was '" + service + "'");
        }
    }
}
