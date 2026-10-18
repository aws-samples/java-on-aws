import path from 'node:path';

import { BedrockAgentCoreClient, InvokeCodeInterpreterCommand } from '@aws-sdk/client-bedrock-agentcore';
import { tool } from 'ai';
import { CodeInterpreter } from 'bedrock-agentcore/code-interpreter';
import { z } from 'zod';

import * as artifacts from './artifacts.js';

const client = new BedrockAgentCoreClient({ region: process.env.AWS_REGION });
const MEDIA_TYPES: Record<string, string> = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.csv': 'text/csv', '.json': 'application/json', '.pdf': 'application/pdf',
};

// >> Read a file from the sandbox as bytes: the `readFiles` operation returns binary files as a blob
async function readFile(sessionId: string, name: string): Promise<Uint8Array | undefined> {
  const response = await client.send(new InvokeCodeInterpreterCommand({
    codeInterpreterIdentifier: 'aws.codeinterpreter.v1', sessionId, name: 'readFiles', arguments: { paths: [name] },
  }));
  for await (const event of response.stream ?? []) {
    for (const item of event.result?.content ?? []) {
      if (item.resource?.blob) return item.resource.blob;
      if (item.resource?.text) return new TextEncoder().encode(item.resource.text);
    }
  }
  return undefined;
}
// <<

export const codeInterpreterTools = {
  executeCode: tool({
    description: 'Execute Python code in a secure sandbox with numpy, pandas, and matplotlib. Use for calculations, data analysis, and charts. Save generated files (for example a chart as PNG) to the current directory and list their file names in outputFiles to show them to the user.',
    inputSchema: z.object({
      code: z.string().describe('Python code to execute'),
      outputFiles: z.array(z.string()).optional().describe('Names of the files the code creates that the user should see'),
    }),
    execute: async ({ code, outputFiles = [] }) => {
      // >> Start an AgentCore Code Interpreter session and run the code
      const interpreter = new CodeInterpreter({ region: process.env.AWS_REGION });
      const session = await interpreter.startSession();
      try {
        const output = [await interpreter.executeCode({ code, language: 'python' })];
      // <<
        // >> Download the generated files and keep them for the user instead of returning them to the model
        for (const name of outputFiles) {
          const data = await readFile(session.sessionId, name);
          if (!data) {
            output.push(`File not found: ${name}`);
            continue;
          }
          artifacts.store(path.basename(name), data, MEDIA_TYPES[path.extname(name).toLowerCase()] ?? 'application/octet-stream');
          output.push(`${name} is shown to the user below your answer.`);
        }
        // <<
        return output.join('\n');
      } finally {
        await interpreter.stopSession();
      }
    },
  }),
};
