import { chromium } from 'playwright';
const S = 'http://localhost:4319';
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1440, height: 950 } })).newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
// A: direct synthetic dispatch with ctrlKey
console.log('direct dispatch:', await page.evaluate(() => {
  const el = document.querySelector('.dv-stage');
  el.dispatchEvent(new WheelEvent('wheel', { ctrlKey: true, deltaY: -100, bubbles: true, cancelable: true }));
  return JSON.stringify({ z: el._z, t: el.querySelector('.dv-zoom')?.style.transform });
}));
// B: real input path, log what the page sees
await page.evaluate(() => {
  window._seen = [];
  document.querySelector('.dv-stage').addEventListener('wheel', (e) => window._seen.push({ ctrl: e.ctrlKey, dy: e.deltaY }));
});
await page.keyboard.down('Control');
const box = await page.locator('.dv-stage').boundingBox();
await page.mouse.move(box.x + box.width / 2, box.y + 200);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(120);
console.log('input path seen:', await page.evaluate(() => JSON.stringify(window._seen)));
console.log('after input:', await page.evaluate(() => JSON.stringify({ z: document.querySelector('.dv-stage')._z, t: document.querySelector('.dv-stage .dv-zoom')?.style.transform })));
await browser.close();
