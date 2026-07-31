import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const OUT = '/tmp/ab-viewer';
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `${OUT}-${theme}-viewer.png`, fullPage: true });
  // FAB chooser
  await page.click('.fab');
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${OUT}-${theme}-chooser.png`, fullPage: true });
  await ctx.close();
}
await browser.close();
console.log('done');
