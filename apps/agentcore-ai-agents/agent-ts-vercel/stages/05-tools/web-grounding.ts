import { BedrockRuntimeClient, ConverseCommand } from '@aws-sdk/client-bedrock-runtime';
import { tool } from 'ai';
import { z } from 'zod';

// >> Configurable model ID with Amazon Nova 2 Lite as default
const MODEL_ID = process.env.WEB_GROUNDING_MODEL ?? 'us.amazon.nova-2-lite-v1:0';
// <<
const bedrock = new BedrockRuntimeClient({ region: process.env.AWS_REGION });

export const searchWeb = tool({
  description: 'Search the web for current information. Use for news, real-time data, or facts needing verification.',
  inputSchema: z.object({ query: z.string().describe('Search query') }),
  execute: async ({ query }) => {
    console.log(`Web search: ${query}`);
    try {
      // >> Use the `nova_grounding` system tool through the Bedrock Converse API
      const response = await bedrock.send(new ConverseCommand({
        modelId: MODEL_ID,
        messages: [{ role: 'user', content: [{ text: query }] }],
        toolConfig: { tools: [{ systemTool: { name: 'nova_grounding' } }] },
      }));
      // <<
      const text: string[] = [];
      const sources: string[] = [];
      for (const block of response.output?.message?.content ?? []) {
        text.push(block.text ?? '');
        // >> Collect the web citations as sources
        for (const citation of block.citationsContent?.citations ?? []) {
          const url = citation.location?.web?.url;
          if (url) sources.push(`- ${url}`);
        }
        // <<
      }
      const result = text.join('') || 'No results found.';
      return sources.length ? `${result}\n\nSources:\n${sources.join('\n')}` : result;
    } catch (e) {
      console.error(`Web search failed: ${e}`);
      return 'Web search failed. Try again later.';
    }
  },
});
