## Preparation

> In the terminal:

```bash
mkdir spring-ai-agent
kiro spring-ai-agent/
```

In the new terminal (Main terminal):

```bash
# git clone https://github.com/aws-samples/java-on-aws.git ./java-on-aws
# export SOURCES_FOLDER=$(pwd)/java-on-aws/samples/spring-ai-te-agent

export SOURCES_FOLDER=../workshops/java-on-aws/samples/spring-ai-te-agent
cd $SOURCES_FOLDER
export SOURCES_FOLDER=$(pwd)
cd ../../../../spring-ai-agent
export AWS_REGION=us-east-1
```

> Ensure AWS credentials are available in this terminal

## 01. Create Spring AI App

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/01-create-app.sh
```

Open localhost:8080 in the browser and ask questions:

> My name in Alex, Who are you?
>> Claude
`Ctrl+C`
> My name in Alex, Who are you?
>> Travel assistant
> What is my name?
`Ctrl+C`

## Run the AI Agent

Open the new terminal (AI Agent terminal):

```bash
cd ai-agent
export AWS_REGION=us-east-1
```

> Ensure AWS credentials are available in this terminal

In the AI Agent terminal:

```bash
./mvnw spring-boot:run
```

## 02. Add Memory

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/02-add-memory.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> My name in Alex
> What is my name?

> What is our travel policy?

/summarize
`Ctrl+C`

## 03. Add RAG

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/03-add-rag.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

> In the main terminal:

```bash
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @ai-agent/samples/policy-travel.md \
  http://localhost:8080/api/admin/rag-load

curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @ai-agent/samples/policy-expense.md \
  http://localhost:8080/api/admin/rag-load

```

Open localhost:8080 in the browser and ask questions:

> What is our travel policy?

> What is the weather in Las Vegas tomorrow?

`Ctrl+C`

## 04. Add Tools

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/04-add-tools.sh
```

> In the AI Agent terminal:

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> What is the weather in Las Vegas tomorrow?

`Ctrl+C`

## 05. Add MCP

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/05-add-mcp.sh
```

**Microservice Architecture:**

- **Travel Service** (port 8082): Hotel and flight booking
- **AI Agent** (port 8080): Central AI assistant orchestrating all services

**Start the microservices in the following order:**

Open the new terminal (Travel terminal - port 8082):

```bash
cd travel/
./mvnw spring-boot:test-run
```

> **Note**: Travel services use `test-run` which automatically starts PostgreSQL containers with Testcontainers - no manual database setup required!

> In the AI Agent terminal (port 8080):

```bash
./mvnw spring-boot:test-run
```

Open localhost:8080 in the browser and ask questions:

> Please find me inbound and outbound flights and accommodations for a trip from London to Paris next week, From Monday to Friday. I travel alone, prefer BA flights in the first part of the day, and choose accommodation which is the most expensive, but comply with our travel policy.
Give me a travel itinerary with flights, accommodation, prices and weather forecast for each day of the travel.

`Ctrl+C`

## 06. Add Multi-model, Multi-modal

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/06-add-multi.sh
```

- **Backoffice Service** (port 8083): Expense management and currency conversion

Open the new terminal (Backoffice terminal - port 8083):

```bash
cd backoffice/
./mvnw spring-boot:test-run
```

---

## Maintenance Prompt for AI Assistant

Use this prompt to update demo scripts when the sample app changes:

```
Task: Update demo scripts, flow, and Step files to match the current sample app.

Context:
- Sample app: workshops/java-on-aws/samples/spring-ai-te-agent
- Demo destination: spring-ai-agent (cleared in script 01)
- Demo scripts: workshops/java-on-aws/samples/spring-ai-te-agent/demo-scripts
- Step files: workshops/java-on-aws/samples/spring-ai-te-agent/demo-scripts/Steps

Requirements:
1. Script 01 must clear destination directory completely before starting
2. All Step files must use streaming (Flux<String>) to match final sample app
3. Progressive build flow:
   - Step 0: Basic streaming agent (ChatService.java.0, ChatController.java.0, WebViewController.java.1)
   - Step 1: + System prompt (ChatService.java.1) - use spring-boot:run (no DB yet)
   - Step 2: + Memory + Multi-user + Summary (ChatService.java.2, ChatController.java.2, WebViewController.java.2) - add testcontainers/postgresql deps
   - Step 3: + RAG (ChatService.java.3)
   - Step 4: + Tools DateTime + Weather (ChatService.java.4)
   - Step 5: + MCP Travel server only (ChatService.java.5) - Weather is @Tool, not MCP
   - Step 6: + Multi-modal + Backoffice server (final ChatController, WebViewController)

4. System prompts progression:
   - Steps 1-2: "travel management" + markdown + "I don't know"
   - Step 3: + "Use provided context for company policies"
   - Step 4: + "Use tools for dynamic data (weather, dates)"
   - Step 5: + "Use tools for dynamic data (flights, weather, bookings)"
   - Step 6: "travel and expenses management" + "Use tools for dynamic data (flights, weather, bookings, currency)"

5. Models must match sample app application.properties:
   - Chat model: global.anthropic.claude-sonnet-4-20250514-v1:0
   - Document model: global.anthropic.claude-sonnet-4-5-20250929-v1:0

6. MCP servers (no weather MCP):
   - server2: Travel (port 8082)
   - server3: Backoffice (port 8083)

7. File paths in demo-flow.md must use $SOURCES_FOLDER for absolute paths
8. RAG endpoint: /api/admin/rag-load with policy-travel.md file
9. Spring initializr deps: Step 1 uses spring-ai-bedrock-converse,web,thymeleaf; Step 2 adds testcontainers,postgresql

Verify: Final ChatService.java.5 must match sample app ChatService.java exactly (use diff to confirm).
```

