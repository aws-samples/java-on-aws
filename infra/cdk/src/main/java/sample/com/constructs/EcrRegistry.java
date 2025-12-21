package sample.com.constructs;

import software.amazon.awscdk.CfnTag;
import software.amazon.awscdk.services.ecr.CfnRepositoryCreationTemplate;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.constructs.Construct;

import java.util.List;

/**
 * EcrRegistry construct for ECR private registry settings.
 * Creates Repository Creation Template for automatic repository creation on push.
 * Uses prefix for resource naming consistency.
 */
public class EcrRegistry extends Construct {

    private final CfnRepositoryCreationTemplate repositoryCreationTemplate;

    public static class EcrRegistryProps {
        private String prefix = "workshop";

        public static Builder builder() { return new Builder(); }

        public static class Builder {
            private EcrRegistryProps props = new EcrRegistryProps();

            public Builder prefix(String prefix) { props.prefix = prefix; return this; }
            public EcrRegistryProps build() { return props; }
        }

        public String getPrefix() { return prefix; }
    }

    public EcrRegistry(final Construct scope, final String id, final EcrRegistryProps props) {
        super(scope, id);

        String prefix = props.getPrefix();

        // Lifecycle policy JSON - expires untagged after 1 day, keeps 10 recent tagged
        String lifecyclePolicyJson = """
            {
                "rules": [
                    {
                        "rulePriority": 1,
                        "description": "Expire untagged images after 1 day",
                        "selection": {
                            "tagStatus": "untagged",
                            "countType": "sinceImagePushed",
                            "countUnit": "days",
                            "countNumber": 1
                        },
                        "action": {
                            "type": "expire"
                        }
                    },
                    {
                        "rulePriority": 2,
                        "description": "Keep only 10 most recent tagged images",
                        "selection": {
                            "tagStatus": "tagged",
                            "tagPrefixList": ["latest", "v"],
                            "countType": "imageCountMoreThan",
                            "countNumber": 10
                        },
                        "action": {
                            "type": "expire"
                        }
                    }
                ]
            }
            """;

        // Create IAM role for ECR repository creation template
        Role ecrTemplateRole = Role.Builder.create(this, "TemplateRole")
            .roleName(prefix + "-ecr-template-role")
            .assumedBy(new ServicePrincipal("ecr.amazonaws.com"))
            .build();

        ecrTemplateRole.addToPolicy(PolicyStatement.Builder.create()
            .actions(List.of(
                "ecr:CreateRepository",
                "ecr:TagResource",
                "ecr:PutLifecyclePolicy"
            ))
            .resources(List.of("*"))
            .build());

        // Create Repository Creation Template
        this.repositoryCreationTemplate = CfnRepositoryCreationTemplate.Builder.create(this, "Template")
            .prefix("ROOT")  // Applies to all repositories
            .appliedFor(List.of("CREATE_ON_PUSH", "REPLICATION"))
            .imageTagMutability("MUTABLE")
            .lifecyclePolicy(lifecyclePolicyJson)
            .customRoleArn(ecrTemplateRole.getRoleArn())
            .resourceTags(List.of(
                CfnTag.builder()
                    .key("Environment")
                    .value(prefix)
                    .build(),
                CfnTag.builder()
                    .key("ManagedBy")
                    .value("ecr-create-on-push")
                    .build()
            ))
            .description("Auto-create repositories on push with lifecycle policies for " + prefix + " workshop")
            .build();
    }

    public CfnRepositoryCreationTemplate getRepositoryCreationTemplate() {
        return repositoryCreationTemplate;
    }
}
