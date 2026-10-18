import { BedrockAgentRuntimeClient, RetrieveCommand } from '@aws-sdk/client-bedrock-agent-runtime';
import { tool } from 'ai';
import { z } from 'zod';

// >> Knowledge Base ID from `~/environment/.envrc`
const KNOWLEDGE_BASE_ID = process.env.KNOWLEDGE_BASE_ID!;
// <<
const kb = new BedrockAgentRuntimeClient({ region: process.env.AWS_REGION });

// >> `tool()` defines a tool: the description tells the model when to call it, the zod schema describes the parameters
export const searchKnowledgeBase = tool({
  description: 'Search the company travel and expense policies. Use for questions about rules, limits, and approvals.',
  inputSchema: z.object({ query: z.string().describe('What to look up in the policies') }),
// <<
  execute: async ({ query }) => {
    // >> Retrieve the most relevant policy chunks from the Knowledge Base
    const response = await kb.send(new RetrieveCommand({
      knowledgeBaseId: KNOWLEDGE_BASE_ID,
      retrievalQuery: { text: query },
      retrievalConfiguration: { vectorSearchConfiguration: { numberOfResults: 5 } },
    }));
    // <<
    const results = response.retrievalResults ?? [];
    if (results.length === 0) {
      return 'No relevant policy found.';
    }
    // >> Return each chunk with its source document, so the model can cite the policy
    return results
      .map((r) => `${r.content?.text}\n(Source: ${r.location?.s3Location?.uri ?? 'unknown'})`)
      .join('\n\n');
    // <<
  },
});
