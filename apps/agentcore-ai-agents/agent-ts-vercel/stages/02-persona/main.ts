import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
import { streamText } from 'ai';
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });
const model = bedrock('global.anthropic.claude-sonnet-5-5');

// >> The system prompt defines the persona of the AI agent
const SYSTEM_PROMPT = `You are the travel and expense assistant of the company. You help employees plan business trips,
follow the travel and expense policies, and keep track of their trips and expenses.

Rules:
- Focus on business travel and expenses.
- Ask for missing details such as dates, origin, or destination instead of guessing them.
- Do not invent policy rules; say so when you are not sure.

Format:
- Be friendly and concise.
- Use tables to compare options.`;
// <<

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),
    async *process(payload) {
      const result = streamText({
        // >> `system` applies the prompt to all requests
        model, system: SYSTEM_PROMPT, maxOutputTokens: 4096, prompt: payload.prompt,
        // <<
      });
      for await (const text of result.textStream) {
        yield text;
      }
    },
  },
});

if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
