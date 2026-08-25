# Alternative idempotent deployment suite
# Alternative idempotent deployment suite

This suite deploys the Unicorn Rentals Spring AI workshop and replaces the removed legacy `1-mcp-server.sh` through `8-agentcore.sh` scripts. The separately linked legacy `cleanup.sh` remains unchanged and is never called by this suite.

## Order and targets

Run the complete flow with exactly one target:

```bash
./00-deploy-all.sh --target eks|ecs|lambda|agentcore
```

The orchestrator runs `01`–`05`, one of `10`–`13`, `20`, and `30`. Cleanup is never automatic. Every stage can also be run independently; each prints its prerequisites. Use `01-setup.sh --force` only when existing `~/environment/aiagent` or `~/environment/mcpserver` files should be refreshed. Existing directories are otherwise left untouched. `05-security.sh --rotate-passwords` is the only mode that changes passwords for existing users.

The EKS, ECS, Lambda, and AgentCore scripts are alternatives. Re-running a stage discovers deterministic resource names and applies or updates the desired configuration. State is stored in `~/environment/.java-spring-ai-agents-suite.env`, is bound to one AWS account and Region, and contains no passwords, tokens, or database credentials. The generated application uses Spring Boot 4.1.0, Spring AI 2.0.1, `spring-ai-vector-store-advisor`, and the modern Bedrock Converse properties with Claude Sonnet 4.6. The AgentCore target adds the AgentCore 2.1.0 BOM and runtime starter in an isolated build directory; its Runtime log group is `/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT`. UI configuration always includes the selected AWS Region.

## Test scope

`30-test.sh --target TARGET` obtains user and administrator Cognito tokens and hard-fails on health/readiness, unauthenticated access, authenticated invocation, persona, conversation memory, PgVector-backed RAG using an exact dynamic retrieval marker, a representative date/time tool call, and MCP Unicorn inventory checks. Knowledge loading is restricted to the `admin` Cognito user and bounded to 4,096 characters; normal assertions use dynamic markers and broad capability evidence rather than exact model prose.

## Cleanup safety

`99-cleanup.sh` is plan-only by default. `99-cleanup.sh --apply` removes only suite-created resources and data or restores settings that the suite recorded before modifying. It never deletes the prerequisite CloudFormation stack, VPC, Aurora cluster, EKS cluster, precreated ECS service, IAM roles, workshop bucket, ECR repositories, or participant source directories. The Lambda ZIP object is restored when it predated the suite and removed otherwise; the deterministic sample Unicorn is removed only when this suite created it.

Use `90-diagnose.sh` for read-only status collection before changing or cleaning up resources.


## Live AWS verification still required

The scripts are syntax-checked without invoking AWS or Kubernetes mutations. Before workshop use, run the stages in a disposable workshop account and verify the predeployed resource names and IAM permissions, EKS Pod Identity/Secrets Store CSI integration, internal MCP ALB reachability from every target, ECS Express Gateway update behavior, Java 25 Lambda Web Adapter layer availability, AgentCore-supported private Availability Zones, Runtime custom-JWT authorization, and CloudFront propagation. Also confirm Bedrock access to Claude Sonnet 4.6 and Titan Text Embeddings V2 in the selected Region. `30-test.sh` is the required live acceptance gate; a deployment is not considered successful until all of its health, authentication, persona, memory, RAG, tool, and MCP assertions pass.

Run `90-diagnose.sh` for read-only discovery before a live deployment. Review `99-cleanup.sh` without arguments first; only `99-cleanup.sh --apply` performs the ownership-scoped cleanup plan.