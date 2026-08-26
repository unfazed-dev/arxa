/**
 * Integration test for dsh-external-gate against the REAL cordis kernel that
 * ships with the installed dsh — not a hand-rolled mock of it.
 *
 * What this proves: our plugin registers on `tools/pre-execute`, that cordis
 * actually dispatches the event to it, that the waterfall's return value is a
 * well-formed PreToolDecision, and that a real subprocess verdict (the shared
 * hooks/arxa-guard.js) turns into deny/allow correctly.
 *
 * What it does NOT prove: that a live `dsh` session routes tool calls through
 * this seam end-to-end. That needs a booted agent and model credits. See
 * harness/README.md for the manual live-check procedure.
 *
 *   node harness/dsh-external-gate/test.mjs
 */
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as plugin from './index.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const REPO = join(here, '..', '..');
const GUARD = join(REPO, 'hooks', 'arxa-guard.js');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m, d) => { fail++; console.log(`  FAIL ${m}${d ? `\n       ${d}` : ''}`); };

// ── locate the real cordis from the installed dsh ────────────────────────────
// NOTE: dsh vendors cordis under the SCOPED name `@deepseek-ai/cordis`; a
// lookup for bare `cordis` finds nothing and silently downgrades this whole
// file to the weaker fallback.
async function loadCordis() {
  const dir = spawnSync('sh', ['-c',
    'ls -d ~/.npm/_npx/*/node_modules/@deepseek-ai/cordis 2>/dev/null | head -1'],
    { encoding: 'utf8' }).stdout.trim();
  if (!dir) return null;
  try {
    return await import(join(dir, 'lib', 'index.mjs'))
      .catch(() => createRequire(import.meta.url)(dir));
  } catch (_) { return null; }
}

// ── a verdict script that shells to the shared guard ─────────────────────────
const VERDICT = join(here, '.verdict-test.sh');
import { writeFileSync, chmodSync, unlinkSync } from 'node:fs';
writeFileSync(VERDICT, `#!/bin/sh\nexec node "${GUARD}"\n`);
chmodSync(VERDICT, 0o755);

async function run() {
  const cordis = await loadCordis();
  if (!cordis || !cordis.Context) {
    console.log('  SKIP cordis not resolvable — falling back to direct-handler test');
    return directHandlerTests();
  }

  console.log('== dsh-external-gate x REAL cordis ==');
  const ctx = new cordis.Context();

  // Mount exactly as a profile patch row would. Cordis plugin loading is
  // fiber-based and ASYNC: without awaiting it, the listener is not registered
  // when the first waterfall fires, every call falls through to the default
  // `allow`, and the allow-shaped assertions below pass while proving nothing.
  await ctx.plugin(plugin, {
    command: VERDICT,
    tools: ['Write', 'Bash'],
    timeoutMs: 5000,
  });
  ok('plugin mounts on a real cordis Context without throwing');

  // PROOF OF LIFE — the only assertion that distinguishes "our plugin ran" from
  // "no plugin at all": a deny can ONLY come from us. Every allow-shaped result
  // is indistinguishable from an unmounted gate, so it is checked after this.
  process.env.ARXA_GUARD_MODE = 'using';
  const alive = await ctx.waterfall('tools/pre-execute',
    { name: 'Write', arguments: { file_path: join(REPO, 'arxa', 'lib', 'probe.dart') }, callId: 'p' },
    async () => ({ kind: 'allow' }));
  alive.kind === 'deny'
    ? ok('gate is genuinely intercepting (deny observed — cannot come from a no-op)')
    : bad('gate is genuinely intercepting', `got ${JSON.stringify(alive)} — plugin likely NOT registered`);

  // Fire the REAL cordis waterfall via its public dispatch API. `waterfall` is
  // a proxied method (Context is a Proxy, so it is invisible to property
  // introspection) — reaching into `_hooks` instead finds nothing and reports a
  // false NO_LISTENER.
  const call = async (name, args, mode) => {
    process.env.ARXA_GUARD_MODE = mode;
    const exec = { name, arguments: args, callId: 'c1', agent: undefined };
    return await ctx.waterfall('tools/pre-execute', exec,
      async () => ({ kind: 'allow' }));
  };

  const denied = await call('Write',
    { file_path: join(REPO, 'arxa', 'lib', 'x.dart') }, 'using');
  denied.kind === 'deny'
    ? ok(`protected write DENIED via real waterfall (${String(denied.reason).slice(0, 40)}...)`)
    : bad('protected write denied', `got ${JSON.stringify(denied)}`);

  const allowed = await call('Write', { file_path: join(REPO, 'docs', 'n.md') }, 'using');
  allowed.kind === 'allow'
    ? ok('docs write ALLOWED via real waterfall')
    : bad('docs write allowed', `got ${JSON.stringify(allowed)}`);

  const devMode = await call('Write',
    { file_path: join(REPO, 'arxa', 'lib', 'x.dart') }, 'dev');
  devMode.kind === 'allow'
    ? ok('dev mode ALLOWS the same write (mode is honored)')
    : bad('dev mode allows', `got ${JSON.stringify(devMode)}`);

  const untracked = await call('Read', { file_path: '/etc/hosts' }, 'using');
  untracked.kind === 'allow'
    ? ok('non-matching tool bypasses the gate entirely')
    : bad('tool filter', `got ${JSON.stringify(untracked)}`);
}

// Fallback when cordis cannot be resolved: exercise apply() with a minimal ctx
// that records the handler, then call it. Weaker, but never silently skips.
async function directHandlerTests() {
  console.log('== dsh-external-gate (direct handler) ==');
  let handler = null;
  const ctx = { on: (ev, fn) => { if (ev === 'tools/pre-execute') handler = fn; } };
  plugin.apply(ctx, { command: VERDICT, tools: ['Write'], timeoutMs: 5000 });
  handler ? ok('apply() registers a tools/pre-execute handler') : bad('handler registered');
  if (!handler) return;

  process.env.ARXA_GUARD_MODE = 'using';
  const d = await handler({ name: 'Write', arguments: { file_path: join(REPO, 'arxa', 'a.dart') }, callId: 'x' },
    async () => ({ kind: 'allow' }));
  d.kind === 'deny' ? ok('protected write DENIED') : bad('protected write denied', JSON.stringify(d));

  const a = await handler({ name: 'Write', arguments: { file_path: join(REPO, 'docs', 'a.md') }, callId: 'x' },
    async () => ({ kind: 'allow' }));
  a.kind === 'allow' ? ok('docs write ALLOWED') : bad('docs write allowed', JSON.stringify(a));

  // Fail-closed check: a command that cannot start must deny, not allow.
  let h2 = null;
  plugin.apply({ on: (ev, fn) => { if (ev === 'tools/pre-execute') h2 = fn; } },
    { command: '/nonexistent/verdict', tools: [], timeoutMs: 2000 });
  const f = await h2({ name: 'Write', arguments: {}, callId: 'x' }, async () => ({ kind: 'allow' }));
  f.kind === 'deny' ? ok('missing verdict binary FAILS CLOSED (deny)') : bad('fail closed', JSON.stringify(f));
}

run()
  .catch((e) => { bad('unexpected throw', String(e)); })
  .finally(() => {
    try { unlinkSync(VERDICT); } catch (_) {}
    console.log(`\n  ${pass} passed, ${fail} failed`);
    process.exit(fail > 0 ? 1 : 0);
  });
