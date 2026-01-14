package com.unicorn.store.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

@Component
public class ReleaseInfo {

    private static final String GITHUB_REPO_URL = "https://github.com/alexsoto-harness/java-on-aws";
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter
            .ofPattern("yyyy-MM-dd HH:mm:ss z")
            .withZone(ZoneId.of("America/New_York"));

    @Value("${release.version:local}")
    private String version;

    @Value("${release.deployment-time:N/A}")
    private String deploymentTime;

    @Value("${release.commit:local}")
    private String commit;

    @Value("${release.pod:unknown}")
    private String pod;

    @Value("${release.environment:local}")
    private String environment;

    public String getVersion() {
        return version;
    }

    public String getDeploymentTime() {
        if (deploymentTime == null || deploymentTime.equals("N/A") || deploymentTime.equals("local")) {
            return deploymentTime;
        }
        try {
            long timestamp = Long.parseLong(deploymentTime);
            return FORMATTER.format(Instant.ofEpochMilli(timestamp));
        } catch (NumberFormatException e) {
            return deploymentTime;
        }
    }

    public String getCommit() {
        return commit;
    }

    public String getCommitUrl() {
        if (commit == null || commit.equals("local")) {
            return null;
        }
        return GITHUB_REPO_URL + "/commit/" + commit;
    }

    public String getPod() {
        return pod;
    }

    public String getEnvironment() {
        if (environment == null) {
            return "Unknown";
        }
        return switch (environment) {
            case "eksparsonunicorndev" -> "AWS NonProd";
            case "eksparsonunicornprod" -> "AWS Prod";
            default -> environment;
        };
    }

    public String getDeploymentType() {
        if (pod == null || pod.equals("unknown")) {
            return "Unknown";
        }
        String podLower = pod.toLowerCase();
        if (podLower.contains("blue")) {
            return "Blue/Green : Blue";
        } else if (podLower.contains("green")) {
            return "Blue/Green : Green";
        } else if (podLower.contains("canary")) {
            return "Canary";
        }
        return "Rolling";
    }
}
