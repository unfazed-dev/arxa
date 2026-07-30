// Interaction check: htmx-driven dock/undock + context chips. Run: node verify-interact.mjs
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const OUT = '/tmp/appbox-shots';
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const errors = [];
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
page.on('pageerror', (e) => errors.push(String(e)));

// Build: open the gate artifact from a thread card → chat should dock right
await page.goto('http://localhost:4319/build', { waitUntil: 'networkidle' });
await page.locator('.msg', { hasText: 'Build acceptance is yours' }).locator('a.cta-main, a:has-text("view on canvas")').first().click();
await page.waitForTimeout(700);
await page.screenshot({ path: `${OUT}/x-build-docked.png` });

// Close via collapse affordance → chat recenters
const collapse = page.locator('.chat-collapse');
if (await collapse.count()) { await collapse.first().click(); await page.waitForTimeout(700); }
await page.screenshot({ path: `${OUT}/x-build-recentered.png` });

// Design: draft-all then pin two screens to context
await page.goto('http://localhost:4319/design', { waitUntil: 'networkidle' });
const plus = page.locator('.composer-plus summary');
if (await plus.count()) await plus.first().click();
const draft = page.locator('button:has-text("draft all"), a:has-text("draft all")');
if (await draft.count()) { await draft.first().click({ force: true }); await page.waitForTimeout(900); }
const pins = page.locator('a:has-text("pin to context"), button:has-text("pin to context")');
if (await pins.count() >= 2) { await pins.nth(0).click(); await page.waitForTimeout(500); await page.locator('a:has-text("pin to context"), button:has-text("pin to context")').nth(0).click(); await page.waitForTimeout(700); }
await page.screenshot({ path: `${OUT}/x-design-board.png` });

// Intake: pick normal depth → carousel card
await page.goto('http://localhost:4319/intake', { waitUntil: 'networkidle' });
await page.locator('button:has-text("normal"), a:has-text("normal")').first().click();
await page.waitForTimeout(700);
await page.screenshot({ path: `${OUT}/x-intake-carousel.png` });

console.log('console errors:', errors.length ? errors : 'none');
await browser.close();
