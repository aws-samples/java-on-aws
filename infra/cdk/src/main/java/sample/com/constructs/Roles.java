package sample.com.constructs;

import software.amazon.awscdk.services.iam.*;
import software.constructs.Construct;
import org.json.JSONObject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public class Roles extends Construct {
    private final Role workshopRole;
    private final Role codeBuildRole;
    private final Role lambdaRole;
    private final Role lambdaBedrockRole;

    public Roles(final Construct scope, final String id) {
        super(scope, id);

        // Workshop role for IDE instances - uses policy from file
        this.workshopRole = Role.Builder.create(this, "WorkshopRole")
            .roleName("ide-user")
            .assumedBy(ServicePrincipal.Builder.create("ec2.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("ReadOnlyAccess"),
                ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
                ManagedPolicy.fromAwsManagedPolicyName("CloudWatchAgentServerPolicy")
            ))
            .build();

        // Load additional IAM policy from file (matches original VSCodeIde pattern)
        var policyDocumentJson = loadFile("/iam-policy.json");
        if (policyDocumentJson != null) {
            var policyDocument = PolicyDocument.fromJson(new JSONObject(policyDocumentJson).toMap());
            var policy = ManagedPolicy.Builder.create(this, "WorkshopIdeUserPolicy")
                .document(policyDocument)
                .build();
            workshopRole.addManagedPolicy(policy);
        }

        // CodeBuild service role
        this.codeBuildRole = Role.Builder.create(this, "CodeBuildRole")
            .assumedBy(ServicePrincipal.Builder.create("codebuild.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("PowerUserAccess")
            ))
            .build();

        // General Lambda role for workshop Lambda functions
        this.lambdaRole = Role.Builder.create(this, "LambdaRole")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaBasicExecutionRole")
            ))
            .build();

        // Add specific permissions for Lambda functions
        PolicyStatement lambdaPermissions = PolicyStatement.Builder.create()
            .effect(Effect.ALLOW)
            .actions(List.of(
                "ec2:DescribeManagedPrefixLists",
                "ec2:RunInstances",
                "ec2:TerminateInstances",
                "ec2:CreateTags",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeSubnets",
                "iam:PassRole",
                "ssm:DescribeInstanceInformation",
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ))
            .resources(List.of("*"))
            .build();

        lambdaRole.addToPolicy(lambdaPermissions);

        // Lambda Bedrock role for AI workshops (matches InfrastructureCore)
        this.lambdaBedrockRole = Role.Builder.create(this, "LambdaBedrockRole")
            .roleName("unicornstore-lambda-bedrock-role")
            .assumedBy(ServicePrincipal.Builder.create("lambda.amazonaws.com").build())
            .managedPolicies(List.of(
                ManagedPolicy.fromAwsManagedPolicyName("AmazonBedrockLimitedAccess"),
                ManagedPolicy.fromAwsManagedPolicyName("service-role/AWSLambdaVPCAccessExecutionRole")
            ))
            .build();
    }

    public Role getWorkshopRole() {
        return workshopRole;
    }

    public Role getCodeBuildRole() {
        return codeBuildRole;
    }

    public Role getLambdaRole() {
        return lambdaRole;
    }

    public Role getLambdaBedrockRole() {
        return lambdaBedrockRole;
    }

    private String loadFile(String filePath) {
        try {
            var resource = getClass().getResource(filePath);
            if (resource == null) {
                return null;
            }
            return Files.readString(Path.of(resource.getPath()));
        } catch (IOException e) {
            return null;
        }
    }
}