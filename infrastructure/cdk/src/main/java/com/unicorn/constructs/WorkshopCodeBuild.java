package com.unicorn.constructs;

import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.Role;
import software.constructs.Construct;

import com.unicorn.constructs.CodeBuildResource.CodeBuildCustomResourceProps;

import java.util.Arrays;

public class WorkshopCodeBuild extends Construct {

    private final InfrastructureCore infrastructureCore;

    private final Role codeBuildRole;
    private final CodeBuildCustomResourceProps codeBuildProps;
    private final CodeBuildResource codeBuildResource;

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

    public WorkshopCodeBuild(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;

        codeBuildRole = createCodeBuildRole();
        codeBuildProps = createCodeBuildProps();
        codeBuildResource = createCodeBuildResource();
    }

    private CodeBuildCustomResourceProps createCodeBuildProps() {
        var props = new CodeBuildCustomResourceProps();
        props.setBuildspec(buildspec);
        props.setRole(codeBuildRole);
        props.setVpc(infrastructureCore.getVpc());
        props.setAdditionalIamPolicies(Arrays.asList(
        ManagedPolicy.fromAwsManagedPolicyName("AdministratorAccess")));
        return props;
    }

    private Role createCodeBuildRole() {
        var role = Role.Builder.create(this, "WorkshopCodeBuildRole")
            .assumedBy(new ServicePrincipal("codebuild.amazonaws.com"))
            .roleName("unicornstore-codebuild")
            .build();
        return role;
    }

    public Role getCodeBuildRole() {
        return codeBuildRole;
    }

    private CodeBuildResource createCodeBuildResource() {
        var resource = new CodeBuildResource(this, "WorkshopCodeBuildResource", codeBuildProps);
        return resource;
    }

    public CodeBuildResource getCodeBuildResource() {
        return codeBuildResource;
    }
}
