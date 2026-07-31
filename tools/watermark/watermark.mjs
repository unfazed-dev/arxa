#!/usr/bin/env node
// tools/watermark/watermark.mjs — post-emit provenance/watermark pass.
//
// P1 (docs/plans/appbox-memory-and-payment.md): free tier = full product with
// watermarked outputs; paid = clean outputs. The provenance block is
// EVIDENCE, not a lock — stripping it is an accepted design constant handled
// by licence terms, not crypto (Unity Personal splash precedent,
// docs/research/monetization-and-licensing.md). Emitted source is never
// encrypted.
//
// Licence status: `dart run bin/licence_tool.dart status` inside appboxd,
// contract = JSON stdout {"status":"paid"|"free"|"none", tier, expires}.
// Any failure (tool missing, dart missing, bad JSON) => treated as "free".
// Status is cached per process.
//
// Env overrides (documented test hooks):
//   APPBOX_LICENCE_STATUS — JSON string or a plain status word ("paid"/"free");
//                           bypasses the dart call entirely.
//   APPBOXD_DIR           — where appboxd lives (default: <repo>/appboxd).
//
// CLI: node tools/watermark/watermark.mjs <rootDir>
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export const MARKER = 'appbox:provenance';
export const WATERMARK_LINE = 'Built with appbox (free tier) — https://appbox.dev';
export const MANIFEST_NAME = '.appbox-provenance.json';

// Comment syntax per extension. .json is deliberately absent: no comment
// syntax — its provenance is a sibling note in the manifest instead.
const COMMENT = {
  '.dart': '//', '.js': '//', '.mjs': '//', '.ts': '//',
  '.yaml': '#', '.yml': '#', '.sh': '#',
  '.html': 'html',
};

let _licence = null;
export function licenceStatus() {
  if (_licence) return _licence;
  const env = process.env.APPBOX_LICENCE_STATUS;
  if (env) {
    _licence = env.trim().startsWith('{')
      ? JSON.parse(env)
      : { status: env.trim() };
    return _licence;
  }
  try {
    const appboxd = process.env.APPBOXD_DIR || path.join(ROOT, 'appboxd');
    const out = execFileSync('dart', ['run', 'bin/licence_tool.dart', 'status'], {
      cwd: appboxd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
    _licence = JSON.parse(out);
  } catch {
    _licence = { status: 'free' }; // tool missing/broken => free, never blocks emission
  }
  return _licence;
}

// Contract: {status: "paid"|"free"|"none", ...}. Only "paid" is clean;
// "none" (no licence file) watermarks like "free".
function resolveTier(lic) {
  return (lic && lic.status) === 'paid' ? 'paid' : 'free';
}

function renderBlock(ext, { tier, projectHash }) {
  const lines = [
    MARKER,
    `generator: appbox  licence: ${tier}  project: ${projectHash}`,
    // evidence of origin, not a lock — see file header comment
  ];
  if (tier === 'free') lines.push(WATERMARK_LINE);
  if (ext === '.html') {
    return `<!-- ${lines[0]}\n${lines.slice(1).map((l) => `     ${l}`).join('\n')}\n-->\n`;
  }
  const c = COMMENT[ext];
  return lines.map((l) => `${c} ${l}`).join('\n') + '\n';
}

// Prepends a provenance header; free tier carries the watermark line inside
// the block. Idempotent via the MARKER token. Returns one of:
// 'injected' | 'already' | 'json-skip' | 'unsupported'.
export function injectProvenance(filePath, { tier, projectHash }) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.json') return 'json-skip';
  if (!(ext in COMMENT)) return 'unsupported';
  const src = readFileSync(filePath, 'utf8');
  if (src.includes(MARKER)) return 'already';
  const block = renderBlock(ext, { tier, projectHash });
  let out;
  if (src.startsWith('#!')) {
    // shebang must stay line 1
    const nl = src.indexOf('\n');
    out = src.slice(0, nl + 1) + block + src.slice(nl + 1);
  } else if (ext === '.html' && /^\s*<!doctype[^>]*>/i.test(src)) {
    // a comment before <!DOCTYPE> triggers quirks mode — inject after it
    out = src.replace(/^\s*<!doctype[^>]*>\s*/i, (m) => m + block);
  } else {
    out = block + src;
  }
  writeFileSync(filePath, out);
  return 'injected';
}

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

// Walk rootDir, inject provenance into every supported file, and write
// .appbox-provenance.json {files: [{path, sha256, note?}], tier, ts}.
export function runPass(rootDir, opts = {}) {
  const tier = opts.tier || resolveTier(licenceStatus());
  const projectHash = opts.projectHash ||
    sha256(path.resolve(rootDir)).slice(0, 12);
  const files = [];

  (function walk(dir) {
    for (const name of readdirSync(dir).sort()) {
      if (name === 'node_modules' || name === '.git' || name === MANIFEST_NAME) continue;
      const p = path.join(dir, name);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      const ext = path.extname(name).toLowerCase();
      if (!(ext in COMMENT) && ext !== '.json') continue;
      const result = injectProvenance(p, { tier, projectHash });
      const entry = { path: path.relative(rootDir, p), sha256: sha256(readFileSync(p)) };
      if (result === 'json-skip') entry.note = 'json: no comment syntax — provenance is this manifest entry';
      files.push(entry);
    }
  })(rootDir);

  const manifest = { tier, ts: new Date().toISOString(), files };
  writeFileSync(path.join(rootDir, MANIFEST_NAME), JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const root = process.argv[2];
  if (!root) {
    console.error('usage: watermark.mjs <rootDir>');
    process.exit(64);
  }
  const m = runPass(root);
  console.log(`provenance pass: tier=${m.tier} files=${m.files.length} -> ${path.join(root, MANIFEST_NAME)}`);
}
