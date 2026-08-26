#!/usr/bin/env node
// install-kimi.js — register the arxa doc hooks with Kimi Code.
//
// Kimi Code reads hooks only from the GLOBAL config.toml ($KIMI_CODE_HOME or
// ~/.kimi-code) — there is no project-level hook registration (docs:
// kimi.com/code/docs/en/kimi-code-cli/customization/hooks.html). So
// "self-contained" means: the hook scripts live in this repo, and this
// installer idempotently appends the registration pointing at them.
//
// Usage: node hooks/install-kimi.js        (safe to re-run; no-op if present)
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

const repoRoot = path.dirname(path.dirname(fs.realpathSync(__filename)));
const home = process.env.KIMI_CODE_HOME || path.join(os.homedir(), '.kimi-code');
const configPath = path.join(home, 'config.toml');

const TAG = '# arxa doc hooks (hooks/install-kimi.js — do not edit between markers)';
const block = `
${TAG}
[[hooks]]
event = "PostToolUse"
matcher = "Write|Edit|MultiEdit"
command = "node \\"${path.join(repoRoot, 'hooks', 'arxa-doc-health.js')}\\""
timeout = 30

[[hooks]]
event = "Stop"
command = "node \\"${path.join(repoRoot, 'hooks', 'arxa-doc-enforce.js')}\\" stop"
timeout = 60

[[hooks]]
event = "SessionStart"
command = "node \\"${path.join(repoRoot, 'hooks', 'arxa-doc-enforce.js')}\\" sessionstart"
timeout = 5
${TAG.replace('do not edit between markers', 'end arxa doc hooks')}
`;

let existing = '';
try { existing = fs.readFileSync(configPath, 'utf8'); } catch (_) {}
if (existing.includes(TAG)) {
  console.log('arxa doc hooks already registered in ' + configPath + ' — nothing to do.');
  process.exit(0);
}
fs.mkdirSync(home, { recursive: true });
fs.appendFileSync(configPath, block);
console.log('Registered arxa doc hooks in ' + configPath + ' (takes effect on next session).');
