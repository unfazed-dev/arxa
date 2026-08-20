#!/usr/bin/env node
// appbox-guard.js — the ONE per-tool-call policy point, shared by every harness.
//
// Claude Code calls it as a PreToolUse hook, dsh calls it through the
// harness/dsh-external-gate plugin (tools/pre-execute), and Pi calls it from
// harness/pi/appbox-gate.ts (pi.on('tool_call')). All three speak the same
// protocol, so the policy lives in exactly one file and cannot drift between
// surfaces. That single-policy-many-harnesses property is what "portable core"
// means.
//
// PROTOCOL (Claude Code's hook contract, adopted verbatim so scripts port):
//   stdin  <- one JSON object: { tool_name, tool_input, cwd, session_id }
//   exit 0 -> allow
//   exit 2 -> DENY; this process's stderr becomes the model-visible reason
//   other  -> the caller decides; the dsh adapter fails CLOSED on unknown codes
//
// THE POLICY (rust-port-closure-and-surgical-lens.md decision 12, ratified):
// "Using-sessions never write into appbox." A session applying appbox to a
// client project must not edit appbox's own source; that is what produced the
// tool/tmp_*.dart litter. Enforcement has to be per-tool-call, which is why the
// existing stage-level gates cannot express it.
//
// MODES (APPBOX_GUARD_MODE, or ~/.appbox/guard-mode, default 'dev'):
//   dev    — an appbox-dev session. Everything allowed. Default, so installing
//            the guard never breaks the operator's own work.
//   using  — a using-session. Writes into the appbox checkout are DENIED.
//   off    — disabled entirely (matches APPBOX_DOC_ENFORCE_OFF's escape hatch).
//
// FAILS OPEN on malformed input: a broken guard must never wedge a session.
'use strict';
const fs = require('fs');
const path = require('path');

const ALLOW = 0, DENY = 2;

function main() {
  const mode = resolveMode();
  if (mode === 'off' || mode === 'dev') process.exit(ALLOW);

  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch (_) {
    process.exit(ALLOW); // unparseable → fail open
  }

  const repoRoot = path.dirname(path.dirname(fs.realpathSync(__filename)));
  const targets = writeTargets(payload);
  if (targets.length === 0) process.exit(ALLOW);

  const protectedHit = targets
    .map((t) => path.resolve(payload.cwd || process.cwd(), t))
    .find((abs) => isProtected(abs, repoRoot));

  if (!protectedHit) process.exit(ALLOW);

  process.stderr.write(
    `[appbox] guard: this is a USING-session, so the appbox checkout is read-only.\n` +
    `  blocked write: ${protectedHit}\n` +
    `  appbox source may only be edited from an appbox-dev session.\n` +
    `  If you need a one-off probe, use the lens eval verb instead of writing a\n` +
    `  tool/tmp_*.dart script (rust-port-closure decision 12).\n` +
    `  Override for this command: APPBOX_GUARD_MODE=dev\n`
  );
  process.exit(DENY);
}

/** dev | using | off */
function resolveMode() {
  const env = (process.env.APPBOX_GUARD_MODE || '').trim().toLowerCase();
  if (env) return env;
  try {
    const f = path.join(require('os').homedir(), '.appbox', 'guard-mode');
    const v = fs.readFileSync(f, 'utf8').trim().toLowerCase();
    if (v) return v;
  } catch (_) {}
  return 'dev';
}

// Tool names differ per harness — Claude Code uses `Write`/`Edit`/`MultiEdit`
// and `Bash`; dsh passes its own `exec.name`; Pi uses lowercase `bash`/`edit`.
// Normalizing here is what lets one policy serve all three.
const WRITE_TOOLS = /^(write|edit|multiedit|str_replace|create|apply_patch|notebookedit)$/;
const SHELL_TOOLS = /^(bash|shell|exec|run|terminal|command)$/;

/** Paths this tool call would write to. Empty ⇒ nothing to police. */
function writeTargets(p) {
  const name = String(p.tool_name || '').toLowerCase();
  const input = p.tool_input || {};
  const out = [];

  if (WRITE_TOOLS.test(name)) {
    for (const k of ['file_path', 'path', 'file', 'filePath', 'notebook_path']) {
      if (typeof input[k] === 'string' && input[k]) out.push(input[k]);
    }
    if (Array.isArray(input.edits)) {
      for (const e of input.edits) {
        if (e && typeof e.file_path === 'string') out.push(e.file_path);
      }
    }
    return out;
  }

  if (SHELL_TOOLS.test(name)) {
    const cmd = String(input.command || input.cmd || input.script || '');
    if (!cmd) return out;
    // Deliberately conservative: only flag shell forms that plainly write to a
    // path. A shell command is not statically analyzable, so this catches the
    // common cases and lets the rest through rather than blocking real work on
    // a guess. The Stop-level doc gate remains the backstop.
    const patterns = [
      />>?\s*([^\s;|&]+)/g,                       // > file, >> file
      /\b(?:rm|mv|cp|touch|mkdir|chmod|chown)\s+(?:-\S+\s+)*([^\s;|&]+)/g,
      /\b(?:tee|dd\s+of=)\s*([^\s;|&]+)/g,
      /\bsed\s+-i\S*\s+(?:-e\s+\S+\s+)*(?:'[^']*'|"[^"]*"|\S+)\s+([^\s;|&]+)/g,
    ];
    for (const re of patterns) {
      let m;
      while ((m = re.exec(cmd)) !== null) if (m[1]) out.push(m[1].replace(/^['"]|['"]$/g, ''));
    }
  }
  return out;
}

// The source set mirrors appbox-doc-enforce.js: the dirs whose behavior the
// docs describe. Everything else in the checkout (docs/, designs/, logs/) stays
// writable so a using-session can still record findings.
const PROTECTED = ['appboxd', 'kit', 'pipeline', 'gates', 'tools', 'skills', 'config', 'hooks', 'harness'];

function isProtected(abs, repoRoot) {
  const rel = path.relative(repoRoot, abs);
  if (rel.startsWith('..') || path.isAbsolute(rel)) return false; // outside the repo
  const top = rel.split(path.sep)[0];
  return PROTECTED.includes(top);
}

main();
