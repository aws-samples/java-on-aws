# AI Agent Demo Scripts

Step-by-step demo scripts for building a Spring AI agent with Amazon Bedrock, used in conference talks.

## Prerequisites

Run `~/java-on-aws/apps/java-spring-ai-agents/scripts/00-deploy-all.sh` first to provision all AWS resources.

## Usage

Run scripts in order. Each script pauses so you can show the diff in your IDE before continuing.

```bash
cd ~/java-on-aws/apps/java-spring-ai-agents/demo-scripts
./00-setup.sh          # Move full app to ~/demo-full/, clean ~/environment/
./01-create.sh         # Bootstrap Spring Boot project + chat client + UI
# Ctrl+C to stop, then:
./02-memory.sh         # Add AgentCore Memory (STM + LTM)
./03-kb.sh             # Add Bedrock Knowledge Base (RAG)
./04-tools.sh          # Add ContextAdvisor + WebGroundingTools
./05-browser.sh        # Add AgentCore Browser + screenshots
./06-code-interpreter.sh  # Add AgentCore Code Interpreter
./07-mcp.sh            # Add MCP client + SigV4 gateway auth
./10-deploy.sh         # Add security + deploy to AgentCore Runtime
```

## Script Flow

Each script (01-07):
1. Adds dependencies, properties, and Java code
2. Pauses (`Press ENTER`) — show diff in IDE
3. Git commits the changes
4. Runs `./mvnw spring-boot:run` — Ctrl+C when done demoing

## What Each Step Adds

| Script | Feature | Key Files |
|--------|---------|-----------|
| 01 | Chat client with system prompt | `ChatService.java`, `application.properties`, static UI |
| 02 | Short-term + long-term memory | AgentCoreMemory advisors, memory-id property |
| 03 | RAG via Bedrock Knowledge Base | QuestionAnswerAdvisor, KB vector store |
| 04 | Context enrichment + web search | `ContextAdvisor.java`, `WebGroundingTools.java` |
| 05 | Browser browsing + screenshots | Browser tool callbacks, artifact store |
| 06 | Code execution + file generation | Code interpreter tool callbacks, artifact store |
| 07 | MCP tools via AgentCore Gateway | `SigV4McpConfig.java`, MCP client properties |
| 10 | JWT security + runtime deploy | `SecurityConfig.java`, `ConversationIdResolver.java`, headless profile |

## Flexible Ordering

Steps 05 and 06 are optional. You can go directly from 04 to 07 (MCP) and it will work.

## Environment

- Config values (memory-id, KB-id, gateway-url) are read from `~/demo-full/.envrc` (created by 00-setup)
- All scripts are idempotent — safe to re-run
