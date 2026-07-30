#!/usr/bin/env node
// Fetch + pin the vendored client libraries (ADR-0002): htmx core and the
// allowlisted official extensions, each with a locally-computed SRI hash.
// Re-run to upgrade: `node vendor/fetch.mjs`. Verify: htmx core fails loudly
// if its hash diverges from the known-good pin.
import { createHash } from 'node:crypto';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

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

// Minimal untar (ustar; npm tarballs have no GNU longname entries here).
function untar(buf) {
  const files = [];
  for (let off = 0; off + 512 <= buf.length;) {
    const h = buf.subarray(off, off + 512);
    if (h.every((b) => b === 0)) break;
    const str = (a, b) => h.subarray(a, b).toString('utf8').replace(/\0.*$/, '');
    const size = parseInt(str(124, 136).trim(), 8);
    off += 512;
    if ((h[156] === 48 || h[156] === 0) && size > 0) {
      const prefix = str(345, 500);
      files.push([(prefix ? prefix + '/' : '') + str(0, 100), buf.subarray(off, off + size)]);
    }
    off += Math.ceil(size / 512) * 512;
  }
  return files;
}

// Lucide icon set (ISC): every SVG, inlined server-side by the icon()
// template global — never served to the browser as a file, so no per-file
// SRI; the manifest records the tarball hash instead.
try {
  const v = await latestVersion('lucide-static');
  const res = await fetch(`https://registry.npmjs.org/lucide-static/-/lucide-static-${v}.tgz`);
  if (!res.ok) throw new Error(`npm registry: lucide-static tarball ${res.status}`);
  const tgz = Buffer.from(await res.arrayBuffer());
  const icons = untar(gunzipSync(tgz)).filter(([n]) => /^package\/icons\/[a-z0-9-]+\.svg$/.test(n));
  if (icons.length < 1000) throw new Error(`suspiciously few icons extracted: ${icons.length}`);
  const lucideDir = path.join(vendorDir, 'lucide', 'icons');
  rmSync(lucideDir, { recursive: true, force: true });
  mkdirSync(lucideDir, { recursive: true });
  for (const [name, data] of icons) writeFileSync(path.join(lucideDir, path.basename(name)), data);
  manifest.push({ file: 'lucide/icons/*.svg', package: 'lucide-static', version: v, integrity: sri(tgz) });
  console.log(`✓ lucide/icons/*.svg ← lucide-static@${v} (${icons.length} icons)`);
} catch (err) {
  console.error(`✗ lucide-static: ${err.message}`);
  process.exit(1);
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
