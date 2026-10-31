import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
import { stepCountIs, streamText } from 'ai';
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

import * as artifacts from './artifacts.js';
import * as attachments from './attachments.js';
import * as auth from './auth.js';
import { browserTools } from './browser-tools.js';
import * as calendar from './calendar-tools.js';
import { codeInterpreterTools } from './code-interpreter-tools.js';
import { complianceTools } from './compliance-tools.js';
import * as guardrail from './guardrail.js';
import { searchKnowledgeBase } from './knowledge.js';
// >> Import the Gateway tools of both Gateways
import { gatewayTools, userGatewayTools } from './mcp-tools.js';
// <<
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
  ...complianceTools,
  ...calendar.calendarTools,
};

function withContext(prompt: string, conversationId: string) {
  const timestamp = new Date().toISOString().slice(0, 19);
  const userId = conversationId.split(':')[0];
  return `[Current date and time: ${timestamp}] [UserId: ${userId}]\n${prompt}`;
}

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({
      prompt: z.string().default(''), oauthSession: z.string().optional(),
      fileName: z.string().optional(), fileBase64: z.string().optional(),
    }),
    async *process(payload, context) {
      const conversationId = auth.conversationId(context);
      artifacts.currentSession.enterWith(conversationId);
      const authorization = context.headers.authorization ?? '';
      calendar.currentUser.enterWith({
        userId: conversationId.split(':')[0],
        bearer: authorization.startsWith('Bearer ') ? authorization : '',
        workloadToken: context.workloadAccessToken,
      });
      if (payload.oauthSession) {
        await calendar.completeAuthorization(payload.oauthSession);
        yield 'The corporate calendar is connected. Send your question again.';
        return;
      }
      payload.prompt = await guardrail.maskPii(payload.prompt);
      const { actorId, sessionId } = memory.parse(conversationId);
      const prompt = withContext(payload.prompt, conversationId);
      const [history, facts] = await Promise.all([memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt)]);
      const system = facts.length
        ? `${SYSTEM_PROMPT}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : SYSTEM_PROMPT;
      const result = streamText({
        model, system, maxOutputTokens: 4096,
        messages: [...history, await attachments.userMessage(prompt, payload)],
// >> Add the backoffice tools of the JWT Gateway for this user
        tools: { ...tools, ...(await userGatewayTools(authorization)) },
// <<
        stopWhen: stepCountIs(10),
        providerOptions: guardrail.providerOptions,
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

auth.requireJwt(app['_app']);
if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
