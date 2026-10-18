# >> Node.js 22 base image
FROM public.ecr.aws/docker/library/node:22-slim
# <<

WORKDIR /app
ENV NODE_ENV=production \
    DOCKER_CONTAINER=1

RUN userdel -r node 2>/dev/null || true
RUN useradd -m -u 1000 bedrock_agentcore

# >> Install the locked dependencies first, so code changes reuse the cached layer
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
# <<

COPY --chown=bedrock_agentcore:bedrock_agentcore . .
USER bedrock_agentcore

# >> AgentCore Runtime calls MCP servers on port 8000 at `/mcp`; `tsx` runs the TypeScript code directly
EXPOSE 8000
CMD ["npx", "tsx", "server.ts"]
# <<
