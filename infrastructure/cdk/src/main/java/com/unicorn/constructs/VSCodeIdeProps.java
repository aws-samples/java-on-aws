package com.unicorn.constructs;

import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.ec2.IMachineImage;
import software.amazon.awscdk.services.ec2.MachineImage;
import software.amazon.awscdk.services.ec2.IVpc;
import software.amazon.awscdk.services.ec2.ISecurityGroup;
import software.amazon.awscdk.services.iam.IManagedPolicy;
import software.amazon.awscdk.services.iam.Role;

import java.util.ArrayList;
import java.util.List;

public class VSCodeIdeProps {
    private String instanceName = "IdeInstance";
    private String bootstrapScript = "echo bootstrapScript was not provided";
    private int diskSize = 50;
    private IVpc vpc;
    private String availabilityZone;
    private IMachineImage machineImage = MachineImage.latestAmazonLinux2023();
    private InstanceType instanceType = InstanceType.of(InstanceClass.T3, InstanceSize.MEDIUM);
    private String codeServerVersion = "4.96.2";
    private List<IManagedPolicy> additionalIamPolicies = new ArrayList<>();
    private List<ISecurityGroup> additionalSecurityGroups = new ArrayList<>();
    private int bootstrapTimeoutMinutes = 30;
    private boolean enableGitea = false;
    private String splashUrl = "";
    private String readmeUrl = "";
    private String environmentContentsZip = "";
    private List<String> extensions = new ArrayList<>();
    private boolean terminalOnStartup = true;
    private Role role;
    private String additionalIamPolicyPath = "/iam-policy.json";
    private boolean enableAppSecurityGroup = false;
    private int appPort = 8080;

    public String getInstanceName() { return instanceName; }
    public void setInstanceName(String instanceName) { this.instanceName = instanceName; }

    public String getBootstrapScript() { return bootstrapScript; }
    public void setBootstrapScript(String bootstrapScript) { this.bootstrapScript = bootstrapScript; }

    public int getDiskSize() { return diskSize; }
    public void setDiskSize(int diskSize) { this.diskSize = diskSize; }

    public IVpc getVpc() { return vpc; }
    public void setVpc(IVpc vpc) { this.vpc = vpc; }

    public String getAvailabilityZone() { return availabilityZone; }
    public void setAvailabilityZone(String availabilityZone) { this.availabilityZone = availabilityZone; }

    public IMachineImage getMachineImage() { return machineImage; }
    public void setMachineImage(IMachineImage machineImage) { this.machineImage = machineImage; }

    public InstanceType getInstanceType() { return instanceType; }
    public void setInstanceType(InstanceType instanceType) { this.instanceType = instanceType; }

    public String getCodeServerVersion() { return codeServerVersion; }
    public void setCodeServerVersion(String codeServerVersion) { this.codeServerVersion = codeServerVersion; }

    public List<IManagedPolicy> getAdditionalIamPolicies() { return additionalIamPolicies; }
    public void setAdditionalIamPolicies(List<IManagedPolicy> additionalIamPolicies) { this.additionalIamPolicies = additionalIamPolicies; }

    public List<ISecurityGroup> getAdditionalSecurityGroups() { return additionalSecurityGroups; }
    public void setAdditionalSecurityGroups(List<ISecurityGroup> additionalSecurityGroups) { this.additionalSecurityGroups = additionalSecurityGroups; }

    public int getBootstrapTimeoutMinutes() { return bootstrapTimeoutMinutes; }
    public void setBootstrapTimeoutMinutes(int bootstrapTimeoutMinutes) { this.bootstrapTimeoutMinutes = bootstrapTimeoutMinutes; }

    public boolean isEnableGitea() { return enableGitea; }
    public void setEnableGitea(boolean enableGitea) { this.enableGitea = enableGitea; }

    public String getSplashUrl() { return splashUrl; }
    public void setSplashUrl(String splashUrl) { this.splashUrl = splashUrl; }

    public String getReadmeUrl() { return readmeUrl; }
    public void setReadmeUrl(String readmeUrl) { this.readmeUrl = readmeUrl; }

    public String getEnvironmentContentsZip() { return environmentContentsZip; }
    public void setEnvironmentContentsZip(String environmentContentsZip) { this.environmentContentsZip = environmentContentsZip; }

    public List<String> getExtensions() { return extensions; }
    public void setExtensions(List<String> extensions) { this.extensions = extensions; }

    public boolean isTerminalOnStartup() { return terminalOnStartup; }
    public void setTerminalOnStartup(boolean terminalOnStartup) { this.terminalOnStartup = terminalOnStartup; }

    public Role getRole() { return role; }
    public void setRole(Role role) { this.role = role; }

    public String getAdditionalIamPolicyPath() { return additionalIamPolicyPath; }
    public void setAdditionalIamPolicyPath(String additionalIamPolicyPath) { this.additionalIamPolicyPath = additionalIamPolicyPath; }

    public boolean isEnableAppSecurityGroup() { return enableAppSecurityGroup; }
    public void setEnableAppSecurityGroup(boolean enableAppSecurityGroup) { this.enableAppSecurityGroup = enableAppSecurityGroup; }

    public int getAppPort() { return appPort; }
    public void setAppPort(int appPort) { this.appPort = appPort; }
}
