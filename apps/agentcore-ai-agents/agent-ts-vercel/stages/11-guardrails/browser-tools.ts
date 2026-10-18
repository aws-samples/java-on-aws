import { tool } from 'ai';
import { PlaywrightBrowser } from 'bedrock-agentcore/browser/playwright';
import { z } from 'zod';

import * as artifacts from './artifacts.js';
// >> Import the guardrail check for tool output
import * as guardrail from './guardrail.js';
// <<

async function withPage<T>(url: string, action: (browser: PlaywrightBrowser) => Promise<T>): Promise<T> {
  const browser = new PlaywrightBrowser({ region: process.env.AWS_REGION });
  await browser.startSession();
  try {
    console.log(`Navigating to: ${url}`);
    await browser.navigate({ url, waitUntil: 'domcontentloaded' });
    return await action(browser);
  } finally {
    await browser.stopSession();
  }
}

export const browserTools = {
  browseUrl: tool({
    description: 'Browse a web page and extract its text content. Returns the page text. Use this to read and extract data from websites.',
    inputSchema: z.object({ url: z.string().describe('The URL to open') }),
    // >> Check the page text with the guardrail before the model reads it
    execute: ({ url }) => withPage(url, async (browser) => guardrail.checkContent((await browser.getText()).slice(0, 20000))),
    // <<
  }),
  takeScreenshot: tool({
    description: 'Take a screenshot of a web page for the user to see. Does NOT return page content to you. Use browseUrl to extract data first, then takeScreenshot for visual evidence.',
    inputSchema: z.object({ url: z.string().describe('The URL to capture') }),
    execute: ({ url }) => withPage(url, async (browser) => {
      const png = await browser.screenshot();
      artifacts.store('screenshot.png', Buffer.from(png as Buffer), 'image/png');
      return 'Screenshot taken. It is shown to the user below your answer.';
    }),
  }),
};
