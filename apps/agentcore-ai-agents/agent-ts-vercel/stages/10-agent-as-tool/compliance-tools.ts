import { randomUUID } from 'node:crypto';

import { BedrockAgentCoreClient, InvokeHarnessCommand } from '@aws-sdk/client-bedrock-agentcore';
import { tool, type ToolSet } from 'ai';
import { z } from 'zod';

import * as artifacts from './artifacts.js';

const AUDITOR_HARNESS_ARN = process.env.AUDITOR_HARNESS_ARN;
// Report links of the auditor: "Report: <https://.../artifacts/...>", "Report: https://...", or a Markdown link [name](https://...)
const REPORT_LINK = /\s*(?:Report:\s*)?<?(?:!?\[[^\]]*\]\()?(https:\/\/[^\s)>]+\/artifacts\/[^\s)>]+)[)>]?/g;

const agentcore = new BedrockAgentCoreClient({ region: process.env.AWS_REGION });

export async function askAuditor(request: string) {
  // >> InvokeHarness runs the auditor's agent loop on AgentCore; one session per check (at least 33 characters)
  const response = await agentcore.send(new InvokeHarnessCommand({
    harnessArn: AUDITOR_HARNESS_ARN,
    runtimeSessionId: randomUUID(),
    messages: [{ role: 'user', content: [{ text: request }] }],
  }));
  // <<
  const parts: string[] = [];
  try {
    // >> The answer arrives as a stream of events; collect the text deltas
    for await (const event of response.stream ?? []) {
      const delta = event.contentBlockDelta?.delta;
      if (delta?.text) {
        parts.push(delta.text);
      }
    }
    // <<
  } catch (error) {
    return `Policy auditor error: ${(error as Error).message}`;
  }
  return parts.join('');
}

// Move the auditor's report links to this agent's answer, so the model doesn't have to copy long URLs
export function forwardLinks(text: string) {
  const links = [...text.matchAll(REPORT_LINK)].map((m) => m[1]);
  // >> The links are appended after the answer, like screenshots and charts
  for (const url of links) {
    artifacts.storeLink('audit-report.md', url, 'text/markdown');
  }
  // <<
  if (!links.length) {
    return text;
  }
  return `${text.replace(REPORT_LINK, '')}\n\n(The download link for the report is appended after your answer.)`;
}

// >> The auditor as a tool; registered only when `AUDITOR_HARNESS_ARN` is set
export const complianceTools: ToolSet = AUDITOR_HARNESS_ARN ? {
  check_compliance: tool({
    description: 'Ask the compliance auditor whether a planned trip or an expense complies with the company travel '
      + 'and expense policies. Returns COMPLIANT or NOT COMPLIANT with the rules that apply. When the user wants a '
      + 'downloadable audit report, ask for one in the request; its link is added to the answer automatically.',
    inputSchema: z.object({
      request: z.string().describe('The trip or expense to check, with all known details (route, travel class, dates, amount, currency)'),
    }),
    execute: async ({ request }) => forwardLinks(await askAuditor(request)),
  }),
} : {};
// <<
