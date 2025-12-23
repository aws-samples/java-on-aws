# Java on Amazon Bedrock AgentCore

**Workshop Application: TEA (Travel & Expense Agent)**

*Next-gen Agentic AI for business travel*

---

## Code-Talk

**Title:** From Zero to Enterprise AI Agent: Building Production-Ready Agentic Systems with Java and Amazon Bedrock AgentCore

**Pitch:** Build enterprise AI agents with Java — from chat to multi-agent systems using Spring AI and Amazon Bedrock AgentCore.

**Abstract:** Transform your Java expertise into AI superpowers. In this code-talk with live demos, you'll see how to build a complete enterprise AI agent from scratch — starting with a simple chat application and evolving it into a sophisticated multi-agent system capable of organizing travel, processing receipts, calculating carbon footprints, and coordinating specialist agents. Using Spring AI, Java SDK, and Amazon Bedrock AgentCore's managed services, we'll walk through real code for persistent memory, RAG-powered knowledge, content safety guardrails, MCP integration for external services, enterprise-grade security, web automation, multi-modal document processing, and advanced orchestration patterns. You'll leave with working code samples and the knowledge to build your own production AI systems.

---

## Abstract

In this hands-on session, you'll build a production-ready AI agent from scratch using Java, Spring AI, Java SDK, and Amazon Bedrock AgentCore. Starting with a simple AI chat application, you'll progressively enhance it into a full enterprise AI agent — adding persistent memory, RAG-powered knowledge, content safety guardrails, external API integration and MCP (Model Context Protocol), web automation, multi-modal document processing, and cost optimization. Finally, you'll transform the monolith agent into a multi-agent system using workflow, swarm, and graph patterns with full observability and traceability across agents.

By the end, you'll have deployed a fully functional Travel & Expense agent that can search flights, dynamically calculate carbon footprints, process receipts, and coordinate specialist agents — all running on AWS managed services.

---

## The Application

### Business Context

**Travel and Expense** is an enterprise system for managing business travel bookings and expense reporting. Employees book policy-compliant travel, submit expenses with receipts, and track sustainability.

### Workshop Modules

| Module | Name | AgentCore Service |
|--------|------|-------------------|
| 1 | Create Agent | — (local) |
| 2 | Deploy and Secure | Runtime + Cognito |
| 3 | Memory | Memory |
| 4 | Knowledge | Knowledge Bases |
| 5 | Content Safety | Guardrails |
| 6 | Real-Time Data | Function Calling |
| 7 | External API Integration | Gateway (OpenAPI) |
| 8 | External Services | Gateway (MCP) |
| 9 | Live Web Data | Nova Premier (grounding) |
| 10 | Optimize Costs | Prompt Caching |
| 11 | Web Automation | Browser |
| 12 | Dynamic Calculations | Code Interpreter |
| 13 | Make Existing Apps Available to AI | MCP + Identity (OAuth 3-leg) |
| 14 | Multi-Modal Capabilities | Claude Sonnet 4 (vision) |
| 15 | Quality Assurance | Evaluations |
| 16 | Advanced Multi-Agent System | Identity (user scopes) |
| 17 | Monitoring and Tracing | Observability |

### Workshop Story

Throughout this workshop, we follow a consistent scenario:

> **"Alice from Berlin, prefers eco-friendly travel, planning a business trip to Las Vegas next week (Monday to Friday)"**

This story threads through all modules:
- Build agent, add persona, but can't remember across sessions (1)
- Deploy to AgentCore with Cognito - gets session memory (2)
- Add persistent memory - remembers "Alice from Berlin, prefers eco-friendly travel" (3)
- Check company policy for US business travel - $250/night hotel limit (4)
- Add content safety guardrails - block investment advice, PII protection (5)
- Get current date to plan travel dates (6)
- Get weather forecast for Las Vegas next week (7)
- Check US holidays during the trip with external MCP + Identity (8)
- Search web for events in Las Vegas next week (9)
- Optimize costs with prompt caching (10)
- Search flights Berlin → Las Vegas on Skyscanner (11)
- Compare carbon footprint: all flights vs train+flight hybrid (12)
- Register selected itinerary to company backoffice (13)
- Submit expense receipts with vision - Claude extracts data (14)
- Test agent quality with automated evaluations (15)
- Advanced multi-agent system plans the complete trip (16)
- Trace requests across all agents with observability (17)

> **Note**: This workshop uses "next week" for realistic weather forecasts. When running near re:Invent, you can replace "business trip next week" with "trip to re:Invent" for the conference planning experience.

**The Booking Flow**:
```
Search (Browser) → Select best option → Register to Backoffice (MCP)
     ↓                    ↓                      ↓
  Skyscanner         Itinerary +           Company system
  Booking.com        Price + Reference     Trip record + expenses
```
Note: We search and find the best option, then register the itinerary, reference, and price to the backoffice. No actual booking on external sites in this workshop.

### Use Cases

| # | Use Case | Description | Capability | Module |
|---|----------|-------------|------------|--------|
| 1 | Chat with AI Agent | Conversation with context, memory, preferences | Agent + Memory | 1, 3 |
| 2 | Check Policy | Ask about travel limits, expense categories | RAG | 4 |
| 3 | Prepare for Travel | Check weather, holidays, event dates | Gateway + MCP + Nova | 7, 8, 9 |
| 4 | Research Travel | Search flights/hotels on Skyscanner, Booking.com | Browser Automation | 11 |
| 5 | Check Sustainability | Compare carbon footprint of travel options | Code Interpreter | 12 |
| 6 | Register Trip | Register selected itinerary to backoffice | MCP to Backoffice | 13 |
| 7 | Submit Expense | Upload receipt, extract data, add to trip | Multi-Modal + MCP | 13, 14 |
| 8 | Multi-Agent Planning | Orchestrator coordinates specialist agents | Multi-Agent Patterns | 16 |

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              UI (S3 + CloudFront)                       │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                              ┌──────▼──────┐
                              │   Cognito   │
                              │  (Identity) │
                              └──────┬──────┘
                                     │
┌─────────────────────────────────────────────────────────────────────────┐
│                        AGENTCORE RUNTIME                                │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │ Memory  │ │Knowledge│ │ Browser │ │  Code   │ │Guardrails│           │
│  │         │ │  Bases  │ │         │ │Interpret│ │         │           │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘           │
└─────────────────────────────────────────────────────────────────────────┘
        │              │              │              │
        ▼              ▼              ▼              ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Holiday   │  │  Skyscanner │  │ Booking.com │  │  Backoffice │
│   Service   │  │  (Browser)  │  │  (Browser)  │  │  (Lambda)   │
└─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
  External MCP      AgentCore        AgentCore       Lambda + APIGW
    (Gateway)        Browser          Browser         + Cognito
```

### AgentCore Services Used

| Service | Purpose | Module |
|---------|---------|--------|
| Runtime | Deploy and run the agent | 2 |
| Memory | Conversation persistence | 3 |
| Knowledge Bases | RAG for policies | 4 |
| Guardrails | Content filtering, PII protection | 5 |
| Gateway | External APIs (OpenAPI) + MCP servers | 7, 8 |
| Identity | Outbound OAuth 3-leg, Inbound user scopes | 13, 16 |
| Browser | Web automation (Skyscanner, Booking.com) | 11 |
| Code Interpreter | Dynamic calculations | 12 |
| Evaluations | Agent testing and quality | 15 |
| Observability | Monitoring and tracing | 17 |

### Security Summary

| Module | Security Type | Implementation |
|--------|---------------|----------------|
| 2 | Inbound | Cognito (user authentication) |
| 5 | Content | Bedrock Guardrails |
| 8 | Outbound | API Key (simple) |
| 13 | Outbound | AgentCore Identity OAuth 3-leg (user delegation) |
| 16 | Inbound | AgentCore Identity (user scopes for agent RBAC) |

---

## Workshop Overview

Build and deploy a production AI agent using Amazon Bedrock AgentCore managed services.

### Prerequisites

- Java 25+
- Maven 3.8+
- AWS account with Amazon Bedrock access
- AWS CLI configured

---

## Workshop Styling Guide

This section defines the structure and style conventions for workshop content.

### Module Structure

Each module follows this pattern:

```
## Module N: Title

**Challenge**: User interaction that fails
(code block showing user prompt and agent failure)

