#!/usr/bin/env node
// arxa-guard.js — the ONE per-tool-call policy point, shared by every harness.
//
// Claude Code calls it as a PreToolUse hook, dsh calls it through the
// harness/dsh-external-gate plugin (tools/pre-execute), and Pi calls it from
// harness/pi/arxa-gate.ts (pi.on('tool_call')). All three speak the same
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
// "Using-sessions never write into arxa." A session applying arxa to a
// client project must not edit arxa's own source; that is what produced the
// tool/tmp_*.dart litter. Enforcement has to be per-tool-call, which is why the
// existing stage-level gates cannot express it.
//
// MODES (ARXA_GUARD_MODE, or ~/.arxa/guard-mode, default 'dev'):
//   dev    — an arxa-dev session. Everything allowed. Default, so installing
//            the guard never breaks the operator's own work.
//   using  — a using-session. Writes into the arxa checkout are DENIED except
//            under docs/, designs/, logs/ (see WRITABLE below).
//   off    — disabled entirely (matches ARXA_DOC_ENFORCE_OFF's escape hatch).
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

  // Both sides must be symlink-resolved before comparison. repoRoot comes from
  // realpathSync; a target that reaches the same directory through a symlinked
  // prefix (macOS /tmp and /var -> /private/..., or a symlinked checkout) would
  // otherwise compute a `../..` relative path, look "outside the repo", and be
  // ALLOWED. That is a fail-open in the security path, so it is fixed here
  // rather than assumed away. Regression-covered in tools/portable-core-test.sh.
  const protectedHit = targets
    .map((t) => realish(path.resolve(payload.cwd || process.cwd(), t)))
    .find((abs) => isProtected(abs, repoRoot));

  if (!protectedHit) process.exit(ALLOW);

  process.stderr.write(
    `[arxa] guard: this is a USING-session, so the arxa checkout is read-only.\n` +
    `  blocked write: ${protectedHit}\n` +
    `  arxa source may only be edited from an arxa-dev session.\n` +
    `  Writable here: docs/, designs/, logs/ — record findings there.\n` +
    `  If you need a one-off probe, use the lens eval verb instead of writing a\n` +
    `  tool/tmp_*.dart script (rust-port-closure decision 12).\n` +
    `  Override for this command: ARXA_GUARD_MODE=dev\n`
  );
  process.exit(DENY);
}

/**
 * realpath() for a path that may not exist yet (a Write creates its target).
 * Resolves symlinks on the longest existing ancestor, then re-appends the
 * not-yet-existing tail.
 */
function realish(p) {
  let cur = path.resolve(p);
  const tail = [];
  for (;;) {
    try {
      return path.join(fs.realpathSync(cur), ...tail);
    } catch (_) {
      const parent = path.dirname(cur);
      if (parent === cur) return path.resolve(p); // hit the root; nothing resolved
      tail.unshift(path.basename(cur));
      cur = parent;
    }
  }
}

/** dev | using | off */
function resolveMode() {
  const env = (process.env.ARXA_GUARD_MODE || '').trim().toLowerCase();
  if (env) return env;
  try {
    const f = path.join(require('os').homedir(), '.arxa', 'guard-mode');
    const v = fs.readFileSync(f, 'utf8').trim().toLowerCase();
    if (v) return v;
  } catch (_) {}
  return 'dev';
}

// Tool names differ per harness — Claude Code uses `Write`/`Edit`/`MultiEdit`
// and `Bash`; dsh passes its own `exec.name`; Pi uses lowercase `bash`/`edit`.
// Normalizing here is what lets one policy serve all three.
const WRITE_TOOLS = /^(write|edit|multiedit|str_replace(_editor)?|create|apply_patch|notebookedit)$/;
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
      while ((m = re.exec(cmd)) !== null) {
        if (!m[1]) continue;
        const cand = m[1].replace(/^['"]|['"]$/g, '');
        // A candidate carrying shell metacharacters was never a literal path —
        // the extraction guessed. That matters because isProtected() is an
        // ALLOWLIST: an unrecognized top segment DENIES. Under the old denylist
        // a bad guess fell through to allow; now it would become a false
        // refusal (`echo x > "$OUT"`, `mkdir "${TMPDIR}/p"`, `tee "$(date).log"`).
        // Discard the guess here so the allowlist only ever judges real paths.
        if (/[$`*?~]/.test(cand)) continue;
        out.push(cand);
      }
    }
  }
  return out;
}

// ALLOWLIST, not a denylist (ratified 2026-08-21; rust-port-closure decision 12
// amended). A using-session has exactly three legitimate write targets in this
// checkout — findings, not source. Everything else is engine.
//
// Why inverted: a denylist of source dirs left arxa-studio/, deploy/, memory/
// and every root file writable, and every future top-level dir would have been
// writable by default — it drifts open silently. An allowlist has no holes, and
// admitting a fourth target becomes a deliberate one-line decision.
//
// NOT the same list as arxa-doc-enforce.js's, and deliberately so: that one
// answers "which dirs' changes require a doc update" (a genuine denylist over
// source). Re-syncing the two would silently re-open the holes above.
const WRITABLE = ['docs', 'designs', 'logs'];

function isProtected(abs, repoRoot) {
  const rel = path.relative(repoRoot, abs);
  // `rel.startsWith('..')` alone would also match an in-repo root file named
  // `..foo` and wave it through as "outside". Segment-exact check instead.
  if (rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) {
    return false; // genuinely outside the repo
  }
  const top = rel.split(path.sep)[0];
  return !WRITABLE.includes(top); // root files (top === the filename) are engine too
}

main();
