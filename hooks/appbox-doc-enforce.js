#!/usr/bin/env node
// appbox-doc-enforce.js — "always document appbox work."
//
// Port of stacked_kit/hooks/stacked_kit-doc-enforce.js for appbox. Sibling
// of appbox-doc-health.js (which VALIDATES docs after a doc edit); this hook
// notices when appbox SOURCE is edited and blocks Stop until the docs
// validator passes.
//
// Mechanism (one marker file, fail-open everywhere):
//   posttool      — appbox source edit (non-markdown under a source dir)
//                   SETS the marker. Edits outside the source set are ignored.
//   stop          — marker set → run `appbox docs`; on failure BLOCK
//                   (exit 2 + stderr — Stop is blockable in both Kimi Code
//                   and Claude Code) keeping the marker so re-Stops keep
//                   blocking; on pass, clear the marker and allow Stop.
//   sessionstart  — clear any stale marker so a fresh session starts clean.
//
// Source set (repo-relative): kit/ appboxd/ appbox-studio/lib/ pipeline/ gates/
// tools/ skills/ config/ — the pieces whose behavior the docs describe.
// archives/ and build outputs never count.
//
// Marker: <repo>/.kimi-code/.appbox_doc_pending
// Bypass: APPBOX_DOC_ENFORCE_OFF=1 (fail-open); sessionstart also clears.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { appboxInvocation } = require('./appbox-bin.js');

const MODE = process.argv[2] || 'posttool';

if (process.env.APPBOX_DOC_ENFORCE_OFF) process.exit(0);

// Self-locate the repo through this script's real path (hooks/ is at root).
const repoRoot = path.dirname(path.dirname(fs.realpathSync(__filename)));
const MARKER = path.join(repoRoot, '.kimi-code', '.appbox_doc_pending');
const appboxd = path.join(repoRoot, 'appboxd');

function setMarker() {
  try {
    fs.mkdirSync(path.dirname(MARKER), { recursive: true });
    fs.writeFileSync(MARKER, String(Date.now()));
  } catch (_) {}
}
function clearMarker() {
  try { fs.unlinkSync(MARKER); } catch (_) {}
}
function hasMarker() {
  try { return fs.existsSync(MARKER); } catch (_) { return false; }
}

// --- sessionstart: fresh budget ---------------------------------------------
if (MODE === 'sessionstart') {
  clearMarker();
  process.exit(0);
}

// --- stop: block until docs pass, if source was edited this session ---------
if (MODE === 'stop') {
  if (!hasMarker()) process.exit(0);
  if (!fs.existsSync(path.join(appboxd, 'bin', 'appbox.dart'))) {
    clearMarker();
    process.exit(0); // validator gone → fail open
  }
  // Prefer the AOT binary (~10ms) over `dart run` (~1420ms); this fires on
  // every Stop. Falls back to `dart run` when install.sh has not been run.
  const inv = appboxInvocation(repoRoot, ['docs', repoRoot]);
  if (!inv) { clearMarker(); process.exit(0); } // fail open
  const r = spawnSync(inv.cmd, inv.args, {
    cwd: inv.cwd,
    encoding: 'utf8',
    timeout: 60000,
  });
  if (typeof r.status === 'number' && r.status !== 0) {
    process.stderr.write(
      '[appbox] doc-enforce: appbox SOURCE was edited but the docs validator FAILS — ' +
      'fix the docs before finishing:\n' +
      (r.stdout || '') + (r.stderr || '') +
      'Fix: update docs/INDEX.md (and the affected doc), then re-run: ' +
      'dart run bin/appbox.dart docs  (bypass: APPBOX_DOC_ENFORCE_OFF=1)\n'
    );
    process.exit(2); // keep the marker set — block until docs pass
  }
  clearMarker(); // docs healthy (or validator died → fail open): obligation met
  process.exit(0);
}

// --- posttool: classify the edited file --------------------------------------
let body = '';
try { body = fs.readFileSync(0, 'utf8'); } catch (_) { process.exit(0); }
if (!body) process.exit(0);

let payload;
try { payload = JSON.parse(body); } catch (_) { process.exit(0); }

const fp = payload && payload.tool_input && payload.tool_input.file_path;
if (!fp) process.exit(0);

const isMarkdown = /\.(md|mdx)$/i.test(fp);
const SOURCE_DIRS = /[\/\\](kit|appboxd|pipeline|gates|tools|skills|config)[\/\\]|[\/\\]appbox-studio[\/\\]lib[\/\\]/;
const underRepo = fp.startsWith(repoRoot);

if (underRepo && !isMarkdown && SOURCE_DIRS.test(fp)) setMarker();
process.exit(0);