**Solution**: Brief description of what we'll add

**Goal**: One-line summary

(Tables for components, technologies)

**What You'll Build**: (bullet list)
**What You'll Learn**: (bullet list)

**Code Snippets Needed**: (list of code to include)

**Verify**: (code block showing successful interaction)

**Section Finished**: Commit and summary
**Outcome**: One-line result
```

### Content Elements

| Element | Format | Example |
|---------|--------|---------|
| Challenge prompt | Code block with User/Agent | `User: "question"` → `Agent: "failure"` |
| Verify prompt | Code block with User/Agent | `User: "question"` → `Agent: "success"` |
| Commands | Bash code block | `curl https://start.spring.io/...` |
| Java code | Java code block with highlights | `highlightLines=14-18` |
| Config | Properties/JSON code block | `application.properties` |
| File paths | Inline code | `src/main/java/com/unicorn/agent/ChatController.java` |

### Git Commits

Each module ends with:
```bash
cd ~/environment/travel-expense-agent
git add .
git commit -m "Module N: Description"
```

### Screenshots

![description](/static/module-name/screenshot.png)

### Code Snippet Conventions

- Show full file for new files
- Show only changed lines with context for updates
- Use `highlightLines` to emphasize new code
- Include imports when they change
- Add comments for key concepts

### Testing Commands

```bash
# API test
curl -X POST http://localhost:8080/api/chat/stream \
  -H "Content-Type: application/json" \
  -d '{"prompt": "test question"}'

# Interactive test
:code[Test prompt here]{showCopyAction=true}
```

### Section Markers

- `**Challenge**:` - Problem statement
- `**Solution**:` - What we'll add
- `**Goal**:` - Module objective
- `**Verify**:` - Success confirmation
- `**Section finished**` - What achieved and outcomes.

### Application Restart Notes

When dependencies change (pom.xml):
```
We changed the `pom.xml`, so we need to restart the application.
Stop the running application with `Ctrl+C` and restart.
```

When only code changes (devtools auto-reload):
```
> Note: The application restarts automatically using `devtools`.
```

### Environment Variables

Format for sensitive configuration:
```bash
export VARIABLE_NAME=$(aws ssm get-parameter --name parameter-name \
  | jq --raw-output '.Parameter.Value')
```

### Code Snippet Types

| Type | When to Use | Keep in Draft? |
|------|-------------|----------------|
| Spring AI code | ChatClient, @Tool, Advisors | ❌ Placeholder only |
| AgentCore SDK | Java SDK calls to AgentCore services | ✅ Keep actual code |
| Configuration | application.properties, CDK | ❌ Placeholder only |
| OpenAPI specs | Gateway targets | ❌ Placeholder only |
| Python code | Code Interpreter examples | ❌ Placeholder only |

**Note**: During drafting phase, only AgentCore Java SDK examples should have actual code. All other code sections should have `📝 Code Snippets Needed` placeholders.

---

## Module 1: Create Agent

**Challenge 1**: Ask the agent who it is
```
User: "Who are you?"
Agent: "I’m ChatGPT, a large language model created by OpenAI. I’m designed to understand and generate text, helping answer questions, provide explanations, brainstorm ideas, and assist with a wide range of topics. Feel free to ask me anything!."
```
The agent responds, but it's generic - not specific to our Travel and Expense domain.

**Solution**: Add a system prompt to define the agent's persona.

**Goal**: Build a basic AI agent with persona and test locally

| Component | Technology |
|-----------|------------|
| Framework | Spring AI + Spring Boot |
| LLM | Amazon Bedrock (GPT OSS 120B) |
| UI | Static HTML/JS + Tailwind CSS |

**Multi-Model Strategy** (introduced progressively):
| Model | Use Case | Module |
|-------|----------|--------|
| GPT OSS 120B | General chat, tool calling | 1-8 |
| Amazon Nova Premier | Web grounding, real-time search | 9+ |
| Claude Sonnet 4 | Document/receipt analysis | 14 |

**Blocking vs Streaming**:
| Mode | Response | Use Case |
|------|----------|----------|
| Blocking | Wait for complete response | Simple APIs, batch processing |
| Streaming (SSE) | Token-by-token as generated | Chat UI, real-time feedback |

We use **streaming from the start** - real applications need responsive UX.

**Spring Initializer**:

```bash
cd ~/environment/
curl https://start.spring.io/starter.zip \
  -d type=maven-project \
  -d language=java \
  -d packaging=jar \
  -d javaVersion=25 \
  -d bootVersion=3.5.x \
  -d baseDir=travel-expense-agent \
  -d groupId=com.example \
  -d artifactId=agent \
  -d name=agent \
  -d description='Travel and Expense Agent with Spring AI and Amazon Bedrock' \
  -d dependencies=spring-ai-bedrock-converse,web,actuator,devtools \
  -o travel-expense-agent.zip

unzip travel-expense-agent.zip
rm travel-expense-agent.zip
```

**What You'll Build**:
- Spring AI agent with REST API
- Streaming responses (SSE) with `Flux<String>`
- Error handling and fallbacks
- Static chat UI with streaming display

**What You'll Learn**:
- Spring AI ChatClient basics
- Streaming vs blocking responses
- System prompts and personas
- Error handling patterns
- REST API design for agents

**📝 Code Snippets Needed**:
- `application.properties` with Bedrock configuration
- `ChatController.java` with system prompt and streaming
- `index.html` UI template with streaming fetch

**Verify** (persona works):
```
User: "Who are you?"
Agent: "I'm your Travel and Expense assistant! I help employees with travel planning,
        booking, expense reporting, and policy questions. How can I help you today?"
```

**Challenge 2**: Agent can't remember
```
User: "My name is Alice"
Agent: "Nice to meet you, Alice!"

User: "What is my name?"
Agent: "I don't have access to your name. Could you please tell me?"
```
The agent has a persona now, but it can't remember anything - not even within the same conversation!

**Outcome**: Working agent with persona, but no memory - we'll fix this after deploying to AgentCore

---

## Module 2: Deploy and Secure

**Challenge**: Local development works, but the agent is not secure
```
Developer: "The agent works on my machine, but we need it accessible to all employees"
Security: "The agent endpoint must be authenticated before going to production!"
```

**Goal**: Deploy the agent to AgentCore Runtime with Cognito authentication

| Component | Service |
|-----------|---------|
| Agent | AgentCore Runtime |
| Auth | Amazon Cognito |
| UI | S3 + CloudFront |

**What You'll Build**:
- Package agent for AgentCore
- Deploy to AgentCore Runtime
- Cognito User Pool for authentication
- Deploy UI to S3 + CloudFront

**What You'll Learn**:
- Agent packaging requirements
- AgentCore Runtime deployment
- Cognito setup and OAuth 2.0 / OIDC flows
- CloudFront distribution setup

**🔐 Security**: Inbound authentication — only authenticated users can access agent

**Bonus**: AgentCore Runtime provides session-based memory automatically! Within a session, the agent now remembers context. But memory is lost when the session ends.

**Verify**:
```
Browser: https://d1234abcd.cloudfront.net
→ Redirects to Cognito login
→ User signs in
→ Agent: "Welcome back! How can I help you today?"

User: "My name is Alice"
Agent: "Nice to meet you, Alice!"

User: "What is my name?"
Agent: "Your name is Alice!"  ← Session memory works!

(close browser, open again)

User: "What is my name?"
Agent: "I don't have access to your name..."  ← But not persistent!
```

**📝 Code Snippets Needed**:
- Agent packaging configuration
- AgentCore Runtime deployment (AWS CLI)
- Cognito User Pool configuration
- S3 + CloudFront setup for UI


**Outcome**: Agent running on AgentCore, secured with Cognito, with session memory

---

## Module 3: Memory

**Challenge**: Session memory works, but not across sessions
```
(close browser, open again)

User: "What is my name?"
Agent: "I don't have access to your name..."
```
AgentCore Runtime provides session memory, but we need persistent memory across sessions.

**Solution**: Add AgentCore Memory for persistent conversation storage.

**Memory Strategies**:
| Type | Purpose | Example |
|------|---------|---------|
| Short-Term (STM) | Current conversation context | Recent messages in session (Runtime provides this) |
| Long-Term (LTM) | Persistent facts across sessions | Past trips, expense history |
| Preferences | User settings and habits | "Prefers window seat", "Uses Celsius" |

