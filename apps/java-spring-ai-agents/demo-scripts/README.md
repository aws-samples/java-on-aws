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

## Prompts

## Repository Purpose

This is an **AWS workshop content repository** for "Building Java AI agents with Spring AI and Amazon Bedrock AgentCore". It contains educational Markdown content, not runnable application code.

**Related code repository**: `java-on-aws` in the same parent directory (`apps/java-spring-ai-agents/{aiagent,backoffice,currency}` modules)

## Key Reference Files

- **STYLE.md** — Generic AWS workshop style rules (formatting, terminology, code blocks)
- **REVIEW.md** — Review prompt for editorial passes
- **contentspec.yaml** — Workshop Studio configuration

Follow **STYLE.md** for all content formatting decisions.

## Technology Stack

- Spring Boot 4.1.0, Java 25
- Spring AI 2.0.0
- Amazon Bedrock (Claude Sonnet 4.6, Claude Opus 4.6, Nova 2 Lite)
- Amazon Bedrock AgentCore (Runtime, Memory, Browser, Code Interpreter, Gateway)
- Amazon Cognito (JWT authentication)

## Workshop Terminology

| Term | Usage |
|------|-------|
| "the application" | Technical operations: start, stop, build, deploy |
| "the AI agent" | User-facing behavior and interaction |
| "the Java application" | Java-specific behavior, module intro/summary |
| Section | Single page |
| Module | Folder containing multiple pages |

**AgentCore terminology:**

| Term | Usage |
|------|-------|
| Amazon Bedrock AgentCore | Full name on first use |
| AgentCore | Short form after first mention |
| AgentCore Runtime | The managed runtime service |
| AgentCore Memory | Memory service (STM, LTM) |
| AgentCore Browser | Browser automation service |
| AgentCore Code Interpreter | Code execution service |
| AgentCore Gateway | MCP/API gateway service |

## Environment Variables

Use **direnv** with `~/environment/.envrc`:

- Only save variables the Spring application needs at runtime
- Fetch transient values inline within code blocks (self-contained)
- No `source` commands needed — direnv auto-loads on cd
- Variables saved to `.envrc` are available in subsequent blocks

## Reference Implementation

The `java-on-aws` repository (`../java-on-aws/apps/java-spring-ai-agents`) contains working application code and deployment scripts. Always check there before writing workshop content:

- `aiagent/` — Main AI agent Spring Boot application
- `backoffice/` — MCP server for trips/expenses
- `currency/` — Currency service
- `scripts/` — Deployment and test scripts (00-deploy-all.sh, 01-memory.sh, etc.)

Never make up code implementations — copy from the reference repository.

## Workshop-Specific Patterns

**Challenge/Solution pattern** — each capability module uses:

```markdown
Interact with the AI agent:

:code[User prompt]{showCopyAction=true}

**Sample conversation:**

![without-feature](/static/module/without-feature.png)

Description of what the agent cannot do.

Stop the application with `Ctrl+C`.

## Introduction to [Capability]

... explanation and implementation ...

## Testing the application

:code[Same user prompt]{showCopyAction=true}

**Sample conversation:**

![with-feature](/static/module/with-feature.png)

Description of what the agent can now do.
```

**Committing changes** — git commit blocks are self-explanatory, no additional explanation needed:
```markdown
## Committing changes

```bash
cd ~/environment/aiagent
git add .
git commit -m "Add feature"
```
```

## Git Commits

- Do not add `Co-Authored-By` lines

## Code Block Line Verification

After adding or changing any `:::code{}` block with `highlightLines` or line number explanations, ALWAYS verify line numbers match actual content:

```bash
awk '/^:::code.*highlightLines/{found=1; print "=== "$0; NR_CODE=0; next} found && /^:::$/{found=0; print "=== END"; next} found{NR_CODE++; print NR_CODE": "$0}' content/module/index.en.md
```

Check every `highlightLines` value and `- N:` explanation against the numbered output. Fix mismatches before committing.

## Workshop Structure

| Weight | Module | Title | Purpose |
|--------|--------|-------|---------|
| 20 | setup | Workshop setup | Environment setup |
| 60 | create | Create the AI agent | Spring AI app with REST + UI |
| 70 | observability-setup | Enable observability | Transaction Search + model invocation logging |
| 80 | persona | Agent persona | System prompt + model selection + temperature |
| 100 | memory | Conversation memory | AgentCore Memory (STM + LTM) |
| 200 | knowledge | Knowledge base | Bedrock Knowledge Base (RAG) |
| 400 | tools | Tool calling and web grounding | Tool calling + Web Grounding (DateTime, Nova) |
| 440 | browser | Web browsing | AgentCore Browser |
| 460 | code-interpreter | Code execution | AgentCore Code Interpreter |
| 600 | mcp | Model Context Protocol | MCP server + deploy + gateway + client |
| 700 | deploy | Deploy the AI agent | Auth + Runtime + UI |
| 740 | document-processing | Document processing | Expense tools, Gateway plug-and-play, multi-modal chat |
| 800 | observability | Observability insights | View dashboards, traces, logs, metrics |
| 999 | summary | Workshop summary | Workshop summary |
| 1000 | cleanup | Resource cleanup | Resource cleanup |

Workshop modules live in `content/`, ordered by weight.

## Story

**User from Berlin** planning a business trip to a Java conference.

> Prompts use Berlin as example. Users can substitute their own city.

Each module demonstrates a challenge (what the agent can't do) and a solution (capability added).

## Challenge/Solution Flow

| Module | User prompt | Problem | Why needed |
|--------|-------------|---------|------------|
| persona | "Hi, how can you help me?" | Generic response | Persona + model/temperature shape behavior |
| memory | "I live in Berlin" → (new session) → "What travel hubs do I have in my location?" | Forgets | Needs to know origin |
| knowledge | "What's our travel policy?" | Doesn't know | Need to check before booking |
| tools | "Search for Java conferences which are planned in the next two months" | Can't get dates or search web | Planning when to go |
| browser | "Browse 3 top routes and prices to the last conference on Google Flights and take a screenshot" | Can't browse websites | Research options with prices |
| code-interpreter | "Calculate the carbon footprint for the top 3 routes and generate a chart image comparing price vs carbon footprint" | Can't calculate/visualize | Eco-conscious decision |
| mcp | "Register this trip in our travel system" | Can't access internal systems | Company requirement |
| deploy | (deploy to cloud) | Running locally only | Production deployment |
| multimodal | "Here's my hotel receipt" (upload) | Can't read images | Expense reporting |

## Test Prompts

**Full flow:**

```text
My name is Alex, I live in Berlin.

What travel hubs do I have nearby?

What's our travel policy?

Search for Java conferences which are planned in the next two months

Browse 3 top routes and prices to the last conference on Google Flights and take a screenshot

Calculate the carbon footprint for the top 3 routes and generate a chart image comparing price vs carbon footprint

Register the best option in our travel system.

Get list of my trips in a table

What are the public holidays in Germany in the rest of this year?
```

```text
Search for Java conferences which are planned in the next two months.
Find 3 top routes and prices to the last conference, calculate the carbon footprint and generate a chart image comparing price vs carbon footprint.
```

```text
My name is Bob, I live in Munich.
I want to go to re:Invent. Find the fastest route and register in our travel system.
```
