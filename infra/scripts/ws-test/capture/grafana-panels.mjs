// grafana-panels.mjs REPORT_DIR SHOTS_JSON [OUT_DIR] — screenshots of a Grafana dashboard
// at fixed windows of a finished run, cropped to the panels (no menu, no time picker).
//
// SHOTS_JSON: [{"name": "baseline-grafana", "from": "<ISO UTC>", "to": "<ISO UTC>"}, ...]
// The Grafana URL and password come from the run's output.log (the content's
// "Open Grafana" block prints "URL: http://..." and "Password: ..."), or from
// GRAFANA_HOST and GRAFANA_PW. GRAFANA_DASH overrides the dashboard path.
// Chrome headless (channel chrome), 1881x1003 at 1.6x: Chrome at 80 % on a 2x screen.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright-core';

const [report, shotsJson, out = '.'] = process.argv.slice(2);
if (!report || !shotsJson) {
  console.error('usage: node grafana-panels.mjs REPORT_DIR SHOTS_JSON [OUT_DIR]');
  process.exit(2);
}
const log = readFileSync(join(report, 'output.log'), 'utf8');
const host = process.env.GRAFANA_HOST ?? log.match(/^URL:\s+http:\/\/(\S+)/m)?.[1];
const password = process.env.GRAFANA_PW ?? log.match(/^Password:\s+(\S+)/m)?.[1];
if (!host || !password) throw new Error('Grafana URL or password not found in output.log');
const G = `http://${host}`;
const DASH = `${G}${process.env.GRAFANA_DASH ?? '/d/perf-sensor-eks/java-on-eks-e28094-sensor'}`;

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 1881, height: 1003 }, deviceScaleFactor: 1.6 });
await ctx.request.post(`${G}/login`, { data: { user: 'admin', password } });
const page = await ctx.newPage();
for (const s of JSON.parse(shotsJson)) {
  await page.goto(`${DASH}?orgId=1&from=${Date.parse(s.from)}&to=${Date.parse(s.to)}&timezone=browser&refresh=`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(6000);
  const r = await page.evaluate(() => {
    const els = [...document.querySelectorAll('.react-grid-item')]
      .map(e => e.getBoundingClientRect()).filter(b => b.height > 60);
    return {
      x: Math.min(...els.map(b => b.left)), y: Math.min(...els.map(b => b.top)),
      r: Math.max(...els.map(b => b.right)), b: Math.max(...els.map(b => b.bottom)),
    };
  });
  const m = 6;
  await page.screenshot({
    path: join(out, `${s.name}.png`),
    clip: { x: r.x - m, y: r.y - m, width: r.r - r.x + 2 * m, height: r.b - r.y + 2 * m },
  });
  console.log('saved', s.name);
}
await browser.close();
