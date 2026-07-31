import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const routes = ['/intake', '/intake/moodboard', '/design', '/design/chat?screen=build.loop', '/build?artifact=evidence/surfaces'];
const name = (r) => r.replace(/[/?=&.]/g, '_');
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  for (const r of routes) {
    await page.goto(S + r, { waitUntil: 'networkidle' });
    await page.screenshot({ path: `/tmp/ab-rf${name(r)}-${theme}.png`, fullPage: true });
  }
  await ctx.close();
}
await browser.close();
console.log('done');
