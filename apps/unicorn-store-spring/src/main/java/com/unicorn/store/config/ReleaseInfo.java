package com.unicorn.store.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;

@Component
public class ReleaseInfo {

    private static final String GITHUB_REPO_URL = "https://github.com/alexsoto-harness/java-on-aws";
    private static final ZoneId EST_ZONE = ZoneId.of("America/New_York");
    private static final DateTimeFormatter OUTPUT_FORMATTER = DateTimeFormatter
            .ofPattern("yyyy-MM-dd hh:mm:ss a z")
            .withZone(EST_ZONE);
    private static final DateTimeFormatter ISO_PARSER = DateTimeFormatter.ISO_DATE_TIME;

    @Value("${release.version:local}")
    private String version;

    @Value("${release.version-url:}")
    private String versionUrl;

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

    public String getVersionUrl() {
        if (versionUrl == null || versionUrl.isEmpty()) {
            return null;
        }
        return versionUrl;
    }

    public String getDeploymentTime() {
        if (deploymentTime == null || deploymentTime.equals("N/A") || deploymentTime.equals("local")) {
            return deploymentTime;
        }
        try {
            ZonedDateTime zdt = ZonedDateTime.parse(deploymentTime, ISO_PARSER);
            return OUTPUT_FORMATTER.format(zdt.withZoneSameInstant(EST_ZONE));
        } catch (Exception e) {
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
        String envLower = environment.toLowerCase().replace("-", "");
        return switch (envLower) {
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
            return "Blue";
        } else if (podLower.contains("green")) {
            return "Green";
        } else if (podLower.contains("canary")) {
            return "Canary";
        }
        return "Rolling";
    }

    public String getDeploymentTypeColor() {
        String type = getDeploymentType();
        return switch (type) {
            case "Blue" -> "text-primary";
            case "Green" -> "text-success";
            case "Canary" -> "text-warning";
            default -> "";
        };
    }

    public String getDeploymentTypeLabel() {
        String type = getDeploymentType();
        return switch (type) {
            case "Blue", "Green" -> "Blue/Green";
            case "Canary", "Rolling" -> "Progressive";
            default -> "Progressive";
        };
    }

    public String getEnvironmentShort() {
        String env = getEnvironment();
        if (env.contains("NonProd")) {
            return "NonProd";
        } else if (env.contains("Prod")) {
            return "Prod";
        }
        return "Local";
    }

    public String getPageTitle() {
        return getEnvironmentShort() + " " + getDeploymentType();
    }
}
