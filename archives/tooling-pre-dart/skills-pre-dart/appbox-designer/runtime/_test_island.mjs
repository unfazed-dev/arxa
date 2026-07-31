import { chromium } from 'playwright';
const S = 'http://localhost:4319';
const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1440, height: 950 } })).newPage();
await page.goto(`${S}/build?artifact=evidence/surfaces`, { waitUntil: 'networkidle' });

// 1. island armed on the stage
const armed = await page.evaluate(() => !!document.querySelector('.dv-stage')?._cz);
console.log('armed:', armed);

// 2. drag pan on free canvas (right of the centered 390 device)
const st = () => page.evaluate(() => document.querySelector('.dv-stage').scrollTop);
const box = await page.locator('.dv-stage').boundingBox();
const sx = box.x + box.width - 20, sy = box.y + box.height / 2;
const before = await st();
await page.mouse.move(sx, sy); await page.mouse.down();
await page.mouse.move(sx, sy - 120, { steps: 5 }); await page.mouse.up();
console.log('drag pan scrollTop:', before, '->', await st());

// 3. pinch zoom (ctrl+wheel) around cursor
await page.keyboard.down('Control');
await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(150);
console.log('zoom:', await page.evaluate(() => JSON.stringify({
  z: document.querySelector('.dv-stage')._z,
  t: document.querySelector('.dv-stage .dv-zoom').style.transform,
  deviceW: document.querySelector('.dv-stage .device').style.width,
})));
await page.screenshot({ path: '/tmp/ab-island-single-zoomed.png' });

// 4. dblclick resets
await page.mouse.dblclick(sx, box.y + 60);
await page.waitForTimeout(100);
console.log('reset:', await page.evaluate(() => JSON.stringify({
  z: document.querySelector('.dv-stage')._z,
  t: document.querySelector('.dv-stage .dv-zoom').style.transform,
})));

// 5. htmx swap → new stage element re-armed
await page.click('.dv-group[aria-label="Viewport"] >> text=tablet');
await page.waitForTimeout(900);
console.log('rearmed after swap:', await page.evaluate(() => !!document.querySelector('.dv-stage')?._cz));

// 6. rungs mode zoom
await page.goto(`${S}/design`, { waitUntil: 'networkidle' });
const rbox = await page.locator('.dv-rungs').boundingBox();
await page.keyboard.down('Control');
await page.mouse.move(rbox.x + 300, rbox.y + 200);
await page.mouse.wheel(0, -240);
await page.keyboard.up('Control');
await page.waitForTimeout(150);
console.log('rungs zoom:', await page.evaluate(() => JSON.stringify({
  z: document.querySelector('.dv-rungs')._z,
  t: document.querySelector('.dv-rungs .dv-zoom').style.transform,
})));
await page.screenshot({ path: '/tmp/ab-island-rungs-zoomed.png' });

await browser.close();
console.log('done');
