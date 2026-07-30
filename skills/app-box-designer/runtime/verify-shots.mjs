// Throwaway visual-verification script — screenshots the redesigned surfaces
// at the three ladder rungs. Run: node verify-shots.mjs
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const OUT = '/tmp/appbox-shots';
mkdirSync(OUT, { recursive: true });

const rungs = [
  { name: 'compact', width: 390, height: 844 },
  { name: 'medium', width: 744, height: 1000 },
  { name: 'expanded', width: 1280, height: 900 },
];
const pages = [
  { name: 'intake', url: '/intake' },
  { name: 'design', url: '/design' },
  { name: 'build', url: '/build' },
  { name: 'build-gate', url: '/build/artifact/gate/build-acceptance' },
  { name: 'dashboard', url: '/dashboard' },
  { name: 'auth', url: '/auth' },
];

const browser = await chromium.launch();
for (const r of rungs) {
  const page = await browser.newPage({ viewport: { width: r.width, height: r.height } });
  const errors = [];
  page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
  page.on('pageerror', (e) => errors.push(String(e)));
  for (const p of pages) {
    await page.goto(`http://localhost:4319${p.url}`, { waitUntil: 'networkidle' });
    await page.screenshot({ path: `${OUT}/${p.name}-${r.name}.png` });
  }
  if (errors.length) console.log(`[${r.name}] console errors:`, errors.slice(0, 5));
  await page.close();
}
await browser.close();
console.log('done');
