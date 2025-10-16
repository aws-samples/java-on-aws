## Preparation

> In the terminal:

```bash
mkdir spring-ai-demo
code spring-ai-demo/
```

In the new terminal (Main terminal):

```bash
git clone https://github.com/aws-samples/java-on-aws.git ./java-on-aws
export SOURCES_FOLDER=$(pwd)/java-on-aws/samples/spring-ai-demo
```

## 01. Create Spring AI App

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/01-create-app.sh
```

## Run the assistant

Open the new terminal (Assistant terminal):

```bash
cd assistant
export AWS_REGION=us-east-1
```

> add AWS credential to the main terminal

In the Assistant terminal:

```bash
./mvnw spring-boot:run
```

Open localhost:8080 in the browser and ask questions:

> Who are you?

> What is our company name?

## 02. Add Memory

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/02-add-memory.sh
```

Open the new terminal (Database terminal):

```bash
cd database/
./start-postgres.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

Open localhost:8080 in the browser and ask questions:

> Our company name is Company1

> What is our company name?

> What is our travel and expenses policy?

## 03. Add RAG

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/03-add-rag.sh
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

Open localhost:8080 in the browser and ask questions:

> What is our travel and expenses policy?

> What is the date today?

## 04. Add Tools

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/04-add-tools.sh
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

Open localhost:8080 in the browser and ask questions:

> What is the date today?

> What is the weather in Paris next Monday?

## 05. Add MCP

> In the main terminal:

```bash
$SOURCES_FOLDER/demo-scripts/05-add-mcp.sh
```

Open the new terminal (Travel terminal):

```bash
cd travel/
./mvnw spring-boot:run
```

Open the new terminal (Backoffice terminal):

```bash
cd backoffice/
./mvnw spring-boot:run
```

> In the assistant terminal:

```bash
./mvnw spring-boot:run
```

Open localhost:8080 in the browser and ask questions:

> What is the weather in Paris next Monday?

> Could you please book me a flight from London to Paris and back, from next Monday to next Friday?

> I would take BA flights

> John Doe, john@example.com, 1, 1

> Please book me accommodation

> Could you please give me a summary of travel?
