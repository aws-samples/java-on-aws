import { existsSync } from 'node:fs';
import path from 'node:path';

import { createAmazonBedrock } from '@ai-sdk/amazon-bedrock';
import { fromNodeProviderChain } from '@aws-sdk/credential-providers';
import fastifyStatic from '@fastify/static';
#!knowledge
import { streamText } from 'ai';
#-
#+knowledge Import `stepCountIs` to let the model call tools in a loop
import { stepCountIs, streamText } from 'ai';
#-
import { BedrockAgentCoreApp } from 'bedrock-agentcore/runtime';
import { z } from 'zod';

#+browser Import the artifact store and the browser tools
import * as artifacts from './artifacts.js';
#-
#+document-processing Import the attachment handling
import * as attachments from './attachments.js';
#-
#+deploy Import JWT validation and the conversation ID resolver
import * as auth from './auth.js';
#-
#+browser
import { browserTools } from './browser-tools.js';
#-
#+identity Import the corporate calendar tool
import * as calendar from './calendar-tools.js';
#-
#+code-interpreter Import the code interpreter tool
import { codeInterpreterTools } from './code-interpreter-tools.js';
#-
#+agent-as-tool Import the compliance auditor tool
import { complianceTools } from './compliance-tools.js';
#-
#+guardrails Import the guardrail configuration and checks
import * as guardrail from './guardrail.js';
#-
#+knowledge Import the Knowledge Base tool
import { searchKnowledgeBase } from './knowledge.js';
#-
#+mcp-client!policies Import the Gateway tools
import { gatewayTools } from './mcp-tools.js';
#-
#+policies Import the Gateway tools of both Gateways
import { gatewayTools, userGatewayTools } from './mcp-tools.js';
#-
#+memory Import the AgentCore Memory functions
import * as memory from './memory.js';
#-
#+optimize Import the system prompt from the configuration bundle
import * as promptConfig from './prompt-config.js';
#-
#+tools!mcp-client Import the web grounding tool (until the Gateway web search replaces it)
import { searchWeb } from './web-grounding.js';
#-

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
#!browser
- Use tables to compare options.`;
#-
#+browser Tell the model where to find flight and hotel offers
- Use tables to compare options.

Flight and hotel offers: the corporate travel portal ${process.env.PORTAL_URL}`;
#-

#+knowledge Tools available to the agent
const tools = {
  searchKnowledgeBase,
#-
#+tools!mcp-client Add the web grounding tool
  searchWeb,
#-
#+browser Add the browser tools
  ...browserTools,
#-
#+code-interpreter Add the code interpreter tool
  ...codeInterpreterTools,
#-
#+mcp-client Add the Gateway tools, discovered once at startup
  ...(await gatewayTools()),
#-
#+agent-as-tool Add the compliance auditor tool when `AUDITOR_HARNESS_ARN` is set
  ...complianceTools,
#-
#+identity Add the calendar tool when `CALENDAR_URL` is set
  ...calendar.calendarTools,
#-
#+knowledge
};
#-
#+tools Add context to every prompt: the model always knows the date and the user without a tool call

function withContext(prompt: string, conversationId: string) {
  const timestamp = new Date().toISOString().slice(0, 19);
  const userId = conversationId.split(':')[0];
  return `[Current date and time: ${timestamp}] [UserId: ${userId}]\n${prompt}`;
}
#-

const app = new BedrockAgentCoreApp({
  invocationHandler: {
#!identity
    requestSchema: z.object({ prompt: z.string() }),
#-
#+identity!document-processing The callback page sends `oauthSession` without a prompt
    requestSchema: z.object({ prompt: z.string().default(''), oauthSession: z.string().optional() }),
#-
#+document-processing The UI sends an attached file as `fileName` and `fileBase64`; `zod` drops fields that the schema does not list
    requestSchema: z.object({
      prompt: z.string().default(''), oauthSession: z.string().optional(),
      fileName: z.string().optional(), fileBase64: z.string().optional(),
    }),
#-
    async *process(payload, context) {
#!deploy
      const conversationId = context.sessionId;
#-
#+deploy The conversation ID combines the Cognito user ID from the JWT with the session ID
      const conversationId = auth.conversationId(context);
#-
#+browser Tools that run during this request store their files under the conversation ID
      artifacts.currentSession.enterWith(conversationId);
#-
#+identity Tools act on behalf of this user; the callback page sends the consent session back
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
#-
#+guardrails Mask payment data before the model, the memory, and the long-term memory search see the prompt
      payload.prompt = await guardrail.maskPii(payload.prompt);
#-
#+memory `context.sessionId` is the `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` header. In local mode, the Web UI sends the login username as the session ID
      const { actorId, sessionId } = memory.parse(conversationId);
#-
#!tools
      const prompt = payload.prompt;
#-
#+tools Add the current date and time and the user ID to the prompt
      const prompt = withContext(payload.prompt, conversationId);
#-
#+memory!optimize Load the session history (short-term memory) and the facts about the user (long-term memory) in parallel
      const [history, facts] = await Promise.all([memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt)]);
      const system = facts.length
        ? `${SYSTEM_PROMPT}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : SYSTEM_PROMPT;
#-
#+optimize Take the system prompt from the configuration bundle when `CONFIG_BUNDLE_ID` is set
      const [history, facts, instructions] = await Promise.all([
        memory.history(actorId, sessionId), memory.facts(actorId, payload.prompt), promptConfig.systemPrompt(SYSTEM_PROMPT),
      ]);
      const system = facts.length
        ? `${instructions}\nWhat you know about the user:\n${facts.map((f) => `- ${f}`).join('\n')}`
        : instructions;
#-
      const result = streamText({
        model, system, maxOutputTokens: 4096,
#+memory!guardrails Send the history and the new message
        messages: [...history, { role: 'user', content: prompt }],
#-
#+guardrails!document-processing The guardrail evaluates only the new message (`guardContent`), not the history from memory
        messages: [...history, guardrail.userMessage(prompt)],
#-
#+document-processing The new message with the attached file; the text part keeps `guardContent`
        messages: [...history, await attachments.userMessage(prompt, payload)],
#-
#+knowledge!policies Register the tools; `stopWhen` lets the model call tools and continue for up to 10 steps
        tools,
#-
#+policies Add the backoffice tools of the JWT Gateway for this user
        tools: { ...tools, ...(await userGatewayTools(authorization)) },
#-
#+knowledge
        stopWhen: stepCountIs(10),
#-
#+guardrails Apply the guardrail to the model call
        providerOptions: guardrail.providerOptions,
#-
      });
      let answer = '';
      for await (const text of result.textStream) {
        answer += text;
        yield text;
      }
#+browser Append screenshots and generated files as S3 links after the answer; they are not saved to memory
      const files = await artifacts.asMarkdown(conversationId);
      if (files) {
        yield files;
      }
#-
#+memory Save the turn; AgentCore Memory extracts facts and preferences from it
      await memory.save(actorId, sessionId, payload.prompt, answer);
#-
    },
  },
});

#+deploy Require a valid Cognito JWT for `/invocations` when `COGNITO_ISSUER_URI` is set
auth.requireJwt(app['_app']);
#-
if (existsSync('static')) {
  await app['_app'].register(fastifyStatic, { root: path.resolve('static') });
}

app.run({ port: Number(process.env.PORT ?? 8080) });
