/**
 * Integration test for the Pi gate extension.
 *
 * Loads harness/pi/arxa-gate.ts through jiti — the SAME loader Pi uses to run
 * .ts extensions without a build step — then drives the registered `tool_call`
 * handler and checks its return value against Pi's documented veto contract:
 *   return { block: true, reason } to deny; return undefined to allow.
 *
 * What this proves: the extension compiles under jiti, registers on tool_call,
 * shells to the shared guard, and returns a correctly-shaped block object.
 * What it does NOT prove: that a booted `pi` session dispatches tool calls to
 * it. That needs Pi configured with model credentials — see harness/README.md.
 *
 *   node harness/pi/test.mjs
 */
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const REPO = join(here, '..', '..');

let pass = 0, fail = 0;
const ok = (m) => { pass++; console.log(`  PASS ${m}`); };
const bad = (m, d) => { fail++; console.log(`  FAIL ${m}${d ? `\n       ${d}` : ''}`); };

/** Resolve jiti from the global pi install, the way Pi loads extensions. */
function loadJiti() {
  const piBin = spawnSync('sh', ['-c', 'command -v pi'], { encoding: 'utf8' }).stdout.trim();
  if (!piBin) return null;
  const real = spawnSync('sh', ['-c', `readlink -f "${piBin}" 2>/dev/null || realpath "${piBin}"`],
    { encoding: 'utf8' }).stdout.trim();
  // <prefix>/lib/node_modules/@earendil-works/pi-coding-agent/...
  const guess = spawnSync('sh', ['-c',
    `ls -d "$(dirname ${real})"/../node_modules/jiti "$(dirname ${real})"/../../jiti 2>/dev/null | head -1`],
    { encoding: 'utf8' }).stdout.trim();
  const require_ = createRequire(import.meta.url);
  for (const cand of [guess, 'jiti'].filter(Boolean)) {
    try { return require_(cand); } catch (_) {}
  }
  return null;
}

console.log('== pi arxa-gate extension ==');

const jiti = loadJiti();
if (!jiti) {
  console.log('  SKIP jiti not resolvable — cannot load the .ts extension the way Pi does');
  console.log('       (install Pi: npm i -g @earendil-works/pi-coding-agent)');
  process.exit(0);
}
ok('jiti resolved (the loader Pi uses for .ts extensions)');

const load = jiti(import.meta.url, { interopDefault: true, esmResolve: true });
let factory;
try {
  const mod = load(join(here, 'arxa-gate.ts'));
  factory = mod?.default ?? mod;
} catch (e) {
  bad('extension compiles under jiti', String(e).slice(0, 200));
  console.log(`\n  ${pass} passed, ${fail} failed`);
  process.exit(1);
}
typeof factory === 'function'
  ? ok('extension compiles under jiti and default-exports a factory')
  : bad('extension default-exports a factory', `got ${typeof factory}`);

// Drive it with a minimal ExtensionAPI stand-in that captures the handler.
let handler = null;
factory({ on: (ev, fn) => { if (ev === 'tool_call') handler = fn; } });
handler ? ok('registers a tool_call handler') : bad('registers a tool_call handler');

const call = async (toolName, input, mode) => {
  process.env.ARXA_GUARD_MODE = mode;
  return handler({ toolName, input, toolCallId: 't1' }, {});
};

const run = async () => {
  // PROOF OF LIFE: only a real interception can produce a block object.
  const blocked = await call('edit', { file_path: join(REPO, 'arxa', 'lib', 'x.dart') }, 'using');
  blocked && blocked.block === true
    ? ok('protected write BLOCKED (block:true — cannot come from a no-op)')
    : bad('protected write blocked', `got ${JSON.stringify(blocked)}`);

  if (blocked && typeof blocked.reason === 'string' && blocked.reason.includes('USING-session')) {
    ok('block carries the guard reason through to the model');
  } else {
    bad('block carries the guard reason', `reason=${JSON.stringify(blocked?.reason)?.slice(0, 80)}`);
  }

  const allowed = await call('edit', { file_path: join(REPO, 'docs', 'n.md') }, 'using');
  allowed === undefined
    ? ok('docs write ALLOWED (undefined = proceed)')
    : bad('docs write allowed', `got ${JSON.stringify(allowed)}`);

  const dev = await call('edit', { file_path: join(REPO, 'arxa', 'lib', 'x.dart') }, 'dev');
  dev === undefined ? ok('dev mode ALLOWS the same write') : bad('dev mode allows', JSON.stringify(dev));

  // Pi's lowercase `bash` tool name must map onto the same policy.
  const sh = await call('bash', { command: `echo x > ${join(REPO, 'arxa', 'z.dart')}` }, 'using');
  sh && sh.block === true
    ? ok('lowercase pi tool name `bash` hits the same policy')
    : bad('bash blocked', `got ${JSON.stringify(sh)}`);

  // A guard that cannot run must fail OPEN, never wedge the session.
  process.env.ARXA_GUARD_PATH = '/nonexistent/guard.js';
  const open = await call('edit', { file_path: join(REPO, 'arxa', 'lib', 'x.dart') }, 'using');
  delete process.env.ARXA_GUARD_PATH;
  open === undefined
    ? ok('missing guard FAILS OPEN (session never wedged)')
    : bad('fails open', `got ${JSON.stringify(open)}`);
};

run()
  .catch((e) => bad('unexpected throw', String(e)))
  .finally(() => {
    console.log(`\n  ${pass} passed, ${fail} failed`);
    process.exit(fail > 0 ? 1 : 0);
  });
