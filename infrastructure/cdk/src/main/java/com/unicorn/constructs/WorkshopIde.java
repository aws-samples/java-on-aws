package com.unicorn.constructs;

import com.unicorn.constructs.InfrastructureCore;
import com.unicorn.constructs.VSCodeIde;
import com.unicorn.constructs.VSCodeIdeProps;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.ec2.InstanceClass;
import software.amazon.awscdk.services.ec2.InstanceSize;
import software.amazon.awscdk.services.ec2.InstanceType;
import software.amazon.awscdk.services.ec2.SecurityGroup;

import java.util.Arrays;
import java.util.List;

import software.amazon.awscdk.services.iam.Role;
import software.constructs.Construct;

public class WorkshopIde extends Construct {

    private final InfrastructureCore infrastructureCore;

    private final Role ideRole;
    private final VSCodeIdeProps ideProps;
    private final SecurityGroup additionalSG;

    private final String bootstrapScript = """
        date

        echo '=== Clone Git repository ==='
        sudo -H -u ec2-user bash -c "git clone https://github.com/aws-samples/java-on-aws ~/java-on-aws/"
        sudo -H -u ec2-user bash -c "cd ~/java-on-aws && git checkout refactoring"

        echo '=== Setup IDE ==='
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/setup-ide.sh"

        echo '=== Additional Setup ==='
        sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/ws-app-setup.sh"
        # sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/ws-eks-setup.sh"
        # sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/ws-containerize.sh"
        # sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/ws-eks-deploy-app.sh"
        # sudo -H -i -u ec2-user bash -c "~/java-on-aws/infrastructure/scripts/ws-eks-cleanup-app.sh"
        """;

    public WorkshopIde(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore,
        final SecurityGroup additionalSG) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;

        this.additionalSG = additionalSG;

        ideRole = createIdeRole();
        ideProps = createIdeProps();
        var ideInstance = createIdeInstance();
    }

    private VSCodeIdeProps createIdeProps() {
        var props = new VSCodeIdeProps();
        props.setBootstrapScript(bootstrapScript);
        props.setVpc(infrastructureCore.getVpc());
        props.setRole(ideRole);
        props.setEnableAppSecurityGroup(true);
        props.setInstanceType(InstanceType.of(InstanceClass.M5, InstanceSize.XLARGE));
        if (additionalSG != null) {
            props.setAdditionalSecurityGroups(List.of(additionalSG));
        }
        props.setExtensions(Arrays.asList(
            // "amazonwebservices.aws-toolkit-vscode",
            // "amazonwebservices.amazon-q-vscode",
            "ms-azuretools.vscode-docker",
            "ms-kubernetes-tools.vscode-kubernetes-tools",
            "vscjava.vscode-java-pack"
        ));
        return props;
    }

    private Role createIdeRole() {
        var role = Role.Builder.create(this, "IdeRole")
            .assumedBy(new ServicePrincipal("ec2.amazonaws.com"))
            .roleName("workshop-ide-user")
            .build();
        return role;
    }

    public Role getIdeRole() {
        return ideRole;
    }

    private VSCodeIde createIdeInstance() {
        var instance = new VSCodeIde(this, "VSCodeIde", ideProps);
        return instance;
    }
}