**What You'll Build**:
- AgentCore Memory store
- Cross-session memory retrieval (LTM)
- User preference storage

**What You'll Learn**:
- AgentCore Memory API
- Memory types: event memory vs semantic memory
- Preference extraction and retrieval

**Verify**:
```
User: "My name is Alice, I'm based in Berlin and prefer eco-friendly travel"
Agent: "Got it, Alice! I'll remember you're in Berlin and prefer green options."

(new session - close browser, open again)

User: "What do you know about me?"
Agent: "You're Alice, based in Berlin, and you prefer eco-friendly travel options."
```

**📝 Code Snippets Needed**:
- AgentCore Memory client initialization
- `batchCreateMemoryRecords` for storing preferences
- `retrieveMemoryRecords` for cross-session retrieval
- ChatController update with memory advisor


**Outcome**: Agent remembers user preferences and context across sessions

---

## Module 4: Knowledge

**Challenge**: Ask about company travel policy
```
User: "What's the hotel budget for Las Vegas?"
Agent: "I don't have information about your company's travel policy..."
```
The agent doesn't have access to internal company documents.

**Solution**: Add Bedrock Knowledge Bases for RAG (Retrieval-Augmented Generation).

| Component | Service |
|-----------|---------|
| Knowledge | Bedrock Knowledge Bases |
| Documents | Travel policy, Expense policy |

**What You'll Build**:
- Bedrock Knowledge Base
- S3 data source with policies
- Knowledge Base integration in agent

**What You'll Learn**:
- Knowledge Base creation
- Document ingestion
- RAG retrieval patterns
- Policy document structure

**Verify**:
```
User: "What's the hotel budget for Las Vegas?"
Agent: "According to our travel policy, the hotel budget for US conferences is $250/night."
```

**📝 Code Snippets Needed**:
- Knowledge Base creation (AWS CLI)
- S3 bucket with policy documents
- `QuestionAnswerAdvisor` integration in ChatController


**Outcome**: Agent answers questions using internal company knowledge

---

## Module 5: Content Safety

**Challenge**: Agent can discuss any topic and expose sensitive data
```
User: "Should I invest in Bitcoin or go on vacation to Las Vegas?"
Agent: "Based on current market trends, I recommend investing in Bitcoin..."

User: "What's my colleague's salary?"
Agent: "Based on the HR database, John's salary is $125,000..."
```
Now that the agent has memory and knowledge, it needs content filtering - it shouldn't give investment advice or expose PII.

**Solution**: Add Bedrock Guardrails for content filtering and PII masking.

**Goal**: Add content filtering and safety before adding more capabilities

| Component | Service |
|-----------|---------|
| Guardrails | Bedrock Guardrails |

**What You'll Build**:
- Bedrock Guardrail configuration
- Input/output filtering
- PII detection and masking
- Topic blocking (investment advice, harmful content)

**What You'll Learn**:
- Guardrail configuration
- Content filtering rules
- PII handling
- Denied topic configuration

**Verify**:
```
User: "Should I invest in Bitcoin or go on vacation?"
Agent: "I can help you plan your Las Vegas trip! For investment advice,
        please consult a financial advisor."

User: "My credit card is 4111-1111-1111-1111"
Agent: "I've noted your payment info as [REDACTED]. I don't store sensitive card details."
```

**📝 Code Snippets Needed**:
- Bedrock Guardrail configuration (AWS CLI)
- Guardrail integration in agent
- Denied topics configuration
- PII detection and masking examples


**Outcome**: Agent blocks harmful content, masks PII, refuses investment advice

---

## Module 6: Real-Time Data

**Challenge**: Ask about dates for next week trip
```
User: "What are the dates for next week Monday to Friday?"
Agent: "I don't have access to real-time information like dates..."
```
The agent doesn't have access to dynamic information like current date to calculate next week's dates.

**Solution**: Add local tools using Spring AI @Tool annotation.

| Tool | Purpose | Type |
|------|---------|------|
| getCurrentDateTime | Current date/time | Java @Tool (internal) |

**What You'll Build**:
- @Tool annotated method
- Tool registration in agent

**What You'll Learn**:
- Spring AI @Tool annotation
- Function calling flow
- Tool descriptions for LLM

**Verify**:
```
User: "What are the dates for next week Monday to Friday?"
Agent: "Next week is December 23-27, 2025 (Monday to Friday)."
```

**📝 Code Snippets Needed**:
- `DateTimeTools.java` with `@Tool` annotation
- Tool registration in ChatController (`.defaultTools()`)


**Outcome**: Agent can call local functions for dynamic data

---

## Module 7: External API Integration

**Challenge**: Ask about weather at destination
```
User: "What's the weather in Las Vegas next week?"
Agent: "I don't have access to weather information..."
```
We could write Java code for each API, but that's a lot of boilerplate.

**Solution**: Use AgentCore Gateway to wrap REST APIs as tools using OpenAPI specs - no Java code needed.

| Tool | API | Purpose |
|------|-----|---------|
| getCoordinates | Open-Meteo Geocoding | Get city lat/lon |
| getWeather | Open-Meteo Weather | Get forecast |

**How It Works**:
1. Define OpenAPI spec for REST API
2. Add as Gateway target
3. Agent discovers tools automatically

**OpenAPI Spec Example** (getCoordinates):
```json
{
  "openapi": "3.0.0",
  "info": {"title": "Open-Meteo Geocoding", "version": "1.0.0"},
  "servers": [{"url": "https://geocoding-api.open-meteo.com"}],
  "paths": {
    "/v1/search": {
      "get": {
        "operationId": "getCoordinates",
        "summary": "Get coordinates for a city",
        "parameters": [
          {"name": "name", "in": "query", "required": true, "schema": {"type": "string"}}
        ]
      }
    }
  }
}
```

**OpenAPI Spec Example** (getWeather):
```json
{
  "openapi": "3.0.0",
  "info": {"title": "Open-Meteo Weather", "version": "1.0.0"},
  "servers": [{"url": "https://api.open-meteo.com"}],
  "paths": {
    "/v1/forecast": {
      "get": {
        "operationId": "getWeather",
        "summary": "Get weather forecast for coordinates",
        "parameters": [
          {"name": "latitude", "in": "query", "required": true, "schema": {"type": "number"}},
          {"name": "longitude", "in": "query", "required": true, "schema": {"type": "number"}},
          {"name": "daily", "in": "query", "schema": {"type": "string"}, "description": "e.g. temperature_2m_max,temperature_2m_min"},
          {"name": "timezone", "in": "query", "schema": {"type": "string"}, "default": "auto"},
          {"name": "start_date", "in": "query", "schema": {"type": "string"}, "description": "YYYY-MM-DD"},
          {"name": "end_date", "in": "query", "schema": {"type": "string"}, "description": "YYYY-MM-DD"}
        ]
      }
    }
  }
}
```

**LLM Orchestration**:
User: "What's the weather in Las Vegas next week? I prefer Celsius."

Agent flow:
```
1. getCoordinates("Las Vegas") → {lat: 36.17, lon: -115.14}
2. getWeather(lat=36.17, lon=-115.14, daily="temperature_2m_max,temperature_2m_min")
3. LLM formats response based on user preferences
```

**What You'll Build**:
- OpenAPI specs for Open-Meteo APIs
- Gateway targets for each API
- Tool chaining (coordinates → weather)

**What You'll Learn**:
- Wrap REST APIs with OpenAPI specs
- Gateway target configuration
- LLM as orchestrator (chains tools, handles preferences)
- No Java code needed for API integration

**Verify**:
```
User: "What's the weather in Las Vegas next week?"
Agent: "Las Vegas next week: High 18°C, Low 8°C. Dry and sunny - pack layers!"
```

**📝 Code Snippets Needed**:
- OpenAPI spec files (geocoding, weather)
- Gateway target creation (AWS CLI)
- Agent configuration to use Gateway tools


**Outcome**: Agent calls external APIs via Gateway without custom Java code

---

## Module 8: External Services

**Challenge**: Ask about holidays at destination
```
User: "Are there any US holidays next week?"
Agent: "I don't have access to holiday information..."
```
We need to connect to external services that expose MCP protocol, with secure authentication.

**Solution**: Use AgentCore Gateway to connect to MCP servers with API key authentication.

