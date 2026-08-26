#!/usr/bin/env node
// arxa-doc-health.js — PostToolUse(Write|Edit|MultiEdit) doc validator.
//
// Port of stacked_kit/hooks/doc-health.js for arxa: after an edit to an
// arxa doc (anything under docs/, or INDEX.md/VOCABULARY.md), run the
// arxa docs validator (`arxa docs`) and surface failures to the agent.
//
// Dual-harness surfacing: findings go to BOTH stdout (Kimi Code's
// PostToolUse is observation-only; exit-0 stdout may reach context) and
// stderr + exit 2 (Claude Code's only PostToolUse channel that reaches the
// model — it cannot block the edit). The Stop gate in
// arxa-doc-enforce.js is the real enforcement in both harnesses.
//
// FAILS OPEN everywhere: missing validator / payload errors exit 0 so a
// broken hook never wedges an edit. Bypass: ARXA_DOC_ENFORCE_OFF=1.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { arxaInvocation } = require('./arxa-bin.js');

if (process.env.ARXA_DOC_ENFORCE_OFF) process.exit(0);

let body = '';
try { body = fs.readFileSync(0, 'utf8'); } catch (_) { process.exit(0); }
if (!body) process.exit(0);

let payload;
try { payload = JSON.parse(body); } catch (_) { process.exit(0); }

const fp = payload && payload.tool_input && payload.tool_input.file_path;
if (!fp) process.exit(0);

// React only to arxa docs. The Kimi registration is GLOBAL (Kimi has no
// project-level hooks), so without the under-repo guard this would run the
// arxa validator on docs edits in unrelated projects.
const repoRoot = path.dirname(path.dirname(fs.realpathSync(__filename)));
const isDoc = /[\/\\]docs[\/\\].*\.(md|mdx)$/i.test(fp)
  || /[\/\\](INDEX|VOCABULARY)\.md$/i.test(fp);
if (!isDoc || !fp.startsWith(repoRoot)) process.exit(0);

// Self-locate the repo through this script's real path (hooks/ sits at the
// repo root, next to arxa/).
const arxa = path.join(repoRoot, 'arxa');
if (!fs.existsSync(path.join(arxa, 'bin', 'arxa.dart'))) {
  process.exit(0); // validator gone → fail open
}

// The one-binary build has landed (install.sh), so prefer the AOT binary
// (~10ms) over `dart run` (~1420ms) and fall back to `dart run` for a checkout
// that has never been installed.
const inv = arxaInvocation(repoRoot, ['docs', repoRoot]);
if (!inv) process.exit(0); // no runnable validator → fail open
const r = spawnSync(inv.cmd, inv.args, {
  cwd: inv.cwd,
  encoding: 'utf8',
  timeout: 60000,
});

if (typeof r.status === 'number' && r.status !== 0) {
  const msg =
    `[arxa] doc-health found issues after editing ${path.basename(fp)}:\n` +
    (r.stdout || '') + (r.stderr || '') +
    `Fix the above, then re-run: dart run bin/arxa.dart docs (from arxa/)\n`;
  process.stdout.write(msg); // Kimi observation channel
  process.stderr.write(msg); // Claude exit-2 channel
  process.exit(2);
}

process.exit(0); // clean — stay silent
