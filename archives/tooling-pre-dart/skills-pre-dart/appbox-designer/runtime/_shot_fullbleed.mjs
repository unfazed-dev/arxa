import { chromium } from 'playwright';

const S = 'http://localhost:4319';
const prefs = (theme) => encodeURIComponent(JSON.stringify({ theme }));

const browser = await chromium.launch();
for (const theme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
  await ctx.addCookies([{ name: 'kdh_prefs', value: prefs(theme), url: S }]);
  const page = await ctx.newPage();
  await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-fb-evidence-${theme}.png`, fullPage: true });
  await page.goto(`${S}/build/artifact/evidence/surfaces/viewer?screen=order.cart&vp=mobile&bg=canvas&os=android`);
  await page.screenshot({ path: `/tmp/ab-fb-android-${theme}.png` });
  await page.goto(`${S}/build/artifact/evidence/surfaces/viewer?screen=catalog.home&vp=desktop&bg=warm&os=ios`);
  await page.screenshot({ path: `/tmp/ab-fb-desktop-${theme}.png` });
  await page.goto(`${S}/build`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `/tmp/ab-fb-gate-${theme}.png` });
  await ctx.close();
}
await browser.close();
console.log('done');
