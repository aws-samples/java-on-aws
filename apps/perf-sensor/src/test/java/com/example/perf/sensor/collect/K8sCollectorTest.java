package com.example.perf.sensor.collect;

import io.kubernetes.client.openapi.models.V1Container;
import io.kubernetes.client.openapi.models.V1DeploymentSpec;
import io.kubernetes.client.openapi.models.V1ExecAction;
import io.kubernetes.client.openapi.models.V1HTTPGetAction;
import io.kubernetes.client.openapi.models.V1LabelSelector;
import io.kubernetes.client.openapi.models.V1Lifecycle;
import io.kubernetes.client.openapi.models.V1LifecycleHandler;
import io.kubernetes.client.openapi.models.V1ObjectMeta;
import io.kubernetes.client.openapi.models.V1Pod;
import io.kubernetes.client.openapi.models.V1PodCondition;
import io.kubernetes.client.openapi.models.V1PodStatus;
import io.kubernetes.client.openapi.models.V1Probe;
import io.kubernetes.client.openapi.models.V1SleepAction;
import org.junit.jupiter.api.Test;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** The pure extraction rules behind the scored workload facts, without a cluster. */
class K8sCollectorTest {

    private final K8sCollector k8s = new K8sCollector(null, null, "app");

    @Test
    void imageTag() {
        assertThat(K8sCollector.imageTag("123.dkr.ecr.eu-west-1.amazonaws.com/shop:crac")).isEqualTo("crac");
        assertThat(K8sCollector.imageTag("registry:5000/shop")).isEqualTo("latest");
        assertThat(K8sCollector.imageTag("shop")).isEqualTo("latest");
        assertThat(K8sCollector.imageTag(null)).isNull();
    }

    @Test
    void preStopSleep_execOrSleepAction() {
        var exec = new V1Container().lifecycle(new V1Lifecycle().preStop(
            new V1LifecycleHandler().exec(new V1ExecAction().command(List.of("sh", "-c", "sleep 10")))));
        var sleep = new V1Container().lifecycle(new V1Lifecycle().preStop(
            new V1LifecycleHandler().sleep(new V1SleepAction().seconds(7L))));
        assertThat(K8sCollector.preStopSleepSeconds(exec)).isEqualTo(10);
        assertThat(K8sCollector.preStopSleepSeconds(sleep)).isEqualTo(7);
        assertThat(K8sCollector.preStopSleepSeconds(new V1Container())).isZero();
    }

    @Test
    void probeBudgets_useKubernetesDefaults() {
        var explicit = new V1Probe().failureThreshold(5).periodSeconds(10).initialDelaySeconds(3)
            .httpGet(new V1HTTPGetAction().path("/actuator/health/readiness"));
        assertThat(K8sCollector.budget(explicit)).isEqualTo(50);
        assertThat(K8sCollector.initialDelay(explicit)).isEqualTo(3);
        assertThat(K8sCollector.httpPath(explicit)).isEqualTo("/actuator/health/readiness");
        assertThat(K8sCollector.budget(new V1Probe())).isEqualTo(30);     // 3 x 10
        assertThat(K8sCollector.initialDelay(new V1Probe())).isZero();
        assertThat(K8sCollector.budget(null)).isNull();
        assertThat(K8sCollector.httpPath(new V1Probe())).isNull();
    }

    @Test
    void selector_prefersTheDeploymentsOwnMatchLabels() {
        var spec = new V1DeploymentSpec().selector(new V1LabelSelector().matchLabels(Map.of("app.kubernetes.io/name", "shop")));
        assertThat(k8s.selector(spec, "shop")).isEqualTo("app.kubernetes.io/name=shop");
        assertThat(k8s.selector(new V1DeploymentSpec(), "shop")).isEqualTo("app=shop");
        assertThat(k8s.selector(null, "shop")).isEqualTo("app=shop");
    }

    @Test
    void isReady_requiresRunningReadyAndNotTerminating() {
        var ready = pod("Running", "True", null);
        var notReady = pod("Running", "False", null);
        var pending = pod("Pending", "False", null);
        var terminating = pod("Running", "True", OffsetDateTime.now());
        assertThat(K8sCollector.isReady(ready)).isTrue();
        assertThat(K8sCollector.isReady(notReady)).isFalse();
        assertThat(K8sCollector.isReady(pending)).isFalse();
        assertThat(K8sCollector.isReady(terminating)).isFalse();
    }

    @Test
    void readyPodRegex_isNullWithoutPods() {
        assertThat(new K8sCollector.Snapshot(null, null, null, null, null, null, null, List.of()).readyPodRegex()).isNull();
        assertThat(new K8sCollector.Snapshot(null, null, null, null, null, null, null, List.of("a", "b")).readyPodRegex()).isEqualTo("a|b");
    }

    private static V1Pod pod(String phase, String ready, OffsetDateTime deletion) {
        return new V1Pod()
            .metadata(new V1ObjectMeta().name("p").deletionTimestamp(deletion))
            .status(new V1PodStatus().phase(phase)
                .conditions(List.of(new V1PodCondition().type("Ready").status(ready))));
    }
}
