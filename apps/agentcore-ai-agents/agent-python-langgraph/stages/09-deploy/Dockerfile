# >> Python 3.13 base image with uv for dependency installation
FROM public.ecr.aws/docker/library/python:3.13-slim-trixie
RUN pip install --no-cache-dir uv
# <<

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 \
    UV_NO_PROGRESS=1 \
    PYTHONUNBUFFERED=1 \
    DOCKER_CONTAINER=1 \
    PATH="/app/.venv/bin:$PATH"

RUN useradd -m -u 1000 bedrock_agentcore

# >> Install the locked dependencies first, so code changes reuse the cached layer
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
# <<

COPY --chown=bedrock_agentcore:bedrock_agentcore . .
USER bedrock_agentcore

# >> AgentCore Runtime calls the HTTP service on port 8080
EXPOSE 8080
# <<
# >> `opentelemetry-instrument` starts ADOT and the LangChain instrumentation before the application; AgentCore Runtime provides the exporter settings
CMD ["opentelemetry-instrument", "python", "main.py"]
# <<
