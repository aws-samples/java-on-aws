package com.unicorn;

import java.util.Arrays;

import com.unicorn.constructs.WorkshopVpc;
import com.unicorn.constructs.VSCodeIde;
import com.unicorn.constructs.VSCodeIde.VSCodeIdeProps;
import com.unicorn.constructs.CodeBuildResource;
import com.unicorn.constructs.CodeBuildResource.CodeBuildResourceProps;
import com.unicorn.constructs.EksCluster;
import com.unicorn.core.*;

import software.amazon.awscdk.*;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.constructs.Construct;

public class UnicornStoreStack extends Stack {

    private final String bootstrapScript = """
        date

        echo '=== Clone Git repository ===\n'
        sudo -H -u ec2-user bash -c "git clone https://github.com/aws-samples/java-on-aws ~/java-on-aws/"
        sudo -H -u ec2-user bash -c "cd ~/java-on-aws && git checkout bedrock-tda"

        echo '=== Setup IDE ===\n'
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/ide.sh"

        echo '=== Additional Setup ===\n'
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/app.sh"
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/eks.sh"

        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/monitoring.sh"
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup/monitoring-jvm.sh"
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

    public UnicornStoreStack(final Construct scope, final String id) {
        // super(scope, id, props);
        super(scope, id, StackProps.builder()
        .synthesizer(new DefaultStackSynthesizer(DefaultStackSynthesizerProps.builder()
            .generateBootstrapVersionRule(false)  // This disables the bootstrap version parameter
            .build()))
        .build());

        // Create VPC
        var vpc = new WorkshopVpc(this, "UnicornStoreVpc", "unicornstore-vpc").getVpc();

        // Create VSCode IDE
        var ideProps = new VSCodeIdeProps();
            ideProps.setBootstrapScript(bootstrapScript);
            ideProps.setVpc(vpc);
            ideProps.setInstanceName("unicornstore-ide");
            ideProps.setInstanceType(InstanceType.of(InstanceClass.M5, InstanceSize.XLARGE));
            ideProps.setExtensions(Arrays.asList(
                // "amazonwebservices.aws-toolkit-vscode",
                // "amazonwebservices.amazon-q-vscode",
                "vscjava.vscode-java-pack",
                "ms-kubernetes-tools.vscode-kubernetes-tools",
                "ms-azuretools.vscode-docker"
            ));
        var ide = new VSCodeIde(this, "UnicornStoreIde", ideProps);
        var ideRole = ideProps.getRole();
        var ideInternalSecurityGroup = ide.getIdeInternalSecurityGroup();

        // Create EKS cluster for the workshop
        var eksCluster = new EksCluster(this, "UnicornStoreEksCluster", "unicorn-store", "1.33",
                vpc, ideInternalSecurityGroup);
        eksCluster.createAccessEntry(ideRole.getRoleArn(), "unicorn-store", "unicornstore-ide-user");

        // Create Core infrastructure
        var infrastructureCore = new InfrastructureCore(this, "InfrastructureCore", vpc);
        // var accountId = Stack.of(this).getAccount();

        // Create additional infrastructure for Containers modules of Java on AWS Immersion Day
        new InfrastructureContainers(this, "InfrastructureContainers", infrastructureCore);
        new InfrastructureEks(this, "InfrastructureEks", infrastructureCore);

        // Create JVM monitoring infrastructure with Lambda thread dump
        new InfrastructureMonitoringJVM(this, "InfrastructureMonitoringJVM", infrastructureCore.getWorkshopBucket(), eksCluster, vpc);

        // Execute Database setup
        var databaseSetup = new DatabaseSetup(this, "UnicornStoreDatabaseSetup", infrastructureCore);
        databaseSetup.getNode().addDependency(infrastructureCore.getDatabase());

        // Create UnicornStoreSpringLambda
        new UnicornStoreSpringLambda(this, "UnicornStoreSpringLambda", infrastructureCore);

        // Create Workshop CodeBuild
        var codeBuildProps = new CodeBuildResourceProps();
        codeBuildProps.setProjectName("unicornstore-codebuild");
        codeBuildProps.setBuildspec(buildspec);
        codeBuildProps.setVpc(vpc);
        codeBuildProps.setAdditionalIamPolicies(Arrays.asList(
            ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess")));
        new CodeBuildResource(this, "UnicornStoreCodeBuild", codeBuildProps);
    }
}
