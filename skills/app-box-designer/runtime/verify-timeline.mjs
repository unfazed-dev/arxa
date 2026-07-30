// Focused check: intake appbar chip + live timeline states. Run: node verify-timeline.mjs
import { chromium } from 'playwright';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('http://localhost:4319/intake', { waitUntil: 'networkidle' });
await page.screenshot({ path: '/tmp/appbox-shots/t-intake-fresh.png' });
await page.locator('button:has-text("normal"), a:has-text("normal")').first().click();
await page.waitForTimeout(700);
await page.screenshot({ path: '/tmp/appbox-shots/t-intake-depth.png' });
// dump the timeline items for a text-level truth check
const states = await page.$$eval('#bottom-bar .tl-item', (els) => els.map((e) => `${e.querySelector('.tl-label')?.textContent.trim()} [${[...e.classList].filter((c) => c.startsWith('tl-state') || c === 'is-current').join(',')}]`));
console.log(states.join('\n'));
await browser.close();
