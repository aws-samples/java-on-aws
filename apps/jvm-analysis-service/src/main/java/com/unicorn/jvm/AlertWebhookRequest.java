package com.unicorn.jvm;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public class AlertWebhookRequest {
    
    @JsonProperty("alerts")
    private List<Alert> alerts;

    public List<Alert> getAlerts() {
        return alerts;
    }

    public void setAlerts(List<Alert> alerts) {
        this.alerts = alerts;
    }

    public static class Alert {
        @JsonProperty("labels")
        private Labels labels;

        public Labels getLabels() {
            return labels;
        }

        public void setLabels(Labels labels) {
            this.labels = labels;
        }
    }

    public static class Labels {
        @JsonProperty("pod")
        private String pod;

        @JsonProperty("instance")
        private String instance;

        public String getPod() {
            return pod;
        }

        public void setPod(String pod) {
            this.pod = pod;
        }

        public String getInstance() {
            return instance;
        }

        public void setInstance(String instance) {
            this.instance = instance;
        }

        public String getPodIp() {
            return instance != null ? instance.split(":")[0] : null;
        }
    }
}