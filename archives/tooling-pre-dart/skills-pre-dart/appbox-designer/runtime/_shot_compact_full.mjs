import { chromium } from 'playwright';
const S = 'http://localhost:4319';
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
const page = await ctx.newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
await page.screenshot({ path: '/tmp/ab-rs-compact-full.png', fullPage: true });
await browser.close();
console.log('done');
