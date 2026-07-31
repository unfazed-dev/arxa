import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
await ctx.addCookies([{ name: 'kdh_prefs', value: encodeURIComponent(JSON.stringify({ theme: 'dark' })), url: S }]);
const page = await ctx.newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
await page.click('.dv-group[aria-label="Device chrome"] a:text("android")');
await page.waitForTimeout(500);
await page.screenshot({ path: '/tmp/ab-fb-android2-dark.png' });
await page.click('.dv-group[aria-label="Viewport"] a:text("desktop")');
await page.waitForTimeout(600);
await page.screenshot({ path: '/tmp/ab-fb-desktop2-dark.png' });
await browser.close();
console.log('done');
