import { chromium } from 'playwright';
const S = 'http://localhost:4319';
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1440, height: 950 } })).newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });
const state = () => page.evaluate(() => JSON.stringify({ z: document.querySelector('.dv-stage')._z, t: document.querySelector('.dv-stage .dv-zoom')?.style.transform }));
const box = await page.locator('.dv-stage').boundingBox();

// A: pinch zoom over FREE canvas
await page.keyboard.down('Control');
await page.mouse.move(box.x + box.width - 30, box.y + box.height / 2);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(150);
console.log('zoom free space:', await state());

// B: pinch zoom OVER THE DEVICE iframe
const fbox = await page.locator('.dv-stage iframe').boundingBox();
await page.keyboard.down('Control');
await page.mouse.move(fbox.x + fbox.width / 2, fbox.y + 300);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(150);
console.log('zoom over device:', await state());
await page.screenshot({ path: '/tmp/ab-island-single-zoomed.png' });

// C: plain wheel (no ctrl) still natively pans the iframe/stage, no zoom
const z0 = await state();
await page.mouse.move(fbox.x + fbox.width / 2, fbox.y + 300);
await page.mouse.wheel(0, 300);
await page.waitForTimeout(150);
console.log('plain wheel keeps zoom:', z0, '==', await state());

// D: dblclick reset
await page.mouse.dblclick(box.x + box.width - 30, box.y + 60);
await page.waitForTimeout(100);
console.log('reset:', await state());

// E: rungs zoom over the desktop rung iframe
await page.goto(`${S}/design`, { waitUntil: 'networkidle' });
const rstate = () => page.evaluate(() => JSON.stringify({ z: document.querySelector('.dv-rungs')._z, t: document.querySelector('.dv-rungs .dv-zoom')?.style.transform }));
const rf = await page.locator('.dv-rungs iframe').first().boundingBox();
await page.keyboard.down('Control');
await page.mouse.move(rf.x + rf.width / 2, rf.y + 200);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(150);
console.log('rungs zoom over device:', await rstate());
await page.screenshot({ path: '/tmp/ab-island-rungs-zoomed.png' });
await browser.close();
console.log('done');