| Tool | MCP Server | Purpose |
|------|------------|---------|
| getHolidays | Nager.Date | Public holidays by country |

| Component | Service |
|-----------|---------|
| Gateway | AgentCore Gateway (MCP target) |
| Auth | API Key |

**API Key Authentication**:
- Simple header-based authentication
- Agent sends API key with each request
- External service validates key
- Good for: public APIs, simple integrations

**What You'll Build**:
- AgentCore Gateway MCP target
- API key configuration
- MCP client connection
- Tool discovery from MCP server

**What You'll Learn**:
- MCP protocol basics
- Gateway MCP target configuration
- API key authentication patterns
- Tool discovery patterns

**🔐 Security**: API Key — simple outbound authentication to external services

**Verify**:
```
User: "Are there any US holidays next week?"
Agent: "No federal holidays next week. The next US holiday is [upcoming holiday]."
```

**📝 Code Snippets Needed**:
- Gateway MCP target configuration
- API key configuration
- MCP client setup in agent


**Outcome**: Agent connects to external MCP servers using API key authentication

---

## Module 9: Live Web Data

**Challenge**: Ask about real-time event information
```
User: "What events are happening in Las Vegas next week?"
Agent: "I don't have information about current events..."
```
RAG has internal docs, MCP has structured APIs, but neither has real-time web information.

**Solution**: Add a separate `WebSearchService` with Amazon Nova Premier for web grounding.

**Architecture**: Separate `WebSearchService` with its own `ChatClient` configured for Nova Premier with grounding - enables real-time web search.

| Source | Use Case | Example |
|--------|----------|---------|
| RAG | Internal knowledge | Company policies |
| MCP | Structured external data | Holidays, weather |
| WebSearchService | Real-time web search | Event dates, news |

**What You'll Build**:
- Separate `WebSearchService` with Nova Premier
- Web grounding configuration (`nova_grounding` system tool)
- Service coordination between web search and main agent

**What You'll Learn**:
- Amazon Nova grounding capabilities
- When to use grounding vs RAG vs MCP
- Multi-service architecture (separate ChatClients for different tasks)

**Verify**:
```
User: "What events are happening in Las Vegas next week?"
Agent: "Next week in Las Vegas: [CES/trade show/concert] at the Convention Center,
        several shows on the Strip. Would you like details on any specific event?"
```

**📝 Code Snippets Needed**:
- `WebSearchService.java` with Nova Premier ChatClient
- Grounding configuration (`nova_grounding` system tool)
- Service coordination with main ChatService


**Outcome**: Agent searches the web for real-time information

---

## Module 10: Optimize Costs

**Goal**: Optimize costs with model selection, caching, and smart tool discovery

**Cost Optimization Strategies**:
| Strategy | How It Works | Savings |
|----------|--------------|---------|
| Model Selection | Use smaller models for simple tasks | 50-80% |
| Prompt Caching | Cache system prompt + tool definitions | 50-90% |
| Semantic Tool Search | Find relevant tools, reduce context | 30-50% |

**1. Model Selection** (our workshop progression):
| Task | Model | Why |
|------|-------|-----|
| General chat, tools | GPT OSS 120B | Open source, cost-effective |
| Web grounding | Amazon Nova Premier | Real-time search capability |
| Document analysis | Claude Sonnet 4 | Best vision + extraction |

**2. Prompt Caching**:
| What's Cached | Cost Reduction |
|---------------|----------------|
| System prompt only | 50-70% |
| System + Tools | 70-90% |

**3. Semantic Tool Search** (from Module 8):
- Instead of sending all tool definitions to LLM
- Gateway finds relevant tools by intent
- Reduces token usage when you have many tools

**What You'll Build**:
- Multi-model routing based on task complexity
- Prompt caching configuration
- Semantic search for tool discovery

**What You'll Learn**:
- Model cost/performance trade-offs
- Bedrock prompt caching
- Gateway semantic search
- Cost monitoring and analysis

**📝 Code Snippets Needed**:
- Multi-model routing configuration
- Prompt caching setup
- Gateway semantic search configuration


**Outcome**: 50-80% cost reduction while maintaining quality

---

## Module 11: Web Automation

**Challenge**: Search for actual flights and hotels
```
User: "Find me flights from Berlin to Las Vegas for next week"
Agent: "I can't search travel websites directly..."
```
APIs don't exist for every website. We need browser automation.

**Solution**: Use AgentCore Browser for web automation.

| Capability | Website |
|------------|---------|
| Flight search | Skyscanner |
| Hotel search | Booking.com |

**What You'll Build**:
- AgentCore Browser integration
- Flight search tool
- Hotel search tool

**What You'll Learn**:
- AgentCore Browser API
- Web automation patterns
- Result extraction
- Rate limiting

**Verify**:
```
User: "Find me flights from Berlin to Las Vegas for next week (Monday to Friday)"
Agent: "Found 3 routes on Skyscanner:
        - BER → FRA → LAS: 14h, €850 (Lufthansa/United)
        - BER → AMS → LAS: 15h, €780 (KLM/Delta)
        - BER → LHR → LAS: 16h, €920 (BA/AA)
        ..."
```

**📝 Code Snippets Needed**:
- AgentCore Browser client initialization
- `startBrowserSession` and `sendBrowserCommand` usage
- Browser tool wrapper for agent


**Outcome**: Agent searches real travel websites

---

## Module 12: Dynamic Calculations

**Challenge**: Find optimal route and compare carbon footprint for the trip
```
User: "I'm flying from Berlin to Las Vegas next week. Compare routes:
       BER→FRA→LAS vs BER→AMS→LAS vs BER→LHR→LAS.
       Which is greenest? Give me a Google Maps link for the best route."
Agent: "I can't calculate distances or carbon footprints..."
```
Route optimization requires haversine distance calculations and carbon math that LLM can't do reliably.

**Solution**: Use AgentCore Code Interpreter for complex calculations.

**Goal**: Calculate optimal route with carbon footprint using Code Interpreter

**Example Prompt**: "Compare routes Berlin to Las Vegas via Frankfurt, Amsterdam, or London. Which has lowest carbon? Give me Google Maps link."

**Why Code Interpreter?**
- Route optimization requires precise haversine distance calculations
- Carbon footprint needs accurate emission factor math
- LLM cannot reliably calculate distances for multiple routes
- Uses `numpy` and `networkx` libraries
- Generates actionable output (Google Maps URLs, recommendations)

**Tools Used**:
| Tool | Source | Purpose |
|------|--------|---------|
| getCoordinates | Module 7 Gateway (reused) | Get city lat/lon from Open-Meteo |
| executeCode | Code Interpreter | Run Python for route optimization + haversine |

**How It Works**:

1. Reuse `getCoordinates` from Gateway (Module 7) - already exposed via OpenAPI spec

2. Add Code Interpreter tool:
```java
@Tool(description = """
    Execute Python code for complex calculations.
    Use for: route optimization, distance calculations, carbon footprint analysis.
    Available libraries: networkx, numpy, pandas, scipy.
    """)
public String executeCode(String pythonCode) {
    return codeInterpreterClient.execute(sessionId, pythonCode);
}
```

3. System prompt steers the agent:
```
When users ask about route comparison or carbon footprint:
1. First call getCoordinates for each city in the routes
2. Then use executeCode to calculate distances and carbon for each route
3. Generate Google Maps URL for the recommended route
- Emission factors: flight 0.255 kg CO2/km, train 0.041 kg CO2/km
```

4. Agent flow:
```
User: "Compare routes BER→FRA→LAS vs BER→AMS→LAS. Which is greenest? Google Maps link."
  ↓
Agent calls getCoordinates("Berlin") → "Berlin: 52.52, 13.41"
Agent calls getCoordinates("Frankfurt") → "Frankfurt: 50.11, 8.68"
Agent calls getCoordinates("Amsterdam") → "Amsterdam: 52.37, 4.90"
Agent calls getCoordinates("Las Vegas") → "Las Vegas: 36.17, -115.14"
  ↓
Agent calls executeCode with Python code
  ↓
Returns: route comparison + Google Maps link for best route
```

