#!/usr/bin/env node
// Fetch + pin the vendored client libraries (ADR-0002): htmx core and the
// allowlisted official extensions, each with a locally-computed SRI hash.
// Re-run to upgrade: `node vendor/fetch.mjs`. Verify: htmx core fails loudly
// if its hash diverges from the known-good pin.
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const vendorDir = path.dirname(fileURLToPath(import.meta.url));
const HTMX_PIN = '2.0.10';
const HTMX_INTEGRITY =
  'sha384-H5SrcfygHmAuTDZphMHqBJLc3FhssKjG7w/CeCpFReSfwBWDTKpkzPP8c+cLsK+V';

const packages = [
  {
    pkg: 'htmx.org',
    version: HTMX_PIN,
    candidates: ['dist/htmx.min.js'],
    out: 'htmx.min.js',
    expect: HTMX_INTEGRITY,
  },
  { pkg: 'htmx-ext-preload', candidates: ['dist/preload.min.js', 'dist/preload.js'], out: 'preload.min.js' },
  { pkg: 'htmx-ext-head-support', candidates: ['dist/head-support.min.js', 'dist/head-support.js'], out: 'head-support.js' },
  { pkg: 'htmx-ext-sse', candidates: ['dist/sse.min.js', 'dist/sse.js'], out: 'sse.js' },
  { pkg: 'htmx-ext-client-side-templates', candidates: ['dist/client-side-templates.min.js', 'dist/client-side-templates.js'], out: 'client-side-templates.js' },
  { pkg: 'mustache', candidates: ['mustache.min.js', 'mustache.js'], out: 'mustache.min.js' },
  { pkg: 'htmx-ext-morph', candidates: ['dist/morph.min.js', 'dist/morph.js'], out: 'morph.js', optional: true },
];

const sri = (buf) => 'sha384-' + createHash('sha384').update(buf).digest('base64');

async function latestVersion(pkg) {
  const res = await fetch(`https://registry.npmjs.org/${pkg}/latest`);
  if (!res.ok) throw new Error(`npm registry: ${pkg} ${res.status}`);
  return (await res.json()).version;
}

const manifest = [];
mkdirSync(vendorDir, { recursive: true });

for (const { pkg, version, candidates, out, expect, optional } of packages) {
  try {
    const v = version ?? (await latestVersion(pkg));
    let buf = null;
    for (const candidate of candidates) {
      const res = await fetch(`https://cdn.jsdelivr.net/npm/${pkg}@${v}/${candidate}`);
      if (res.ok) {
        buf = Buffer.from(await res.arrayBuffer());
        break;
      }
    }
    if (!buf) throw new Error(`no candidate file found: ${candidates.join(', ')}`);
    const integrity = sri(buf);
    if (expect && integrity !== expect) {
      throw new Error(`integrity mismatch! got ${integrity}, expected ${expect}`);
    }
    writeFileSync(path.join(vendorDir, out), buf);
    manifest.push({ file: out, package: pkg, version: v, integrity });
    console.log(`✓ ${out} ← ${pkg}@${v} (${buf.length} bytes)`);
  } catch (err) {
    if (optional) {
      console.warn(`– ${pkg}: skipped (${err.message})`);
    } else {
      console.error(`✗ ${pkg}: ${err.message}`);
      process.exit(1);
    }
  }
}

writeFileSync(path.join(vendorDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
writeFileSync(
  path.join(vendorDir, 'SRI.md'),
  '# Vendored client libraries (re-run `node vendor/fetch.mjs` to update)\n\n' +
    '| file | package | version | integrity |\n|---|---|---|---|\n' +
    manifest.map((m) => `| ${m.file} | ${m.package} | ${m.version} | \`${m.integrity}\` |`).join('\n') +
    '\n',
);
console.log(`\n${manifest.length} libraries vendored → ${vendorDir}`);
