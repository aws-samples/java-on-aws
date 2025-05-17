package com.unicorn;

import java.util.Arrays;

import com.unicorn.constructs.WorkshopVpc;
import com.unicorn.constructs.VSCodeIde;
import com.unicorn.constructs.VSCodeIde.VSCodeIdeProps;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.constructs.Construct;

import software.amazon.awscdk.DefaultStackSynthesizer;
import software.amazon.awscdk.DefaultStackSynthesizerProps;

public class IdeGiteaStack extends Stack {

    private final String bootstrapScript = """
        date

        echo '=== Clone Git repository ==='
        sudo -H -u ec2-user bash -c "git clone https://github.com/aws-samples/java-on-aws ~/java-on-aws/"
        # sudo -H -u ec2-user bash -c "cd ~/java-on-aws && git checkout refactoring"

        echo '=== Setup IDE ==='
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/ide.sh"
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/idp.sh"
        """;

    public IdeGiteaStack(final Construct scope, final String id) {
        // super(scope, id, props);
        super(scope, id, StackProps.builder()
        .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
            .generateBootstrapVersionRule(false)  // This disables the bootstrap version parameter
            .build()))
        .build());

        // Create VPC
        var vpc = new WorkshopVpc(this, "IdeVpc", "ide-vpc").getVpc();

        // Create Workshop IDE
        var ideProps = new VSCodeIdeProps();
            ideProps.setBootstrapScript(bootstrapScript);
            ideProps.setVpc(vpc);
            ideProps.setInstanceName("ide");
            ideProps.setInstanceType(InstanceType.of(InstanceClass.M5, InstanceSize.XLARGE));
            ideProps.setExtensions(Arrays.asList(
                // "amazonwebservices.aws-toolkit-vscode",
                // "amazonwebservices.amazon-q-vscode",
                "ms-azuretools.vscode-docker",
                "ms-kubernetes-tools.vscode-kubernetes-tools",
                "vscjava.vscode-java-pack"
            ));
            ideProps.setAppPort(8080);
            ideProps.setEnableGitea(true);
        var ide = new VSCodeIde(this, "VSCodeIdeGitea", ideProps);
        var ideRole = ideProps.getRole();
        ideRole.addManagedPolicy(ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess"));
    }
}
