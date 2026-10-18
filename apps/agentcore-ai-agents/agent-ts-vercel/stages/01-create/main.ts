import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
import { streamText } from 'ai';
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

// >> The Amazon Bedrock provider of the AI SDK, with credentials from the default AWS credential chain
const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });
const model = bedrock('global.anthropic.claude-sonnet-4-6');
// <<

// >> `BedrockAgentCoreApp` is an HTTP service with the `/invocations` and `/ping` endpoints; `requestSchema` validates the request body
const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),
// <<
    // >> `streamText()` streams the model output; each yielded chunk is sent as a server-sent event
    async *process(payload) {
      const result = streamText({ model, prompt: payload.prompt, maxOutputTokens: 4096 });
      for await (const text of result.textStream) {
        yield text;
      }
    },
    // <<
  },
});

// >> Serve the Web UI from the `static` folder in local mode (the container image has no `static` folder)
if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}
// <<

app.run({ port: Number(process.env.PORT ?? 8080) });
