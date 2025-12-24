package com.unicorn.jvm;

import net.jqwik.api.*;
import net.jqwik.api.constraints.*;

// Property tests for alert validation - pod and podIp must be non-blank
class AlertValidationPropertyTest {

    @Property(tries = 100)
    void validAlertHasNonBlankPodAndPodIp(
        @ForAll @StringLength(min = 1, max = 50) @AlphaChars String pod,
        @ForAll @IntRange(min = 1, max = 255) int ip1,
        @ForAll @IntRange(min = 0, max = 255) int ip2,
        @ForAll @IntRange(min = 0, max = 255) int ip3,
        @ForAll @IntRange(min = 1, max = 255) int ip4,
        @ForAll @IntRange(min = 1, max = 65535) int port
    ) {
        String ip = ip1 + "." + ip2 + "." + ip3 + "." + ip4;
        String instance = ip + ":" + port;
        var labels = new AlertWebhookRequest.Labels(pod, instance);
        var alert = new AlertWebhookRequest.Alert(labels);

        assert isValidAlert(alert) : "Alert with valid pod and instance should be valid";
        assert labels.podIp() != null : "podIp should not be null";
        assert !labels.podIp().isBlank() : "podIp should not be blank";
    }

    @Property(tries = 100)
    void alertWithNullPodIsInvalid(
        @ForAll @IntRange(min = 1, max = 255) int ip1,
        @ForAll @IntRange(min = 0, max = 255) int ip2,
        @ForAll @IntRange(min = 0, max = 255) int ip3,
        @ForAll @IntRange(min = 1, max = 255) int ip4,
        @ForAll @IntRange(min = 1, max = 65535) int port
    ) {
        String ip = ip1 + "." + ip2 + "." + ip3 + "." + ip4;
        String instance = ip + ":" + port;
        var labels = new AlertWebhookRequest.Labels(null, instance);
        var alert = new AlertWebhookRequest.Alert(labels);

        assert !isValidAlert(alert) : "Alert with null pod should be invalid";
    }

    @Property(tries = 100)
    void alertWithBlankPodIsInvalid(
        @ForAll("blankStrings") String blankPod,
        @ForAll @IntRange(min = 1, max = 255) int ip1,
        @ForAll @IntRange(min = 0, max = 255) int ip2,
        @ForAll @IntRange(min = 0, max = 255) int ip3,
        @ForAll @IntRange(min = 1, max = 255) int ip4,
        @ForAll @IntRange(min = 1, max = 65535) int port
    ) {
        String ip = ip1 + "." + ip2 + "." + ip3 + "." + ip4;
        String instance = ip + ":" + port;
        var labels = new AlertWebhookRequest.Labels(blankPod, instance);
        var alert = new AlertWebhookRequest.Alert(labels);

        assert !isValidAlert(alert) : "Alert with blank pod should be invalid";
    }

    @Property(tries = 100)
    void alertWithNullInstanceIsInvalid(
        @ForAll @StringLength(min = 1, max = 50) @AlphaChars String pod
    ) {
        var labels = new AlertWebhookRequest.Labels(pod, null);
        var alert = new AlertWebhookRequest.Alert(labels);

        assert !isValidAlert(alert) : "Alert with null instance should be invalid";
        assert labels.podIp() == null : "podIp should be null when instance is null";
    }

    @Property(tries = 100)
    void alertWithNullLabelsIsInvalid() {
        var alert = new AlertWebhookRequest.Alert(null);
        assert !isValidAlert(alert) : "Alert with null labels should be invalid";
    }

    // --- Providers ---

    @Provide
    Arbitrary<String> blankStrings() {
        return Arbitraries.of("", " ", "  ", "\t", "\n", "   \t\n  ");
    }

    private boolean isValidAlert(AlertWebhookRequest.Alert alert) {
        if (alert == null || alert.labels() == null) {
            return false;
        }
        var labels = alert.labels();
        return labels.pod() != null && !labels.pod().isBlank()
            && labels.podIp() != null && !labels.podIp().isBlank();
    }
}
