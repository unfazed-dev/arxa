import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
// 1-2: build evidence single, default mobile vp, both themes
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-rs-single-${theme}.png` });
  await ctx.close();
}
// 3: build evidence single, switch to desktop vp via the toolbar chip (htmx swap)
{
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.click('.dv-group[aria-label="Viewport"] >> text=desktop');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: '/tmp/ab-rs-single-desktop.png' });
  await ctx.close();
}
// 4-5: design tab rungs, both themes
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  await page.goto(`${S}/design`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-rs-rungs-${theme}.png` });
  await ctx.close();
}
// 6: compact — floating pill strip
{
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: '/tmp/ab-rs-compact.png' });
  await ctx.close();
}
await browser.close();
console.log('done');
