package com.unicorn.constructs.eks;

import com.unicorn.core.InfrastructureStack;

import software.amazon.awscdk.services.eks.Cluster;
import software.amazon.awscdk.Duration;
import software.amazon.awscdk.services.ec2.Port;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.ecr.IRepository;
import software.amazon.awscdk.services.ecr.Repository;
import software.amazon.awscdk.services.codebuild.PipelineProject;
import software.amazon.awscdk.services.codebuild.BuildSpec;
import software.amazon.awscdk.services.codebuild.ComputeType;
import software.amazon.awscdk.services.codebuild.LinuxBuildImage;
import software.amazon.awscdk.services.codebuild.BuildEnvironment;
import software.amazon.awscdk.services.codebuild.BuildEnvironmentVariable;
import software.amazon.awscdk.services.codepipeline.Pipeline;
import software.amazon.awscdk.services.codepipeline.Artifact;
import software.amazon.awscdk.services.codepipeline.StageProps;
import software.amazon.awscdk.services.codepipeline.actions.CodeBuildAction;
import software.amazon.awscdk.services.codepipeline.actions.EcrSourceAction;

import software.constructs.Construct;

import java.util.List;
import java.util.Map;

public class UnicornStoreEKSaddPipeline extends Construct {

    public UnicornStoreEKSaddPipeline(final Construct scope, final String id,
            InfrastructureStack infrastructureStack, Cluster cluster, final String projectName) {
        super(scope, id);

        // deployment construct which listens to ECR events, then deploys to the
        // existing service.
        IRepository ecr = Repository.fromRepositoryName(scope, projectName + "-ecr", projectName);

        Artifact sourceOuput = Artifact.artifact(projectName + "-ecr-artifact");

        EcrSourceAction sourceAction = EcrSourceAction.Builder.create()
                .actionName("source-ecr")
                .repository(ecr)
                .imageTag("latest")
                .output(sourceOuput)
                .variablesNamespace("ecrvars")
                .build();

        PipelineProject codeBuild = PipelineProject.Builder.create(scope, projectName + "-codebuild-deploy-eks")
                .projectName(projectName + "-deploy-eks")
                .vpc(infrastructureStack.getVpc())
                .environment(BuildEnvironment.builder()
                        .privileged(true)
                        .computeType(ComputeType.SMALL)
                        .buildImage(LinuxBuildImage.AMAZON_LINUX_2_4)
                        .build())
                .buildSpec(BuildSpec.fromObject(Map.of(
                        "version", "0.2",
                        "phases", Map.of(
                                "build", Map.of(
                                        "commands", List.of(
                                                "cat imageDetail.json",
                                                "IMAGE_DETAIL_URI=$(cat imageDetail.json | python -c \"import sys, json; print(json.load(sys.stdin)['ImageURI'].split('@')[0])\")",
                                                "IMAGE_DETAIL_TAG=$(cat imageDetail.json | python -c \"import sys, json; a=json.load(sys.stdin)['ImageTags']; a.sort(); print(a[0])\")",
                                                "echo $IMAGE_DETAIL_URI:$IMAGE_DETAIL_TAG",
                                                "echo IMAGE_URI=$IMAGE_URI",
                                                "echo IMAGE_TAG=$IMAGE_TAG",
                                                "echo \"spec:\">> patch.yml",
                                                "echo \"  template:\">> patch.yml",
                                                "echo \"    spec:\">> patch.yml",
                                                "echo \"      containers:\">> patch.yml",
                                                "echo \"      - name: unicorn-store-spring\">> patch.yml",
                                                "echo \"        image: $IMAGE_DETAIL_URI:$IMAGE_DETAIL_TAG\">> patch.yml",
                                                "cat patch.yml",
                                                "aws eks update-kubeconfig --name unicorn-store-spring --region "
                                                        + infrastructureStack.getRegion() + " --role-arn "
                                                        + cluster.getKubectlRole().getRoleArn(),
                                                "kubectl -n " + projectName + " patch deployment " + projectName
                                                        + " --patch-file patch.yml"))))))
                .environmentVariables(Map.of(
                        "IMAGE_URI", BuildEnvironmentVariable.builder()
                                .value(sourceAction.getVariables().getImageUri())
                                .build(),
                        "IMAGE_TAG", BuildEnvironmentVariable.builder()
                                .value(sourceAction.getVariables().getImageTag())
                                .build()))
                .timeout(Duration.minutes(60))
                .build();

        PolicyStatement EksReadOnlyPolicy = PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "eks:DescribeNodegroup",
                        "eks:DescribeUpdate",
                        "eks:DescribeCluster"))
                .resources(List.of("*"))
                .build();

        PolicyStatement CodeBuildSTSPolicy = PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "sts:AssumeRole"))
                .resources(List.of(cluster.getKubectlRole().getRoleArn()))
                .build();

        codeBuild.addToRolePolicy(EksReadOnlyPolicy);
        codeBuild.addToRolePolicy(CodeBuildSTSPolicy);
        cluster.getKubectlRole().grantAssumeRole(codeBuild.getGrantPrincipal());

        codeBuild.getConnections().allowTo(cluster, Port.allTraffic());

        Pipeline.Builder.create(scope, projectName + "-pipeline-deploy-eks")
                .pipelineName(projectName + "-deploy-eks")
                .crossAccountKeys(false)
                .stages(List.of(
                        StageProps.builder()
                                .stageName("source")
                                .actions(List.of(
                                        sourceAction))
                                .build(),
                        StageProps.builder()
                                .stageName("deploy")
                                .actions(List.of(
                                        CodeBuildAction.Builder.create()
                                                .actionName("deploy-codebuild-kubectl")
                                                .input(sourceOuput)
                                                .project(codeBuild)
                                                .runOrder(1)
                                                .build()))
                                .build()))
                .build();
    }
}
