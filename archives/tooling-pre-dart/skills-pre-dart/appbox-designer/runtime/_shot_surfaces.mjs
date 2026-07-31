import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const routes = ['/intake', '/intake/brief', '/intake/moodboard', '/design', '/design/chat?screen=build.loop', '/design/freeze'];
const name = (r) => r.replace(/[/?=&.]/g, '_');
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  for (const r of routes) {
    await page.goto(S + r, { waitUntil: 'networkidle' });
    await page.screenshot({ path: `/tmp/ab-s${name(r)}-${theme}.png`, fullPage: true });
  }
  await ctx.close();
}
// compact rung spot-checks
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
for (const r of ['/intake', '/design']) {
  await page.goto(S + r, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-s${name(r)}-compact.png`, fullPage: true });
}
await browser.close();
console.log('done');
