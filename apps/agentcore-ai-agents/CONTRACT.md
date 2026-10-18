# Agent contract

Every agent in `apps/agent-<framework>/` implements the same contract. The shared UI, scripts, test prompts, and screenshots then work with every framework unchanged.

Reference: `java-on-aws/apps/java-spring-ai-agents/aiagent` (Spring AI + AgentCore starter) and its UI in `src/main/resources/static/`.

## HTTP

| Item | Value |
|---|---|
| Port | `8080` (same locally and on AgentCore Runtime) |
| Health | `GET /ping` |
| Invoke | `POST /invocations` |
| Request body | `{"prompt": "..."}` (the UI may add `modelId`) |
| Response | `text/event-stream`; each `data:` line carries raw text, events end with an empty line. A plain `text/plain` stream also works |

## Headers

| Header | Local | Deployed |
|---|---|---|
| `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` | Login username (required by the TypeScript SDK) | Set by the UI per browser tab |
| `Accept` | `text/event-stream` (required for streaming by the TypeScript SDK) | Same |
| `Authorization` | Login username | `Bearer <Cognito access token>` |

Session ID format: `actorId` or `actorId:sessionId`, parsed as in `AgentCoreMemoryConversationIdParser` (spring-ai-agentcore). `actorId` scopes long-term memory; `sessionId` scopes short-term memory (default `default-session`).

## Configuration

- AWS resource IDs that the agent needs at runtime are saved to `~/environment/.envrc` (direnv), e.g. `AGENTCORE_MEMORY_ID`.
- The Java track also writes them to `application.properties`, as in `java-ai-agents`.
- On AgentCore Runtime, the same names are passed as environment variables.

## MCP server (backoffice)

Each language builds its own backoffice MCP server (Java: Spring AI, Python: FastMCP, TypeScript: MCP TypeScript SDK) with the same tool names and input schemas. The Gateway pages, the Cedar policies (`backoffice___cancelTrip`, `backoffice___deleteExpense`), and the test prompts then stay shared.

| Tools | Source |
|---|---|
| `registerTrip`, `getTrips`, `getTrip`, `cancelTrip` | `java-on-aws/apps/java-spring-ai-agents/backoffice/tools/TripTools.java` |
| `createExpense`, `getExpenses`, `getExpense`, `getExpensesForTrip`, `submitExpense`, `approveExpense` (`expenseReference`, `approverId`; SUBMITTED → APPROVED, managers only through the Gateway policy), `deleteExpense` | `.../backoffice/tools/ExpenseTools.java` |

Transport: stateless streamable HTTP on AgentCore Runtime (MCP protocol).

## Shared across frameworks

- UI (static files)
- `currency` Lambda
- AWS setup scripts
- System prompt
- Test prompts (`java-ai-agents/AGENTS.md` → Test Prompts)
