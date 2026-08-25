# Idempotent deployment suite

This suite deploys and verifies the Unicorn Rentals Spring AI workshop. It replaces the removed legacy single-digit deployment scripts while preserving the manual-workshop `cleanup.sh` entry point.

## Order and targets

Run the complete flow for all deployment targets:

```bash
./00-deploy-all.sh
```

To deploy and test one target only:

```bash
./00-deploy-all.sh --target eks|ecs|lambda|agentcore
```

`--target all` is equivalent to omitting `--target`. The orchestrator runs `01`–`05`, every selected script from `10`–`13`, `20`, and `30` once for each deployed target. Cleanup is never automatic. Every stage can also run independently and prints its prerequisites.

Use `01-setup.sh --force` only to refresh existing `~/environment/aiagent` or `~/environment/mcpserver` source trees. `05-security.sh --rotate-passwords` is the only mode that changes passwords for existing workshop users.

The EKS, ECS, Lambda, and AgentCore scripts are separate deployment targets. Re-running a stage discovers deterministic resource names and creates or updates the desired configuration. State is stored in `~/environment/.java-spring-ai-agents-suite.env`, is bound to one AWS account and Region, and contains no passwords, tokens, or database credentials.

Workshop resource names match the workshop content:

- ECR repositories: `aiagent` and `mcpserver`
- ECR image tag: `latest`
- AgentCore Runtime: `aiagent`
- Kubernetes namespaces and services: `aiagent` and `mcpserver`

The generated application uses Spring Boot 4.1.0, Spring AI 2.0.1, `spring-ai-vector-store-advisor`, and Claude Sonnet 4.6. The AgentCore target adds the AgentCore 2.1.0 BOM and Runtime starter in an isolated build directory. AgentCore logs use `/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT`.

## Test scope

`30-test.sh --target TARGET` obtains Cognito tokens and hard-fails on health, authentication, persona, conversation memory, PgVector RAG, date/time tools, and MCP Unicorn inventory checks.

## Cleanup safety

`99-cleanup.sh` is plan-only by default. `99-cleanup.sh --apply` removes only resources tracked by this suite or restores settings recorded before modification. It never deletes the prerequisite CloudFormation stack, VPC, Aurora cluster, EKS cluster, precreated ECS service, IAM roles, workshop bucket, ECR repositories, or participant source directories.

Use `90-diagnose.sh` for read-only status collection before changing or cleaning resources. Participants who followed manual workshop commands use the separate `cleanup.sh` referenced by the workshop cleanup section.

## Live AWS verification

Before workshop use, run the stages in a disposable workshop account and verify EKS Pod Identity and Secrets Store CSI integration, internal MCP ALB reachability, ECS Express updates, Lambda Web Adapter behavior, AgentCore Runtime authorization, CloudFront propagation, and Bedrock model access. `30-test.sh` is the live acceptance gate.
