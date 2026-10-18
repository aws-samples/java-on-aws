# agentcore-ai-agents

Code of the workshop "Building AI agents with Amazon Bedrock AgentCore" (Workshop Studio repository `agentcore-ai-agents`, content source in `agentic-ai-workshop`). On the IDE it is in `~/java-on-aws/apps/agentcore-ai-agents`; the content writes the stage files into `~/environment` and calls the helpers in `scripts/`.

Every implementation follows [CONTRACT.md](CONTRACT.md).

| Folder | Content |
|---|---|
| `agent-python-strands/` | Python agent. `stages/NN-module/` holds the files each module adds or changes; stage 04+ `main.py` files are generated from `main.template.py` by `build_stages.py`. `tests/run.sh` smoke-tests every stage without AWS |
| `agent-python-langgraph/` | Python LangGraph agent, same stage layout and smoke test; tool modules match the Strands ones except the `@tool` decorator |
| `agent-ts-vercel/` | TypeScript Vercel AI SDK agent, same stage layout; `tests/run.sh` type-checks and smoke-tests every stage with mocked AWS |
| `backoffice-ts/` | TypeScript MCP server (MCP TypeScript SDK, stateless JSON responses). `app/` is the starting application, `stages/` the files the workshop adds |
| `java-spring-ai/` | Java (Spring AI) agent, same stage layout: `stages/NN-module/` holds the files each module adds or changes (`09-observability` is the second half of the deploy module); `pom.xml`, `application.properties`, and `ChatService.java` are generated from `templates/` by `build_stages.py`. `tests/run.sh` compiles every stage on a Spring Initializr project, and the backoffice |
| `backoffice-java/` | Java MCP server (Spring AI). `app/` is the starting application, `stages/` the files the workshop adds (`01-mcp-server` trip tools, `02-expenses` expense tools with `approveExpense`) |
| `backoffice-python/` | Python MCP server. `app/` is the starting application, `stages/` the files the workshop adds |
| `scripts/` | Helpers the content calls (`local-app.sh`, `ask-runtime.sh`, `check-state.sh`, `invoke-harness.sh`, `oauth-sign-in.sh`), `fast-forward.sh` for facilitators |
| `samples/` | Policy documents for the Knowledge Base, receipts |
| `receipt-lambda/` | Receipt reader Lambda (Bedrock Data Automation) |
| `travel-portal/`, `calendar-api/` | Corporate travel portal and calendar API, deployed by the stack (`infra/cdk` `TravelPortal`, `CalendarApi`) |
| `ui/` | Shared web UI (Java UI plus JSON `data:` decoding) |

In stage files, `# >> note` / `# <<` mark highlighted lines; `tools/render.py` turns them into `highlightLines` and explanations, and `build_stages.py assemble` strips them.
