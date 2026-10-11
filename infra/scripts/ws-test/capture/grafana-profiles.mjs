// grafana-profiles.mjs REPORT_DIR SHOTS_JSON [OUT_DIR] — Grafana Drilldown → Profiles flame
// graphs of one pod over a window, with a search term highlighted, for the content's profile
// sections. Login as in grafana-panels.mjs (the run's "Open Grafana" block, or GRAFANA_HOST and
// GRAFANA_PW).
//
// SHOTS_JSON: [{"name": "baseline-profile", "service": "unicorn-store-spring",
//               "pod": "<pod name>", "from": "<ISO UTC>", "to": "<ISO UTC>", "search": "CompileBroker"}]
// The shot is the exploration below the breadcrumb: filters, the CPU timeline and the flame
// graph with the search applied.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { chromium } from 'playwright-core';

const [report, shotsJson, out = '.'] = process.argv.slice(2);
if (!report || !shotsJson) {
  console.error('usage: node grafana-profiles.mjs REPORT_DIR SHOTS_JSON [OUT_DIR]');
  process.exit(2);
}
const log = readFileSync(join(report, 'output.log'), 'utf8');
const host = process.env.GRAFANA_HOST ?? log.match(/^URL:\s+http:\/\/(\S+)/m)?.[1];
const password = process.env.GRAFANA_PW ?? log.match(/^Password:\s+(\S+)/m)?.[1];
if (!host || !password) throw new Error('Grafana URL or password not found in output.log');
const G = `http://${host}`;
const CPU = 'process_cpu:cpu:nanoseconds:cpu:nanoseconds';

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await browser.newContext({ viewport: { width: 1881, height: 1003 }, deviceScaleFactor: 1.6 });
await ctx.request.post(`${G}/login`, { data: { user: 'admin', password } });
const page = await ctx.newPage();
for (const s of JSON.parse(shotsJson)) {
  const q = new URLSearchParams({
    explorationType: 'flame-graph', 'var-dataSource': 'pyroscope',
    'var-serviceName': s.service ?? 'unicorn-store-spring', 'var-profileMetricId': CPU,
    'var-filters': `pod|=|${s.pod}`, from: String(Date.parse(s.from)), to: String(Date.parse(s.to)),
  });
  await page.goto(`${G}/a/grafana-pyroscope-app/explore?${q}`);
  await page.waitForTimeout(12000);   // the app streams; networkidle never comes
  if (s.search) {
    const box = page.locator('input[placeholder="Search..."]').last();
    await box.fill(s.search);
    await page.waitForTimeout(3000);
  }
  await page.mouse.move(5, 995);
  const main = await page.evaluate(() => {
    const nav = document.querySelector('[data-testid="data-testid navigation mega-menu"], nav');
    const left = nav ? Math.ceil(nav.getBoundingClientRect().right) : 0;
    return { left, top: 40 };
  });
  await page.screenshot({
    path: join(out, `${s.name}.png`),
    clip: { x: main.left, y: main.top, width: 1881 - main.left, height: 1003 - main.top },
  });
  console.log('saved', s.name);
}
await browser.close();
