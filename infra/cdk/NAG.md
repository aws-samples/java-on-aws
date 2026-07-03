# cdk-nag notes

## Current versions
- `aws-cdk-lib`: **2.260.0** (latest 2.x)
- `cdk-nag`: **2.38.2** (latest 2.x)
- EKS: stable `software.amazon.awscdk.services.eks_v2`

`cdk synth` passes with **0 cdk-nag findings** for all five `template.type`
values (java-on-aws, java-on-amazon-eks, java-spring-ai-agents,
java-ai-agents, java-ai-agents-advanced) under the latest CDK CLI.

## Suppressing IAM findings

Broad IAM is intentional for this ephemeral workshop. IAM4 (managed
policies) and IAM5 (wildcards) findings are suppressed in `WorkshopApp`
using cdk-nag's `RegexAppliesTo` so the suppression matches every finding
regardless of template type or generated resource name:

- IAM4: `/^Policy::.*$/g`
- IAM5: `/^(Action|Resource)::.*$/g`

Do NOT go back to enumerated `appliesTo` lists - they only match one
template's specific findings and silently break `npm run gen` for the
others (each `template.type` builds a different construct/IAM set).

## cdk-nag 3.x

Not adopted. cdk-nag 3.x's `NagPack` is plugin-only
(`IPolicyValidationPlugin`, no `IAspect`) and suppresses via CDK's native
`Validations.of().acknowledge()`, whose rule-id parser rejects ids
containing `::` - which every IAM managed-policy/ARN finding embeds
(`iam::aws`, `arn:<AWS::Partition>:...`). We don't need 3.x: the 2.x Aspect
+ `NagSuppressions` (regex `appliesTo`) path works on the latest
aws-cdk-lib. Revisit 3.x only if cdk-nag/CDK fix the `::` handling in
`acknowledge`.
