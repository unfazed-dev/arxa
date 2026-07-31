#!/usr/bin/env node
// Load pages headless and fail on any console error / pageerror.
// Usage: node console-check.mjs <url> [url...]
import { chromium } from 'playwright';

const urls = process.argv.slice(2);
if (!urls.length) {
  console.error('Usage: node console-check.mjs <url> [url...]');
  process.exit(2);
}

const browser = await chromium.launch();
let failed = false;
for (const url of urls) {
  const page = await browser.newPage();
  const errors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(url, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  await page.close();
  if (errors.length) {
    failed = true;
    console.error(`✗ ${url}\n  ${errors.join('\n  ')}`);
  } else {
    console.log(`✓ ${url} — console clean`);
  }
}
await browser.close();
process.exit(failed ? 1 : 0);