5. LLM generates Python code:
```python
import numpy as np

# Coordinates from getCoordinates tool calls
coords = {
    'Berlin': (52.52, 13.41),
    'Frankfurt': (50.11, 8.68),
    'Amsterdam': (52.37, 4.90),
    'Las Vegas': (36.17, -115.14)
}

# Haversine formula for distance calculation
def haversine(city1, city2):
    R = 6371  # Earth radius in km
    lat1, lon1 = np.radians(coords[city1])
    lat2, lon2 = np.radians(coords[city2])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = np.sin(dlat/2)**2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon/2)**2
    return 2 * R * np.arcsin(np.sqrt(a))

# Emission factor for flights (kg CO2 per km)
FLIGHT_FACTOR = 0.255

# Calculate routes
routes = {
    'BER→FRA→LAS': ['Berlin', 'Frankfurt', 'Las Vegas'],
    'BER→AMS→LAS': ['Berlin', 'Amsterdam', 'Las Vegas'],
}

results = {}
for name, cities in routes.items():
    total_dist = sum(haversine(cities[i], cities[i+1]) for i in range(len(cities)-1))
    co2 = total_dist * FLIGHT_FACTOR
    results[name] = {'distance': total_dist, 'co2': co2, 'cities': cities}

# Find best route
best = min(results.items(), key=lambda x: x[1]['co2'])
best_name, best_data = best

# Generate Google Maps URL
maps_url = "https://www.google.com/maps/dir/" + "/".join(best_data['cities'])

print("Route Comparison:")
for name, data in results.items():
    marker = " ← GREENEST" if name == best_name else ""
    print(f"  {name}: {data['distance']:,.0f} km, {data['co2']:,.0f} kg CO2{marker}")

print(f"\nRecommendation: {best_name}")
print(f"Total distance: {best_data['distance']:,.0f} km")
print(f"Carbon footprint: {best_data['co2']:,.0f} kg CO2")
print(f"Google Maps: {maps_url}")
```

6. Example output:
```
Route Comparison:
  BER→FRA→LAS: 9,630 km, 2,456 kg CO2 ← GREENEST
  BER→AMS→LAS: 9,780 km, 2,494 kg CO2

Recommendation: BER→FRA→LAS
Total distance: 9,630 km
Carbon footprint: 2,456 kg CO2
Google Maps: https://www.google.com/maps/dir/Berlin/Frankfurt/Las Vegas
```

**Bonus: Train + Flight Hybrid**

For eco-conscious travelers, compare train to hub + flight:
```
User: "What if I take train Berlin→Frankfurt, then fly to Las Vegas?"
```

```python
# Hybrid: Train BER→FRA + Flight FRA→LAS
train_dist = haversine('Berlin', 'Frankfurt')  # ~430 km
flight_dist = haversine('Frankfurt', 'Las Vegas')  # ~9,200 km

hybrid_co2 = (train_dist * 0.041) + (flight_dist * 0.255)  # train + flight factors
all_flight_co2 = (train_dist + flight_dist) * 0.255

savings = all_flight_co2 - hybrid_co2
print(f"All flights: {all_flight_co2:,.0f} kg CO2")
print(f"Train + Flight: {hybrid_co2:,.0f} kg CO2")
print(f"Savings: {savings:,.0f} kg CO2 ({savings/all_flight_co2*100:.1f}%)")
```

Output:
```
All flights: 2,456 kg CO2
Train + Flight: 2,364 kg CO2
Savings: 92 kg CO2 (3.7%)
```

**What You'll Build**:
- AgentCore Code Interpreter integration
- Reuse getCoordinates from Gateway (Module 7)
- System prompt for multi-tool orchestration

**What You'll Learn**:
- Code Interpreter API and pre-installed libraries
- Tool reuse across modules
- Multi-tool orchestration (Gateway + Code Interpreter)
- Steering agent to generate executable code
- Returning actionable results (URLs, data)

**📝 Code Snippets Needed**:
- AgentCore Code Interpreter client initialization
- `startCodeInterpreterSession` and `executeCode` usage
- Code Interpreter tool wrapper for agent


**Outcome**: Agent calculates carbon footprint, optimizes multi-city routes (TSP), and returns Google Maps links

---

## Module 13: Make Existing Apps Available to AI

**Challenge**: Register selected travel options to company backoffice
```
User: "Register the Lufthansa BER→FRA→LAS flight for €850 to the system."
Agent: "I can't connect to the company backoffice system..."
```
After searching with Browser (Module 11) and selecting the best option, we need to register the itinerary to the company system. The backoffice needs to know which user is registering the trip.

**Solution**: Add MCP to existing Backoffice service with AgentCore Identity OAuth 3-leg for user delegation.

**Goal**: Connect agent to Backoffice via MCP with user identity

**API Key vs Identity OAuth 3-leg**:
| Aspect | API Key (Module 8) | Identity OAuth 3-leg (This Module) |
|--------|-------------------|-------------------------------------|
| Auth | Simple header | Full OAuth flow with user consent |
| Identity | Agent only | Agent on behalf of user |
| Use case | Public APIs | User-specific data |
| Backoffice sees | "Agent called" | "Alice called via Agent" |
| Data access | Shared data | User's trips only |
| Token vault | No | Yes (AgentCore stores tokens) |

**AgentCore Identity Flow**:
```
1. User signs in (Cognito) → passes token to app
2. User requests action via agent
3. Agent requests workload access token from AgentCore Identity
4. AgentCore validates user token, issues workload token
5. Agent requests resource access token for Backoffice
6. First time: User sees consent prompt ("Allow agent to access your trips?")
7. User consents → Backoffice issues resource token
8. AgentCore stores token in secure vault (no consent fatigue next time)
9. Agent calls Backoffice with resource token
10. Backoffice returns Alice's data (not Bob's)
```

**The Flow**:
```
1. Search flights/hotels (Browser → Skyscanner, Booking.com)
2. Agent recommends best option based on policy, price, sustainability
3. User confirms selection
4. Agent registers itinerary on behalf of user (OAuth 3-leg)
5. Backoffice stores trip under Alice's account
6. After trip: submit expenses with receipts (Module 14 vision)
```
Note: No actual booking on external sites - we register the selected itinerary for tracking.

| Component | Service |
|-----------|---------|
| Backoffice | Lambda + API Gateway |
| Auth | AgentCore Identity (OAuth 3-leg) |
| Protocol | MCP |

**What You'll Build**:
- MCP server in Backoffice Lambda
- AgentCore Identity OAuth 3-leg configuration
- User token delegation flow
- Agent MCP client with user context

**Tools Exposed**:
| Tool | Description |
|------|-------------|
| registerTrip | Register trip for current user |
| createExpense | Create expense for current user |
| getTrips | Get current user's trips |
| getExpenses | Get current user's expenses |

**What You'll Learn**:
- MCP server implementation
- Lambda deployment patterns
- AgentCore Identity OAuth 3-leg (user delegation)
- User context propagation to backend

**🔐 Security**: AgentCore Identity OAuth 3-leg — agent acts on behalf of user with secure token vault

**When to use AgentCore Identity**:
- Secure agent access to prevent unauthorized usage
- Integrate with enterprise identity systems
- Enable agents to access external services securely
- Implement fine-grained access control
- Reduce consent fatigue (tokens stored securely)

**Verify**:
```
User: "Register the Lufthansa BER→FRA→LAS flight for €850 and Venetian hotel $220/night
       for 5 nights for my Las Vegas business trip."
Agent: "Registered your Las Vegas trip:
        - Flight: BER→FRA→LAS, €850 (Lufthansa)
        - Hotel: Venetian, $1,100 (5 nights)
        - Total: ~€1,850
        Trip ID: TRIP-2026-1201 created in backoffice under your account (Alice)."
```

**📝 Code Snippets Needed**:
- AgentCore Identity OAuth 3-leg configuration
- MCP server implementation in Lambda
- User token validation in Lambda
- Agent MCP client with user delegation


**Outcome**: Agent registers trips on behalf of user — backoffice knows it's Alice's trip

---

## Module 14: Multi-Modal Capabilities

**Challenge**: Process expense receipts from the trip
```
User: (uploads photo of restaurant receipt from Las Vegas)
Agent: "I can't process images..."
```
After the trip, we need to submit expenses with receipts. Vision capabilities needed for document processing.

**Solution**: Use Claude Sonnet 4 for multi-modal document analysis.

**Goal**: Process receipts and documents with Claude Sonnet 4

| Use Case | Input | Output | Model |
|----------|-------|--------|-------|
| Receipt processing | Photo | Expense data | Claude Sonnet 4 |
| Invoice extraction | PDF | Line items | Claude Sonnet 4 |

