## Preparation

> In the main terminal:

```bash
mkdir spring-ai-demo
code spring-ai-demo/
```

```bash
git clone https://github.com/aws-samples/java-on-aws.git ./java-on-aws
export SOURCES_FOLDER=$(pwd)/java-on-aws/samples/spring-ai
export AWS_REGION=us-east-1
```

> add AWS credential to the main terminal

## Spring AI project setup

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/01-setup-project.sh
```

## Add ChatController and UI

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/02-add-api-ui.sh
```

> In the new terminal:
> add AWS credential to the terminal

```bash
export AWS_REGION=us-east-1
cd assistant/
./mvnw spring-boot:run
```

> What is my name?

> My name is ...

## Add Memory

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/03-add-memory.sh
```

> In the new terminal

```bash
cd database/
./start-postgres.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

> my name is ...

> What is my name?

> What is our travel and expenses policy?

## Add RAG

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/04-add-rag.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

> In the main terminal:

```bash
code $SOURCES_FOLDER/assistant/samples/travel_and_expenses_policy.md
curl -X POST \
  -H "Content-Type: text/plain" \
  --data-binary @$SOURCES_FOLDER/assistant/samples/travel_and_expenses_policy.md \
  http://localhost:8080/api/rag-load
```

> What is our travel and expenses policy?

> What is the date today?

## Add Tools

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/05-add-tools.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

> What is the date today?

> What is the weather in Paris next Monday?

## Add MCP

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/06-add-mcp.sh
```

> In the new terminal

```bash
cd travel/
./start-postgres.sh
```

> In the new terminal (optional):

```bash
cd backoffice/
./start-postgres.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

> What is the weather in Paris next Monday?

> Could you please book me a flight from London to Paris and back, from next Monday to next Friday?

> I would take BA flights

> John Doe, john@example.com, 1, 1

> Please book me accommodation

> Could you please give me a summary of travel?
