import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
// >> Import `stepCountIs` to let the model call tools in a loop
import { stepCountIs, streamText } from 'ai';
// <<
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

// >> Import the Knowledge Base tool
import { searchKnowledgeBase } from './knowledge.js';
// <<
import * as memory from './memory.js';

const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });
const model = bedrock('global.anthropic.claude-sonnet-4-6');

const SYSTEM_PROMPT = `You are the travel and expense assistant of the company. You help employees plan business trips,
follow the travel and expense policies, and keep track of their trips and expenses.

Rules:
- Focus on business travel and expenses.
- Ask for missing details such as dates, origin, or destination instead of guessing them.
- Do not invent policy rules; say so when you are not sure.

Format:
- Be friendly and concise.
- Use tables to compare options.`;

// >> Tools available to the agent
const tools = {
  searchKnowledgeBase,
};
// <<

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),
    async *process(payload, context) {
      const conversationId = context.sessionId;
      const { actorId, sessionId } = memory.parse(conversationId);
      const prompt = payload.prompt;
      const [history, facts] = await Promise.all([memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt)]);
      const system = facts.length
        ? `${SYSTEM_PROMPT}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : SYSTEM_PROMPT;
      const result = streamText({
        model, system, temperature: 0.7, maxOutputTokens: 4096,
        messages: [...history, { role: 'user', content: prompt }],
// >> Register the tools; `stopWhen` lets the model call tools and continue for up to 10 steps
        tools,
        stopWhen: stepCountIs(10),
// <<
      });
      let answer = '';
      for await (const text of result.textStream) {
        answer += text;
        yield text;
      }
      await memory.save(actorId, sessionId, payload.prompt, answer);
    },
  },
});

if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
