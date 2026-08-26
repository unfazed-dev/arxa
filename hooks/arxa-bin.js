#!/usr/bin/env node
// arxa-bin.js — resolve the fastest available way to invoke the arxa CLI.
//
// Hooks fire often (PostToolUse on every matching edit, Stop on every turn
// end), so invocation cost is the difference between a gate you keep and a
// gate you disable. Measured on this repo:
//
//     dart run bin/arxa.dart --help   ~1420ms   (JIT, every invocation)
//     .build/arxa --help                ~10ms   (AOT, built by install.sh)
//
// So: prefer the AOT binary, fall back to `dart run` so a checkout that has
// never run install.sh still enforces its gates (slowly) rather than silently
// enforcing nothing.
//
// The binary deliberately lives INSIDE the repo (.build/arxa): the designer
// resolves its runtime assets by walking up from the running executable to the
// directory holding config/arxa.config.json. A binary outside the tree loses
// those assets silently.
'use strict';
const fs = require('fs');
const path = require('path');

/**
 * Build a spawn descriptor for `arxa <argv>`.
 *
 * @param {string} repoRoot absolute path to the arxa checkout
 * @param {string[]} argv   CLI args, e.g. ['docs', repoRoot]
 * @returns {{cmd:string,args:string[],cwd:string,mode:'aot'|'dart-run'}|null}
 *          null when no runnable CLI exists — callers must fail OPEN, never
 *          wedge an edit because the validator is missing.
 */
function arxaInvocation(repoRoot, argv) {
  const bin = path.join(repoRoot, '.build', 'arxa');
  try {
    fs.accessSync(bin, fs.constants.X_OK);
    return { cmd: bin, args: argv, cwd: repoRoot, mode: 'aot' };
  } catch (_) {
    // not built yet — fall through
  }
  const arxa = path.join(repoRoot, 'arxa');
  if (fs.existsSync(path.join(arxa, 'bin', 'arxa.dart'))) {
    return {
      cmd: 'dart',
      args: ['run', 'bin/arxa.dart', ...argv],
      cwd: arxa,
      mode: 'dart-run',
    };
  }
  return null;
}

/** True when a .dart source file is newer than the compiled binary. */
function isStale(repoRoot) {
  const bin = path.join(repoRoot, '.build', 'arxa');
  let binTime;
  try { binTime = fs.statSync(bin).mtimeMs; } catch (_) { return false; }
  for (const sub of ['bin', 'lib']) {
    const dir = path.join(repoRoot, 'arxa', sub);
    if (newerThan(dir, binTime)) return true;
  }
  return false;
}

function newerThan(dir, t) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return false; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { if (newerThan(full, t)) return true; continue; }
    if (!e.name.endsWith('.dart')) continue;
    try { if (fs.statSync(full).mtimeMs > t) return true; } catch (_) {}
  }
  return false;
}

module.exports = { arxaInvocation, isStale };
