package com.unicorn.jvm;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

// Java 16 Records (JEP 395) - immutable DTOs
@JsonIgnoreProperties(ignoreUnknown = true)
public record AlertWebhookRequest(
    @JsonProperty("alerts") List<Alert> alerts
) {
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Alert(
        @JsonProperty("labels") Labels labels
    ) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Labels(
        @JsonProperty("pod") String pod,
        @JsonProperty("instance") String instance
    ) {
        public String podIp() {
            return instance != null ? instance.split(":")[0] : null;
        }
    }
}
