import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
import { streamText } from 'ai';
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

// >> Import the AgentCore Memory functions
import * as memory from './memory.js';
// <<

const bedrock = createAmazonBedrock({ region: process.env.AWS_REGION, credentialProvider: fromNodeProviderChain() });
const model = bedrock('global.anthropic.claude-sonnet-5-5');

const SYSTEM_PROMPT = `You are the travel and expense assistant of the company. You help employees plan business trips,
follow the travel and expense policies, and keep track of their trips and expenses.

Rules:
- Focus on business travel and expenses.
- Ask for missing details such as dates, origin, or destination instead of guessing them.
- Do not invent policy rules; say so when you are not sure.

Format:
- Be friendly and concise.
- Use tables to compare options.`;


const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),
    async *process(payload, context) {
// >> `context.sessionId` is the `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` header. In local mode, the Web UI sends the login username as the session ID
      const conversationId = context.sessionId;
      const { actorId, sessionId } = memory.parse(conversationId);
// <<
      const prompt = payload.prompt;
// >> Load the session history (short-term memory) and the facts about the user (long-term memory) in parallel
      const [history, facts] = await Promise.all([memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt)]);
      const system = facts.length
        ? `${SYSTEM_PROMPT}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : SYSTEM_PROMPT;
// <<
      const result = streamText({
        model, system, maxOutputTokens: 4096,
// >> Send the history and the new message
        messages: [...history, { role: 'user', content: prompt }],
// <<
      });
      let answer = '';
      for await (const text of result.textStream) {
        answer += text;
        yield text;
      }
// >> Save the turn; AgentCore Memory extracts facts and preferences from it
      await memory.save(actorId, sessionId, payload.prompt, answer);
// <<
    },
  },
});

if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
