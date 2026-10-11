// Helpers for driving Code Editor in headless Chrome (used by ide.mjs).
import { chromium } from 'playwright-core';

const MASK = '123456789012';

// Chrome headless 1600x900 at 2x, signed in through the IdeUrl token.
export async function open(url) {
  const browser = await chromium.launch({
    channel: 'chrome', headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist', '--use-angle=metal'],
  });
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 2 });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(url).origin });
  const page = await ctx.newPage();
  await page.goto(url);
  await page.waitForSelector('.monaco-workbench', { timeout: 60000 });
  await page.waitForTimeout(6000);
  return { browser, page };
}

// F1 goes to a focused terminal: open the palette from the title bar's command center.
export async function palette(page, cmd) {
  await page.locator('.command-center-quick-pick').first().click();
  await page.waitForSelector('.quick-input-widget input', { state: 'visible' });
  await page.keyboard.type('>' + cmd, { delay: 10 });
  await page.waitForTimeout(900);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1200);
}

export async function typeInTerminal(page, text) {
  await page.locator('.editor-instance .xterm-helper-textarea, .terminal-wrapper.active .xterm-helper-textarea')
    .last().focus();
  await page.keyboard.type(text, { delay: 15 });
  await page.keyboard.press('Enter');
}

// Replace the account ID in every DOM text node before a screenshot.
export async function mask(page, account = process.env.WS_ACCOUNT) {
  if (!account) return;
  await page.evaluate(([a, m]) => {
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n; (n = w.nextNode());) if (n.nodeValue.includes(a)) n.nodeValue = n.nodeValue.replaceAll(a, m);
  }, [account, MASK]);
}

// Clear notifications and park the mouse on the empty activity bar (no hover tooltips).
export async function clearToasts(page) {
  await palette(page, 'Notifications: Clear All Notifications');
  await page.mouse.move(28, 820);
  await page.waitForTimeout(1500);
}