**Architecture**: Separate `DocumentChatService` with its own `ChatClient` configured for Claude Sonnet 4 - best-in-class for vision and structured extraction.

**The Expense Flow**:
```
1. User uploads receipt photo
2. DocumentChatService (Claude Sonnet 4) extracts: vendor, amount, date, category
3. Main ChatService confirms with user
4. Agent calls createExpense (Module 13 MCP) to register
```

**Multi-Service Architecture**:
```
User uploads receipt
       │
       ▼
┌─────────────────────┐
│ DocumentChatService │  ← Separate ChatClient
│  (Claude Sonnet 4)  │     for vision + extraction
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│    ChatService      │  ← Main agent ChatClient
│   (GPT OSS 120B)    │     confirms and registers
└────────┬────────────┘
         │
         ▼
   createExpense (Module 13 MCP)
```

**Verify**:
```
User: (uploads photo of dinner receipt from Gordon Ramsay Hell's Kitchen)
Agent: "I extracted from your receipt:
        - Vendor: Gordon Ramsay Hell's Kitchen
        - Amount: $127.50
        - Date: Dec 3, 2026
        - Category: Meals
        - Contains alcohol: Yes (2x cocktails)

        ⚠️ Policy check: Meals with alcohol require Manager approval.

        Should I submit this for manager approval?"
User: "Yes"
Agent: "Expense submitted for manager approval. Trip ID: TRIP-2026-1201.
        You'll be notified when approved."
```

**What You'll Build**:
- Image upload handling
- Separate `DocumentChatService` with Claude Sonnet 4
- Structured data extraction
- Service coordination between document analysis and main agent

**What You'll Learn**:
- Multi-modal input handling
- Vision model prompting
- OCR and extraction
- Multi-service architecture (separate ChatClients for different tasks)

**📝 Code Snippets Needed**:
- Claude Sonnet 4 model configuration
- Image upload handling in controller
- Multi-modal prompt construction
- Model routing based on input type


**Outcome**: Upload receipt → Claude extracts expense data → saved to Backoffice via MCP

---

## Module 15: Quality Assurance

**Challenge**: How do we know the agent is working correctly?
```
Developer: "The agent sometimes gives wrong policy information"
QA: "We need automated testing before each release"
Manager: "How do we measure agent quality over time?"
```
Manual testing doesn't scale. We need automated evaluation.

**Solution**: Add AgentCore Evaluations for automated quality testing.

**Goal**: Test and evaluate agent quality

| Test Type | What It Tests |
|-----------|---------------|
| Unit Tests | Individual tools |
| Integration Tests | Service communication |
| E2E Tests | Conversation flows |
| Eval Tests | Response quality |

**What You'll Build**:
- AgentCore Evaluations setup
- Test datasets
- Quality metrics
- Regression tests

**What You'll Learn**:
- AgentCore Evaluations API
- Agent testing strategies
- Quality metrics definition
- Continuous evaluation

**📝 Code Snippets Needed**:
- AgentCore Evaluations setup
- Test dataset format
- `evaluate` API usage
- Quality metrics configuration


**Outcome**: Automated quality assurance for agent

---

## Module 16: Advanced Multi-Agent System

**Goal**: Refactor monolith agent into multi-agent architecture

**The Problem**: Our single agent has grown complex with many capabilities:
- Policy checking (RAG)
- Travel booking (Browser)
- Sustainability calculations (Code Interpreter)
- Expense management (MCP)

As the agent grows, it becomes harder to maintain, test, and scale independently.

**The Solution**: Break into specialist agents, each deployed to AgentCore Runtime.

**From Monolith to Multi-Agent**:
```
Before (Modules 1-16):                    After (Module 17):
┌─────────────────────────┐              ┌─────────────┐ ┌─────────────┐
│    Single Agent         │              │   Policy    │ │   Booking   │
│  ┌───────┐ ┌───────┐   │              │   Agent     │ │    Agent    │
│  │Policy │ │Booking│   │     →        │  (Runtime)  │ │  (Runtime)  │
│  │ RAG   │ │Browser│   │              └──────┬──────┘ └──────┬──────┘
│  └───────┘ └───────┘   │                     │               │
│  ┌───────┐ ┌───────┐   │              ┌──────┴───────────────┴──────┐
│  │Sustain│ │Expense│   │              │        Orchestrator         │
│  │CodeInt│ │  MCP  │   │              │         (Runtime)           │
│  └───────┘ └───────┘   │              └──────┬───────────────┬──────┘
└─────────────────────────┘                    │               │
                                        ┌──────┴──────┐ ┌──────┴──────┐
                                        │Sustainability│ │   Expense   │
                                        │    Agent    │ │    Agent    │
                                        │  (Runtime)  │ │  (Runtime)  │
                                        └─────────────┘ └─────────────┘
```

**Specialist Agents**:
| Agent | Role | Capability |
|-------|------|------------|
| Orchestrator | Coordinator | Routes tasks, manages flow |
| Policy Advisor | Budget/rules | RAG on policies |
| Booking Agent | Travel search | Web grounding + Browser |
| Sustainability Advisor | Carbon tracking | Code Interpreter |
| Expense Agent | Expense management | Vision + MCP to Backoffice |
| Summary Agent | Final presentation | Summarize and present results |

**Multi-Model Strategy for Multi-Agent**:

Use lightweight models for orchestration, specialized models for complex tasks:

| Agent | Model | Why |
|-------|-------|-----|
| Orchestrator | Amazon Nova Lite | Fast routing, low cost, simple decisions |
| Policy Advisor | GPT OSS 120B | RAG retrieval, policy interpretation |
| Booking Agent | Amazon Nova Premier | Web grounding + browser automation |
| Sustainability Advisor | Amazon Nova Micro | Simple calculations, lowest cost |
| Expense Agent | Claude Sonnet 4 | Vision for receipts, structured extraction |
| Summary Agent | Claude Haiku 4 | Fast, high-quality final presentation |

> **Note**: Model selection will be adjusted during implementation based on performance and cost.

**Cost Optimization**:
- Orchestrator handles many requests but does simple routing → Nova Lite (cheapest)
- Specialist agents do complex work but fewer requests → appropriate model per task
- Result: 40-60% cost reduction vs using same model everywhere

**Iterative Collaboration Example**:
```
User: "Plan my business trip to Las Vegas from Berlin within budget"

Orchestrator → Policy Advisor: "What's the budget for US conferences?"
Policy Advisor → Orchestrator: "$3,000 total, $250/night hotel"

Orchestrator → Booking Agent: "Find Berlin to Las Vegas options"
Booking Agent → Orchestrator: "BER→FRA→LAS €850, Venetian $220/night, Total €2,100"

Orchestrator → Sustainability Advisor: "Compare carbon footprint of routes"
Sustainability Advisor → Orchestrator: "BER→FRA→LAS: 1,850kg CO2, BER→FRA (train) + FRA→LAS: 1,650kg CO2"

Orchestrator → Booking Agent: "User prefers green travel, find train+flight combo"
Booking Agent → Orchestrator: "ICE Berlin→Frankfurt €89 + FRA→LAS €720, saves 200kg CO2"

→ Loop until optimal solution found
→ Present options to user
```

**Coordination Patterns**:

| Pattern | When to Use | Travel & Expense Example |
|---------|-------------|--------------------------|
| **Workflow** | Sequential stages, clear dependencies | Check policy → Book travel → Submit expense |
| **Swarm** | Parallel exploration, shared insights | Multiple agents research destinations simultaneously |
| **Graph** | Complex dependencies, iterative refinement | Booking ↔ Sustainability loop until optimal |

**Workflow Pattern** (Sequential):
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Policy    │ →  │   Booking   │ →  │Sustainability│ →  │   Expense   │
│   Advisor   │    │    Agent    │    │   Advisor   │    │    Agent    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     Check              Find              Calculate           Create
     budget            options            carbon             expense
```

**Swarm Pattern** (Parallel):
```
                    ┌─────────────┐
                    │   Policy    │
                    │   Advisor   │
                    └──────┬──────┘
                           │
