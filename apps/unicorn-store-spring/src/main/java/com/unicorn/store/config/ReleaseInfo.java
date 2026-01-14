package com.unicorn.store.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class ReleaseInfo {

    @Value("${release.version:local}")
    private String version;

    @Value("${release.deployment-time:N/A}")
    private String deploymentTime;

    @Value("${release.commit:local}")
    private String commit;

    @Value("${release.pod:unknown}")
    private String pod;

    public String getVersion() {
        return version;
    }

    public String getDeploymentTime() {
        return deploymentTime;
    }

    public String getCommit() {
        return commit;
    }

    public String getPod() {
        return pod;
    }
}
