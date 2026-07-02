# cdk-nag / CDK version ceiling

## Current pinned versions
- `aws-cdk-lib`: **2.250.0**
- `cdk-nag`: **2.38.2**
- EKS: stable `software.amazon.awscdk.services.eks_v2` (the deprecated `eks-v2-alpha` module was dropped).

`cdk synth` passes with **0 cdk-nag findings** under the latest CDK CLI with this
combination. IAM4/IAM5 suppressions in `WorkshopApp` carry explicit `appliesTo`
evidence (a bare `AwsSolutions-IAM5` id does not suppress).

## Why not newer

`aws-cdk-lib` 2.251.0 introduced CDK's native policy-validation framework
(`software.amazon.awscdk.Validations`). From 2.251 onward, cdk-nag findings are
routed through it and must be suppressed via `Validations.of(scope).acknowledge()`
instead of `NagSuppressions`.

That acknowledge API treats `::` as a reserved `prefix::ruleName` delimiter, so it
rejects finding ids that embed IAM ARNs (which contain `iam::aws` and
`arn:<AWS::Partition>:...`), e.g.:

    AwsSolutions::AwsSolutions-IAM4[Policy::arn:<AWS::Partition>:iam::aws:policy/AdministratorAccess]
    -> InvalidValidationId: The '::' delimiter is reserved for separating the prefix from the rule name

Because every AWS managed-policy finding embeds `iam::aws`, IAM4/IAM5 findings
cannot currently be acknowledged on aws-cdk-lib >= 2.251.

cdk-nag 3.x does not help: its `NagPack` is plugin-only
(`IPolicyValidationPlugin`, no `IAspect`), so it relies entirely on the same
native `acknowledge` mechanism and cannot run report-only either.

Verified: 2.250 synth passes (0 findings); 2.260 synth fails with 19 IAM4/IAM5
findings even with correct `appliesTo`.

## Trigger to update

Do NOT pin the CDK CLI and do NOT add a Dependabot `ignore` for these bumps.
CI runs `cdk synth` with the latest CLI, so the Dependabot PR that bumps
`aws-cdk-lib` to >= 2.251 (or `cdk-nag` to 3.x) is a live tripwire:

- While the `build-infra` check on that PR is **red**, the upstream gap is still open.
- When that check goes **green**, the fix has landed. Then:
  1. bump `aws-cdk-lib` (and optionally `cdk-nag` to 3.x),
  2. switch the IAM4/IAM5 suppressions in `WorkshopApp` from
     `NagSuppressions` to `Validations.of(stack).acknowledge(...)`,
  3. delete this note.

### Manual recheck
On a scratch branch with `aws-cdk-lib >= 2.251` + `cdk-nag` 3.x, confirm that

    Validations.of(stack).acknowledge(
        Acknowledgment.builder()
            .id("AwsSolutions-IAM4[Policy::arn:<AWS::Partition>:iam::aws:policy/AdministratorAccess]")
            .reason("...").build());

no longer throws `InvalidValidationId` and that `cdk synth` exits 0.

## Upstream references
- aws/aws-cdk#26844 - cdk synth used to return exit 0 despite policy-validation
  failures (fixed in recent CLIs; this is what surfaced the findings).
- cdk-nag v3 README: prefix / bulk suppression "not yet supported" (tracked upstream).
- Watch `aws-cdk-lib` release notes for `Validations.acknowledge` id parsing that
  accepts embedded `::`.
