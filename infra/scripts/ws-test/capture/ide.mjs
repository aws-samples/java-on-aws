// ide.mjs tools|scm OUT_DIR — Code Editor screenshots (run through ide.sh, which prepares
// the IDE and sets IDE_URL and WS_ACCOUNT).
//
//   tools  Claude Code in a fresh editor-area terminal lists the MCP tools of perf-sensor and
//          eks-mcp, the Shell terminal in the panel -> OUT_DIR/tools.png. Starts interactive
//          Claude sessions (two, see below): never while a ws-test runs.
//   open   the IDE as it opens: Explorer, the editor-area terminal, the Shell terminal
//          -> OUT_DIR/open.png
//   scm    the Source Control view with SCM_FILE's diff open (default deployment.yaml)
//          -> OUT_DIR/scm.png
import { join } from 'node:path';
import { open, palette, typeInTerminal, mask, clearToasts } from './ide-lib.mjs';

const [what, out = '.'] = process.argv.slice(2);
const { browser, page } = await open(process.env.IDE_URL);

if (what === 'open') {
  await page.waitForTimeout(6000);
} else if (what === 'tools') {
  // The first terminal that runs Claude Code activates its VS Code extension, which then
  // asks to relaunch that terminal and marks its tab with a warning badge for the rest of
  // the session. So: run Claude once in a throwaway terminal, close it, and take the shot in
  // a second one, where the extension's variables are set at creation and no badge appears.
  const newTerminal = () =>
    page.locator('.editor-group-container .editor-actions .codicon-plus').first().click();
  await page.locator('.editor-group-container .tab', { hasText: 'zsh' }).first().click();
  await page.waitForTimeout(800);
  await newTerminal();
  await page.waitForTimeout(4000);
  await typeInTerminal(page, 'claude');
  await page.waitForTimeout(18000);
  await typeInTerminal(page, '/exit');
  await page.waitForTimeout(4000);
  await typeInTerminal(page, 'exit');       // closes the throwaway terminal and its tab
  await page.waitForTimeout(3000);
  await newTerminal();
  await page.waitForTimeout(4000);
  await typeInTerminal(page, 'claude');
  await page.waitForTimeout(15000);
  await typeInTerminal(page, 'List the MCP tools you can see from perf-sensor and eks-mcp, names only.');
  const rows = page.locator('.editor-instance .xterm-rows').last();
  for (let i = 0; i < 60; i++) {
    await page.waitForTimeout(3000);
    const t = await rows.innerText().catch(() => '');
    if (/startupLog/.test(t) && /checklist/.test(t) && /eks/i.test(t.split('startupLog')[1] || '')) break;
  }
  await page.waitForTimeout(5000);
} else if (what === 'scm') {
  await palette(page, 'View: Show Source Control');
  await page.waitForTimeout(4000);
  await page.locator('.scm-view .monaco-list-row', { hasText: process.env.SCM_FILE ?? 'deployment.yaml' })
    .first().click();
  await page.waitForTimeout(5000);
} else {
  console.error('usage: node ide.mjs open|tools|scm OUT_DIR');
  await browser.close();
  process.exit(2);
}

// Progress notifications (the Java extension's "Opening Java Projects") survive Clear All:
// IDE_SETTLE_MS waits for them to finish first.
await page.waitForTimeout(Number(process.env.IDE_SETTLE_MS ?? 0));
await clearToasts(page);
await page.waitForTimeout(1000);
await mask(page);
await page.screenshot({ path: join(out, `${what}.png`) });
if (what === 'tools') {
  await typeInTerminal(page, '/exit');
  await page.waitForTimeout(3000);
}
await browser.close();
console.log(`saved ${what}.png`);
