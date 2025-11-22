# DeepEval Service

This folder contains the DeepEval evaluation service for testing AI responses.

## Files
- `Dockerfile` - Docker image definition for the DeepEval service
- `deepeval_service.py` - Flask REST API service for DeepEval metrics
- `README.md` - This file

## Build and Run

```bash
# Build the Docker image
cd deep-eval
docker build -t deepeval-service:latest .

# Run manually (optional)
docker run -p 8080:8080 deepeval-service:latest
```

## API Endpoints

- `GET /health` - Health check
- `POST /evaluate` - Evaluate response relevancy

### Evaluate Request
```json
{
  "question": "What is AI?",
  "response": "AI is artificial intelligence...",
  "threshold": 0.3
}
```

### Evaluate Response
```json
{
  "score": 0.85,
  "success": true,
  "threshold": 0.3,
  "reason": "Response is relevant to the question"
}
```