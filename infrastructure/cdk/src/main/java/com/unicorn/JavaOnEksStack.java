package com.unicorn;

import java.util.Arrays;

import com.unicorn.constructs.WorkshopVpc;
import com.unicorn.constructs.VSCodeIde;
import com.unicorn.constructs.VSCodeIde.VSCodeIdeProps;
import com.unicorn.constructs.CodeBuildResource;
import com.unicorn.constructs.CodeBuildResource.CodeBuildResourceProps;
import com.unicorn.constructs.EksCluster;
import com.unicorn.core.InfrastructureCore;
import com.unicorn.core.InfrastructureContainers;
import com.unicorn.core.InfrastructureEks;
import com.unicorn.core.InfrastructureJvmAnalysis;
import com.unicorn.core.DatabaseSetup;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.constructs.Construct;

import software.amazon.awscdk.DefaultStackSynthesizer;
import software.amazon.awscdk.DefaultStackSynthesizerProps;

public class JavaOnEksStack extends Stack {

    private final String bootstrapScript = """
        date

        echo '=== Clone Git repository ==='
        sudo -H -u ec2-user bash -c "git clone https://github.com/aws-samples/java-on-aws ~/java-on-aws/"
        sudo -H -u ec2-user bash -c "cd ~/java-on-aws && git checkout riv25-eks"

        echo '=== Setup IDE ==='
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/ide.sh"

        echo '=== Additional Setup ==='
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/app.sh"
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/eks.sh"

        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/monitoring.sh"
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/java-on-eks/1-app.sh"
        """;

    private final String buildspec = """
        version: 0.2
        env:
            shell: bash
        phases:
            install:
                commands:
                    - |
                        aws --version
            build:
                commands:
                    - |
                        # Resolution for when creating the first service in the account
                        aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>/dev/null || true
                        aws iam create-service-linked-role --aws-service-name apprunner.amazonaws.com 2>/dev/null || true
                        aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com 2>/dev/null || true
        """;

    public JavaOnEksStack(final Construct scope, final String id) {
        // super(scope, id, props);
        super(scope, id, StackProps.builder()
        .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
            .generateBootstrapVersionRule(false)  // This disables the bootstrap version parameter
            .build()))
        .build());

        // Create VPC
        var vpc = new WorkshopVpc(this, "UnicornStoreVpc", "unicornstore-vpc").getVpc();

        // Create Workshop IDE
        var ideProps = new VSCodeIdeProps();
            ideProps.setBootstrapScript(bootstrapScript);
            ideProps.setVpc(vpc);
            ideProps.setInstanceName("unicornstore-ide");
            ideProps.setInstanceType(InstanceType.of(InstanceClass.M5, InstanceSize.XLARGE));
            ideProps.setExtensions(Arrays.asList(
                // "amazonwebservices.aws-toolkit-vscode",
                // "amazonwebservices.amazon-q-vscode",
                "vscjava.vscode-java-pack",
                // "shardulm94.trailing-spaces",
                "ms-kubernetes-tools.vscode-kubernetes-tools",
                "ms-azuretools.vscode-docker"
            ));
        var ide = new VSCodeIde(this, "UnicornStoreIde", ideProps);
        var ideRole = ideProps.getRole();
        var ideInternalSecurityGroup = ide.getIdeInternalSecurityGroup();

        // Create Core infrastructure
        var infrastructureCore = new InfrastructureCore(this, "InfrastructureCore", vpc);
        // var accountId = Stack.of(this).getAccount();

        // Create additional infrastructure for Containers modules of Java on AWS Immersion Day
        new InfrastructureContainers(this, "InfrastructureContainers", infrastructureCore);
        new InfrastructureEks(this, "InfrastructureEks", infrastructureCore);

        // Create EKS cluster for the workshop
        var eksCluster = new EksCluster(this, "UnicornStoreEksCluster", "unicorn-store", "1.33",
            vpc, ideInternalSecurityGroup);
        eksCluster.createAccessEntry(ideRole.getRoleArn(), "unicorn-store", "unicornstore-ide-user");

        // Execute Database setup
        var databaseSetup = new DatabaseSetup(this, "UnicornStoreDatabaseSetup", infrastructureCore);
        databaseSetup.getNode().addDependency(infrastructureCore.getDatabase());

        // Create Workshop CodeBuild
        var codeBuildProps = new CodeBuildResourceProps();
        codeBuildProps.setProjectName("unicornstore-codebuild");
        codeBuildProps.setBuildspec(buildspec);
        codeBuildProps.setVpc(vpc);
        codeBuildProps.setAdditionalIamPolicies(Arrays.asList(
            ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess")));
        new CodeBuildResource(this, "UnicornStoreCodeBuild", codeBuildProps);

        // Create JVM monitoring infrastructure with Lambda thread dump
        new InfrastructureJvmAnalysis(this, "InfrastructureJvmAnalysis", infrastructureCore);
    }
}
