import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
import { stepCountIs, streamText } from 'ai';
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

import * as artifacts from './artifacts.js';
// >> Import JWT validation and the conversation ID resolver
import * as auth from './auth.js';
// <<
import { browserTools } from './browser-tools.js';
import { codeInterpreterTools } from './code-interpreter-tools.js';
import { searchKnowledgeBase } from './knowledge.js';
import { gatewayTools } from './mcp-tools.js';
import * as memory from './memory.js';

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
- Use tables to compare options.

Flight and hotel offers: the corporate travel portal ${process.env.PORTAL_URL}`;

const tools = {
  searchKnowledgeBase,
  ...browserTools,
  ...codeInterpreterTools,
  ...(await gatewayTools()),
};

function withContext(prompt: string, conversationId: string) {
  const now = new Date();
  const timestamp = `${now.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' })}, ${now.toISOString().slice(0, 16).replace('T', ' ')}`;
  const userId = conversationId.split(':')[0];
  return `[Current date and time: ${timestamp}] [UserId: ${userId}]\n${prompt}`;
}

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),
    async *process(payload, context) {
// >> The conversation ID combines the Cognito user ID from the JWT with the session ID
      const conversationId = auth.conversationId(context);
// <<
      artifacts.currentSession.enterWith(conversationId);
      const { actorId, sessionId } = memory.parse(conversationId);
      const prompt = withContext(payload.prompt, conversationId);
      const [history, facts] = await Promise.all([memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt)]);
      const system = facts.length
        ? `${SYSTEM_PROMPT}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : SYSTEM_PROMPT;
      const result = streamText({
        model, system, maxOutputTokens: 4096,
        messages: [...history, { role: 'user', content: prompt }],
        tools,
        stopWhen: stepCountIs(10),
      });
      let answer = '';
      for await (const text of result.textStream) {
        answer += text;
        yield text;
      }
      const files = await artifacts.asMarkdown(conversationId);
      if (files) {
        yield files;
      }
      await memory.save(actorId, sessionId, payload.prompt, answer);
    },
  },
});

// >> Require a valid Cognito JWT for `/invocations` when `COGNITO_ISSUER_URI` is set
auth.requireJwt(app['_app']);
// <<
if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