┌─────────────┐    ┌───────▼───────┐    ┌─────────────┐
│   Booking   │ ←→ │  Orchestrator │ ←→ │Sustainability│
│    Agent    │    │  (Shared Mem) │    │   Advisor   │
└─────────────┘    └───────┬───────┘    └─────────────┘
                           │
                    ┌──────▼──────┐
                    │   Expense   │
                    │    Agent    │
                    └─────────────┘
All agents share memory, collaborate on best solution
```

**Graph Pattern** (Iterative):
```
┌─────────────┐         ┌─────────────┐
│   Booking   │ ←─────→ │Sustainability│
│    Agent    │  refine │   Advisor   │
└──────┬──────┘         └──────┬──────┘
       │                       │
       └───────────┬───────────┘
                   ▼
            ┌─────────────┐
            │ Orchestrator│
            └─────────────┘
Booking and Sustainability iterate until optimal balance
```

**User-Based Agent Permissions (AgentCore Identity)**:

Same orchestrator, different access based on user:

| User | Policy | Booking | Sustainability | Expense |
|------|--------|---------|----------------|---------|
| Alice (full) | ✅ | ✅ | ✅ | ✅ |
| Bob (restricted) | ✅ | ✅ | ❌ | ✅ |

```
Alice → Orchestrator → All agents ✅
Bob   → Orchestrator → Sustainability Agent ❌ "Access denied"
```

**Why?** Bob's role doesn't include carbon tracking permissions. AgentCore Identity enforces this at the agent level.

**🔐 Security**: Inbound Identity with user scopes — same orchestrator, per-user agent access

**What You'll Build**:
- Multi-agent system with specialist agents
- Orchestrator for coordination
- Inter-agent communication
- AgentCore Identity user scopes for RBAC
- Pattern selection based on use case

**What You'll Learn**:
- When to use each coordination pattern
- Agent specialization and separation of duties
- Shared memory for collaboration
- Iterative refinement loops
- AgentCore Identity inbound for per-user agent permissions

**📝 Code Snippets Needed**:
- Specialist agent configurations
- Orchestrator implementation
- Inter-agent communication patterns
- AgentCore Identity user scope configuration
- Shared memory setup

**Outcome**: Production multi-agent system with user-based access control

---

## Module 17: Monitoring and Tracing

**Goal**: Monitor and debug multi-agent system in production

| Metric | Description |
|--------|-------------|
| Requests | Total agent requests |
| Latency | Response time per agent |
| Tokens | Token usage across agents |
| Errors | Error rates by agent |
| Cost | Cost per conversation |
| Traces | Cross-agent request flow |

**What You'll Build**:
- AgentCore Observability setup
- CloudWatch dashboards
- Alerts configuration
- Distributed tracing across agents

**What You'll Learn**:
- AgentCore Observability API
- Bedrock invocation logging
- Multi-agent trace analysis
- Troubleshooting patterns

**Why After Multi-Agent?**: Observability is most valuable when you can trace requests across multiple agents. See how Orchestrator → Policy → Booking → Sustainability flows through the system.

**📝 Code Snippets Needed**:
- AgentCore Observability configuration
- CloudWatch dashboard setup
- Distributed tracing integration
- Multi-agent trace correlation
**Outcome**: Full visibility into multi-agent performance

---

# Java SDK Support

All AgentCore services are accessible via AWS SDK for Java v2. AgentCore provides two APIs:
- **Control Plane** — create and manage resources
- **Data Plane** — runtime operations

## SDK Support Matrix

| Service | Control Plane | Data Plane | Java SDK |
|---------|---------------|------------|----------|
| Runtime | ✅ | ✅ `invokeAgentRuntime` | ✅ |
| Memory | ✅ | ✅ `batchCreateMemoryRecords` | ✅ |
| Knowledge Bases | ✅ | ✅ | ✅ |
| Gateway | ✅ | ✅ | ✅ |
| Browser | ✅ | ✅ `getBrowserSession` | ✅ |
| Code Interpreter | ✅ | ✅ `getCodeInterpreterSession` | ✅ |
| Identity | ✅ | ✅ `getWorkloadAccessToken` | ✅ |
| Evaluations | ✅ | ✅ `evaluate` | ✅ |
| Guardrails | ✅ | ✅ | ✅ |

## Java SDK Examples

### Invoke Agent Runtime

```java
BedrockAgentCoreClient client = BedrockAgentCoreClient.create();

InvokeAgentRuntimeResponse response = client.invokeAgentRuntime(req -> req
    .agentRuntimeArn("arn:aws:bedrock-agentcore:us-east-1:123456789:runtime/my-agent")
    .inputText("What's the weather in Las Vegas next week?")
    .sessionId("user-123"));
```

### Memory Operations

```java
// Create memory records
client.batchCreateMemoryRecords(req -> req
    .memoryId("memory-123")
    .records(List.of(
        MemoryRecord.builder()
            .content("User prefers window seats")
            .build())));

// Retrieve memory
client.retrieveMemoryRecords(req -> req
    .memoryId("memory-123")
    .query("user preferences"));
```

### Browser Session

```java
// Start browser session
StartBrowserSessionResponse session = client.startBrowserSession(req -> req
    .browserArn("arn:aws:bedrock-agentcore:us-east-1:123456789:browser/my-browser"));

// Navigate and interact
client.sendBrowserCommand(req -> req
    .sessionId(session.sessionId())
    .command(BrowserCommand.builder()
        .navigate("https://www.skyscanner.com")
        .build()));
```

### Code Interpreter

Code Interpreter executes **Python** code in a secure, sandboxed environment.

```java
// Start code interpreter session
StartCodeInterpreterSessionResponse session = client.startCodeInterpreterSession(req -> req
    .codeInterpreterArn("arn:aws:bedrock-agentcore:us-east-1:123456789:code-interpreter/my-ci"));

// Execute Python code
client.executeCode(req -> req
    .sessionId(session.sessionId())
    .code("print(100 * 0.255)"));  // Carbon calculation
```

### Evaluations

```java
// Create evaluator (Control Plane)
BedrockAgentCoreControlClient controlClient = BedrockAgentCoreControlClient.create();

controlClient.createEvaluator(req -> req
    .evaluatorName("helpfulness-eval")
    .level(EvaluationLevel.TRACE)
    .evaluatorConfig(config));

// Run evaluation (Data Plane)
client.evaluate(req -> req
    .evaluatorId("helpfulness-eval")
    .traces(traces));
```

## API Documentation

| API | Documentation |
|-----|---------------|
| Control Plane | [AgentCore Control Plane API](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/Welcome.html) |
| Data Plane | [AgentCore Data Plane API](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/Welcome.html) |
| AWS CLI | [bedrock-agentcore CLI](https://docs.aws.amazon.com/cli/latest/reference/bedrock-agentcore/index.html) |
| Developer Guide | [AgentCore Developer Guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/develop-agents.html) |

---

# CDK Support

All AgentCore services are supported with AWS CDK. Two levels of constructs are available:
- **L1 Constructs** (stable) — direct CloudFormation mappings
- **L2 Constructs** (alpha) — higher-level abstractions with sensible defaults

## CDK Support Matrix

| Service | L1 Construct | L2 Construct (Alpha) | Status |
|---------|--------------|----------------------|--------|
| Runtime | `CfnRuntime` | `Runtime` | ✅ |
| Memory | `CfnMemory` | `Memory` | ✅ |
| Gateway | `CfnGateway` | `Gateway` | ✅ |
| Gateway Target | `CfnGatewayTarget` | `GatewayTarget` | ✅ |
| Browser | `CfnBrowserCustom` | `Browser` | ✅ |
| Code Interpreter | `CfnCodeInterpreterCustom` | `CodeInterpreter` | ✅ |

## CDK Packages

| Language | L1 Package | L2 Package (Alpha) |
|----------|------------|-------------------|
| Java | `software.amazon.awscdk.services.bedrockagentcore` | `software.amazon.awscdk.services.bedrockagentcore.alpha` |
| TypeScript | `aws-cdk-lib/aws-bedrockagentcore` | `@aws-cdk/aws-bedrock-agentcore-alpha` |
| Python | `aws_cdk.aws_bedrockagentcore` | `aws_cdk.aws_bedrock_agentcore_alpha` |

## CDK Examples (Java)

### Runtime (L2)

```java
import software.amazon.awscdk.services.bedrockagentcore.alpha.Runtime;

