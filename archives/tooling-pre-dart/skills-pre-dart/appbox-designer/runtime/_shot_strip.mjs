import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-strip-${theme}.png`, fullPage: true });
  await ctx.close();
}
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
await page.screenshot({ path: '/tmp/ab-strip-compact.png' });
await browser.close();
console.log('done');
