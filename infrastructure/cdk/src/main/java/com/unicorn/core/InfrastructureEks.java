package com.unicorn.core;

import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.ArnPrincipal;
import software.amazon.awscdk.services.iam.Effect;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.constructs.Construct;

import java.util.List;

// Additional infrastructure for EKS for Containers modules of Java on AWS Immersion Day
public class InfrastructureEks extends Construct {

    private final InfrastructureCore infrastructureCore;

    public InfrastructureEks(final Construct scope, final String id,
        final InfrastructureCore infrastructureCore) {
        super(scope, id);

        // Get previously created infrastructure construct
        this.infrastructureCore = infrastructureCore;

        createRolesEks();
    }

    private void createRolesEks() {
        ServicePrincipal eksPods = new ServicePrincipal("pods.eks.amazonaws.com");

        // EKS Pod Identity role
        var unicornStoreEksPodRole = Role.Builder.create(this, "UnicornStoreEksPodRole")
            .roleName("unicornstore-eks-pod-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        unicornStoreEksPodRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of("xray:PutTraceSegments"))
            .resources(List.of("*"))
            .build());
        unicornStoreEksPodRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEksPodRole-" + "CloudWatchAgentServerPolicy",
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"));
        unicornStoreEksPodRole.addManagedPolicy(ManagedPolicy.fromManagedPolicyArn(this,
            "UnicornStoreEksPodRole-" + "AmazonBedrockLimitedAccess",
            "arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess"));

        unicornStoreEksPodRole.addToPolicy(PolicyStatement.Builder.create()
                .effect(Effect.ALLOW)
                .actions(List.of(
                        "ecs:ListTasks",
                        "ecs:DescribeTasks",
                        "ecs:ListServices",
                        "ecs:DescribeServices",
                        "ecs:ListClusters",
                        "ecs:DescribeClusters",
                        "ecs:ListContainerInstances",
                        "ecs:DescribeContainerInstances"
                ))
                .resources(List.of("*"))
                .build());

        infrastructureCore.getEventBridge().grantPutEventsTo(unicornStoreEksPodRole);
        infrastructureCore.getDatabaseSecret().grantRead(unicornStoreEksPodRole);
        infrastructureCore.getParamDBConnectionString().grantRead(unicornStoreEksPodRole);

        var dbSecretPolicy = ManagedPolicy.Builder.create(this, "UnicornStoreDbSecretsManagerPolicy")
            .managedPolicyName("unicornstore-db-secret-policy")
            .statements(List.of(
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .actions(List.of("secretsmanager:ListSecrets"))
                    .resources(List.of("*"))
                    .build(),
                PolicyStatement.Builder.create()
                    .effect(Effect.ALLOW)
                    .actions(List.of(
                            "secretsmanager:GetResourcePolicy",
                            "secretsmanager:DescribeSecret",
                            "secretsmanager:GetSecretValue",
                            "secretsmanager:ListSecretVersionIds"
                    ))
                    .resources(List.of(infrastructureCore.getDatabaseSecret().getSecretFullArn()))
                    .build()
            ))
            .build();

        // External Secrets Operator roles
        Role unicornStoreEksEsoRole = Role.Builder.create(this, "UnicornStoreEksEsoRole")
            .roleName("unicornstore-eks-eso-role")
            .assumedBy(eksPods.withSessionTags())
            .build();
        ArnPrincipal unicornStoreEksEsoRolePrincipal = new ArnPrincipal(unicornStoreEksEsoRole.getRoleArn());

        Role unicornStoreEksEsoSmRole = Role.Builder.create(this, "UnicornStoreEksEsoSmRole")
            .roleName("unicornstore-eks-eso-sm-role")
            .assumedBy(unicornStoreEksEsoRolePrincipal.withSessionTags())
            .build();
        unicornStoreEksEsoSmRole.addManagedPolicy(dbSecretPolicy);
    }
}