Runtime runtime = Runtime.Builder.create(this, "TravelAgentRuntime")
    .runtimeName("travel-expense-agent")
    .networkMode(NetworkMode.PUBLIC)
    .build();
```

### Memory (L2)

```java
import software.amazon.awscdk.services.bedrockagentcore.alpha.Memory;

Memory memory = Memory.Builder.create(this, "AgentMemory")
    .memoryName("travel-agent-memory")
    .eventExpiryDuration(Duration.days(30))
    .build();
```

### Gateway (L2)

```java
import software.amazon.awscdk.services.bedrockagentcore.alpha.Gateway;
import software.amazon.awscdk.services.bedrockagentcore.alpha.GatewayTarget;

Gateway gateway = Gateway.Builder.create(this, "McpGateway")
    .gatewayName("holiday-service-gateway")
    .build();

GatewayTarget.Builder.create(this, "HolidayTarget")
    .gateway(gateway)
    .targetName("nager-date-holidays")
    .endpointUrl("https://date.nager.at/api/v3")
    .build();
```

### Browser (L2)

```java
import software.amazon.awscdk.services.bedrockagentcore.alpha.Browser;

Browser browser = Browser.Builder.create(this, "TravelBrowser")
    .browserName("travel-search-browser")
    .build();
```

### Code Interpreter (L2)

```java
import software.amazon.awscdk.services.bedrockagentcore.alpha.CodeInterpreter;

CodeInterpreter codeInterpreter = CodeInterpreter.Builder.create(this, "SustainabilityCalc")
    .codeInterpreterName("carbon-calculator")
    .build();
```

### L1 Construct Example

```java
import software.amazon.awscdk.services.bedrockagentcore.CfnRuntime;

CfnRuntime runtime = CfnRuntime.Builder.create(this, "TravelAgentRuntime")
    .runtimeName("travel-expense-agent")
    .networkConfiguration(CfnRuntime.NetworkConfigurationProperty.builder()
        .networkMode("PUBLIC")
        .build())
    .build();
```

## CDK Documentation

| Resource | Link |
|----------|------|
| L1 API Reference | [aws-cdk-lib/aws-bedrockagentcore](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_bedrockagentcore-readme.html) |
| L2 API Reference (Alpha) | [@aws-cdk/aws-bedrock-agentcore-alpha](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-bedrock-agentcore-alpha-readme.html) |
| CDK Developer Guide | [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/) |

---

# Future Considerations

## Spring AI Community Integration

This workshop creates AgentCore tools as `@Tool` wrappers. These can be packaged as a reusable library with Spring Boot auto-configuration.

**Community Project**: [spring-ai-bedrock-agentcore](https://github.com/spring-ai-community/spring-ai-bedrock-agentcore)

Currently provides:
- `@AgentCoreInvocation` for Runtime deployment
- `/invocations` and `/ping` endpoints
- SSE streaming, health checks, rate limiting

**Potential contributions from this workshop:**

| Component | Spring AI Type | AgentCore Service |
|-----------|----------------|-------------------|
| `AgentCoreBrowserTool` | `ToolCallbackProvider` | Browser |
| `AgentCoreCodeInterpreterTool` | `ToolCallbackProvider` | Code Interpreter |
| `AgentCoreChatMemory` | `ChatMemory` | Memory |
| `AgentCoreGatewayToolProvider` | `ToolCallbackProvider` | Gateway |
| `AgentCoreGuardrailsAdvisor` | `Advisor` | Guardrails |

**Auto-configuration pattern:**
```java
@Bean
@ConditionalOnProperty("spring.ai.agentcore.browser.enabled")
public ToolCallbackProvider browserTool(AgentCoreBrowserClient client) {
    return ToolCallbackProvider.from(
        FunctionCallback.builder()
            .function("searchWeb", req -> client.search(req))
            .description("Search the web using AgentCore Browser")
            .build()
    );
}
```

**Result:** Add dependency → tools auto-registered:
```xml
<dependency>
    <groupId>org.springaicommunity</groupId>
    <artifactId>spring-ai-agentcore-tools</artifactId>
</dependency>
```

---

## Event-Driven Agents

This workshop focuses on synchronous agent invocation patterns. For future iterations, consider adding event-driven scenarios:

| Pattern | Use Case | Implementation |
|---------|----------|----------------|
| S3 → Agent | Receipt uploaded triggers expense processing | S3 Event → EventBridge → Lambda → AgentCore Runtime |
| SQS → Agent | Batch processing of travel requests | SQS Queue → Lambda → AgentCore Runtime |
| Agent → Agent (async) | Booking complete triggers expense draft | Agent publishes event → EventBridge → Another agent |
| Schedule → Agent | Daily travel policy compliance check | EventBridge Scheduler → Lambda → AgentCore Runtime |

These patterns combine AWS event-driven services (EventBridge, SQS, S3 Events) with AgentCore Runtime invocation, enabling asynchronous and reactive agent workflows.

## Alternative Deployment Options

This workshop uses AgentCore as the primary deployment target. For teams with different infrastructure requirements, here are alternative deployment options per capability:

### Agent Runtime

| Option | Service | Best For |
|--------|---------|----------|
| AgentCore Runtime | Managed serverless | ✅ This workshop |
| EKS | Kubernetes | Multi-cloud, existing K8s clusters |
| ECS Fargate | Containers | Existing ECS infrastructure |
| Lambda + SnapStart | Serverless | Event-driven, sporadic usage |

### Memory

| Option | Service | Best For |
|--------|---------|----------|
| AgentCore Memory | Managed | ✅ This workshop |
| Aurora PostgreSQL | RDS + JdbcChatMemory | Full SQL control, existing RDS |
| DynamoDB | NoSQL | Serverless, simple key-value |
| S3 | Object storage | Stateless Lambda, conversation files |

### Knowledge (RAG)

| Option | Service | Best For |
|--------|---------|----------|
| Bedrock Knowledge Bases | Managed RAG | ✅ This workshop |
| Aurora + pgvector | RDS | Self-managed, full control |
| OpenSearch Serverless | Managed search | Hybrid search, large scale |

### MCP Services

| Option | Service | Best For |
|--------|---------|----------|
| AgentCore Gateway | Managed | ✅ This workshop |
| EKS Service | Kubernetes DNS | Existing K8s clusters |
| ECS Service | Cloud Map | Existing ECS infrastructure |
| Lambda | API Gateway / Lambda URL | Event-driven, per-service scaling |

### Browser Automation

| Option | Service | Best For |
|--------|---------|----------|
| AgentCore Browser | Managed | ✅ This workshop |
| Playwright on ECS/EKS | Self-managed | Custom browser requirements |

### Code Execution

| Option | Service | Best For |
|--------|---------|----------|
| AgentCore Code Interpreter | Managed Python sandbox | ✅ This workshop |
| GraalJS on ECS/EKS | Self-managed JavaScript | Custom runtime requirements |

### Deployment Path Comparison

| Factor | AgentCore (This Workshop) | EKS | ECS | Lambda |
|--------|---------------------------|-----|-----|--------|
| Ops overhead | ⭐ Low | High | Medium | ⭐ Low |
| Control | Low | ⭐ High | Medium | Low |
| Scaling | Auto | Manual/HPA | Auto | Auto |
| Cost model | Per-request | Per-hour | Per-hour | Per-invoke |
| Cold start | Optimized | None | Seconds | SnapStart |
| Portability | AWS only | ⭐ Multi-cloud | AWS | AWS |

### Local Development Alternatives

This workshop uses AgentCore services from the start. For local-first development:

| Capability | AgentCore (This Workshop) | Local Alternative |
|------------|---------------------------|-------------------|
| Memory | AgentCore Memory | PostgreSQL + Testcontainers |
| Knowledge | Bedrock Knowledge Bases | pgvector + Testcontainers |
| Browser | AgentCore Browser | Playwright (limited) |
| Code Execution | AgentCore Code Interpreter | GraalJS sandbox |

See the companion workshop "Building Java AI Agents with Spring AI" for a local-first approach with Testcontainers and multiple deployment paths.

---

# Resources

- [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)
- [AgentCore Developer Guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/)
- [AgentCore Control Plane API](https://docs.aws.amazon.com/bedrock-agentcore-control/latest/APIReference/Welcome.html)
- [AgentCore Data Plane API](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/Welcome.html)
- [Spring AI Documentation](https://docs.spring.io/spring-ai/reference/)
- [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
