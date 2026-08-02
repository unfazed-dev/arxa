// Shared target resolution for every probe in this directory.
//
// WHY THIS EXISTS: every probe used to resolve its target as
//   const BASE = process.env.APPBOX_BASE || 'http://localhost:4319';
// and NONE of them read process.argv. So `node tools/probe-x.mjs --port 4335`
// silently ran against 4319 — the shared dev server — while the operator
// believed it was hitting an isolated instance they had just booted. That cost
// a real incident: probes ran flow-mutating requests against a live project,
// and a whole root-cause investigation was built on runs that had never
// targeted the server they claimed to.
//
// Three rules, in order of importance:
//   1. An argument that cannot be honoured is a HARD ERROR, never a no-op.
//      A flag that looks supported and does nothing is worse than no flag.
//   2. The resolved base is PRINTED before any check runs, so a misdirected
//      run is visible in the first line of output instead of invisible.
//   3. --base / --port beat APPBOX_BASE, which beats the 4319 default.

const DEFAULT_BASE = 'http://localhost:4319';
const KNOWN = new Set(['--base', '--port', '-b', '-p']);

// ── waiting on conditions instead of on the clock ────────────────────────
//
// The suite-wide shape was: click, `waitForTimeout(1400)`, read the DOM, assert.
// That asserts on whatever the page happened to look like 1400ms later. Every
// one of those numbers was picked on an idle machine, and the studio's writes
// are async (facade.undo awaits a file write; #panelsSwap re-renders the whole
// stage) — so under load the read lands mid-transition and the probe reports a
// regression that is not there. It fails in the other direction too, and worse:
// on a fast machine the wait is pure dead time, and a genuinely broken feature
// can still "settle" into a passing state within the window.
//
// `waitFor` polls the condition the NEXT assertion depends on, with a bounded
// timeout — bounded because an unbounded wait converts a real regression into a
// hang, which is harder to diagnose than a fast failure.
//
// On timeout it does NOT throw: it returns false and prints why. A probe's job
// is to report every check, so one slow condition must not abort the remaining
// checks the way a thrown Playwright TimeoutError does.
/// Count in-flight view transitions in the page. MUST be called on a fresh page
/// before its first `goto` (it installs an init script, so it survives
/// navigations).
///
/// `base.html` sets htmx-config `globalViewTransitions: true`, so EVERY swap in
/// the studio runs inside `document.startViewTransition`. That is what made the
/// naive "poll for the post-condition" rewrite worse than the fixed sleeps it
/// replaced: the condition (a class landing on a tile) becomes true INSIDE the
/// transition callback, while the transition is still playing. A probe that
/// acts at that instant starts a second transition, the browser reports
/// `Transition was skipped`, and the swap is lost — the probe then reports a
/// regression it caused itself.
///
/// Waiting for the DOM to go quiet does not cover this: `::view-transition`
/// pseudo-elements are not in the DOM, so the tree is already still while the
/// animation plays. The only honest signal is the transition's own `finished`
/// promise, which means wrapping the API.
export async function trackTransitions(page) {
  await page.addInitScript(() => {
    // htmx's own "this swap is done" event, counted. A probe that needs to know
    // a swap landed should ask htmx, not guess from the DOM: "is .design-viewer
    // present" is true before the click as well as after, so a wait built on it
    // returns instantly and asserts nothing (that mistake is what this counter
    // replaces).
    window.__hxSettled = 0;
    addEventListener('htmx:afterSettle', () => { window.__hxSettled++; }, true);

    window.__vtBusy = 0;
    const d = document;
    const orig = d.startViewTransition && d.startViewTransition.bind(d);
    if (!orig) return; // no support → __vtBusy stays 0, waits are unaffected
    d.startViewTransition = (cb) => {
      window.__vtBusy++;
      const t = orig(cb);
      const done = () => { window.__vtBusy = Math.max(0, window.__vtBusy - 1); };
      // `finished` rejects on a skipped transition — settle either way, or one
      // skip would wedge the counter above zero and hang every later wait.
      t.finished.then(done, done);
      return t;
    };
  });
}

/// `polling` is an INTERVAL, never Playwright's default `'raf'`: a rAF-driven
/// poll runs a callback every frame, which is needless contention with the
/// animation frames the transition itself needs.
export async function waitFor(page, fn, { timeout = 8000, label = '', arg } = {}) {
  try {
    await page.waitForFunction(fn, arg, { timeout, polling: 100 });
    // The condition held — but it may have held mid-transition. Let any
    // transition drain before the caller acts on the page. Cheap when
    // trackTransitions was never installed (the expression is 0 === 0).
    await page.waitForFunction(
      () => (window.__vtBusy || 0) === 0, undefined,
      { timeout: 5000, polling: 50 },
    ).catch(() => {});
    return true;
  } catch (e) {
    console.log(`  [warn] timed out after ${timeout}ms waiting for` +
      ` ${label || 'a condition'} — the check below reports the real state`);
    return false;
  }
}

/// Wait for the DOM to stop changing — the honest replacement for a blanket
/// `settle()` sleep at call sites where there is no single condition to name
/// (a full-stage re-render touching several panels at once).
///
/// Preferred over naming a condition ONLY when the alternative would be a
/// guess: an assertion that waits for the wrong condition is worse than one
/// that waits too long, because it passes vacuously. Where the post-condition
/// is known, use `waitFor`.
///
/// Two consecutive identical samples [quietMs] apart, or [timeout], whichever
/// comes first. The sample is element count + innerHTML length together: length
/// alone collides across a swap that happens to produce the same-size markup,
/// and a collision reads as "quiet" when the page is still moving.
///
/// Strictly better than the fixed sleep it replaces in both directions — it
/// returns as soon as the page is actually still (usually faster than the old
/// 700–900ms), and it keeps waiting when the machine is loaded, which is the
/// case that produced the phantom failures.
export async function waitQuiet(page, { quietMs = 120, timeout = 8000 } = {}) {
  const started = Date.now();
  let prev = null;
  while (Date.now() - started < timeout) {
    const now = await page
      .evaluate(() => `${document.querySelectorAll('*').length}:${document.body.innerHTML.length}`)
      .catch(() => null);
    if (now !== null && now === prev) return true;
    prev = now;
    await page.waitForTimeout(quietMs);
  }
  console.log(`  [warn] the DOM never went quiet within ${timeout}ms —` +
    ' the checks below report whatever state it reached');
  return false;
}

export function resolveBase(argv = process.argv.slice(2)) {
  let base = null;
  let port = null;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    // Accept both `--port 4335` and `--port=4335`.
    const eq = a.indexOf('=');
    const key = eq === -1 ? a : a.slice(0, eq);
    const inline = eq === -1 ? null : a.slice(eq + 1);

    if (!a.startsWith('-')) continue;
    if (!KNOWN.has(key)) {
      // Rule 1. Silently ignoring this is the exact bug this file exists for.
      console.error(
        `probe: unsupported argument ${JSON.stringify(a)}.\n` +
        `       Supported: --base <url> | --port <n>. Or set APPBOX_BASE.\n` +
        `       Refusing to run rather than silently target ${DEFAULT_BASE}.`);
      process.exit(2);
    }
    const value = inline ?? argv[++i];
    if (value == null || value.startsWith('-')) {
      console.error(`probe: ${key} needs a value.`);
      process.exit(2);
    }
    if (key === '--base' || key === '-b') base = value;
    else port = value;
  }

  if (base && port) {
    console.error('probe: pass --base OR --port, not both.');
    process.exit(2);
  }

  const resolved = base
    ?? (port ? `http://localhost:${port}` : null)
    ?? process.env.APPBOX_BASE
    ?? DEFAULT_BASE;

  const via = base ? '--base'
    : port ? '--port'
      : process.env.APPBOX_BASE ? 'APPBOX_BASE'
        : 'default';
  // Rule 2. First line of every probe run, always.
  console.log(`probe target: ${resolved}  (via ${via})`);
  if (via === 'default') {
    console.log(
      'probe target: NOTE — this is the shared dev server. Pass --port to isolate.');
  }
  return resolved;
}

// ── refusing to mutate a project that isn't disposable ───────────────────
//
// WHY THIS EXISTS: probe-shell-chrome.mjs's flow-move (section F) and
// probe-inspect.mjs both drive real POSTs into whatever project the target
// server has bound as its projectRoot. `resolveBase` above stops a probe
// from running against the WRONG SERVER by accident; it does nothing about
// a probe running against the RIGHT SERVER while it happens to be serving
// the user's real project — and that has corrupted real `portalo` data
// three times, because the only defense was an operator remembering to
// copy the project and pass --base every time. This makes that mechanical:
// every mutation probe calls requireDisposableProject(BASE) before it goes
// near Chrome, and it exits non-zero rather than let a click reach a
// server that isn't demonstrably disposable.
//
// GET /__projects -> { current, boundProject, projects }.
//
//   `current` is NOT the boot-time-bound projectRoot; it's a live read of
//   the global ~/.appbox/current marker file (design_server.dart's
//   /__project_use handler says so outright: "the overlay itself rebinds
//   on the next serve"). Two ways that lies:
//     - a server booted with `--project <name>` never touches the marker,
//       so `current` keeps reporting whatever it already said. Verified:
//       `design serve ... --project portalo-probe` on a spare port still
//       returned `current: "portalo"` from /__projects.
//     - a server's marker can be flipped by ANOTHER process (POST
//       /__project_use, or `appbox project use`) without restarting it,
//       so `current` can report a disposable name while the server is
//       still actually bound to the real project underneath.
//   This guard used to read `current` anyway (no alternative existed) and
//   documented that risk as accepted, not solved. It was then proven live:
//   a server booted `--project portalo-endpointtest` with the marker left
//   at `portalo` reported `current: "portalo"` — the SAFE-looking value —
//   while actually bound to the non-disposable copy. `current` is not used
//   below anymore; it's kept in this comment only as the reason the next
//   field exists.
//
//   `boundProject` is the fix: the project this process resolved ONCE at
//   boot (--project > APPBOX_PROJECT > the marker as it stood then), read
//   straight from projectRoot. It is a per-process fact — no other process
//   can flip it, and a server started with --project is not blind to it
//   the way it is to `current`. Proven to disagree with `current` in
//   exactly the dangerous direction (case above): `boundProject` correctly
//   read "portalo-endpointtest" on that same request. This is what closes
//   the gap the first paragraph left open — the risk noted above no longer
//   applies to this guard, only to any other code still reading `current`.
//
// Disposable means `boundProject` ends in -probe or -test — the existing
// convention (the incident writeup already called the safe copy
// `portalo-probe`), and the one thing an operator can act on immediately:
// the message below is the exact command that satisfies it.
//
// `boundProject: null` is a different case from "unknown": it's the server
// stating, as a fact, that no project is overlaid (artifact-only serving).
// Checked what a mutation probe could do to that: /__project_write (the
// ONE channel every project write goes through — flow-move included; see
// fixture_reader.js's writeProjectFixture) resolves `base = target project
// ?? projectRoot` and returns `deny(409, 'no project overlaid')` when
// `base` is null (design_server.dart _handleProjectWrite). Neither probe's
// client code sends an explicit `project` override in the write body, so
// with no project bound there is no file for a write to land in — the
// server's own contract refuses it before this guard would ever need to.
// Failing closed here would be refusing a target that literally cannot be
// corrupted; this guard lets `boundProject: null` proceed, with a printed
// note, instead of erroring on a state that isn't the danger it exists to
// stop.
//
// A missing `boundProject` key entirely is neither of the above — it means
// a server binary from before this field existed, and whether IT enforces
// the same /__project_write refusal is genuinely unknown. That fails
// closed, same as an unreachable server: absence of the fact is not the
// fact "no project bound."
const DISPOSABLE_RE = /-(?:probe|test)$/;

export async function requireDisposableProject(base) {
  let projects;
  try {
    const res = await fetch(`${base}/__projects`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    projects = await res.json();
  } catch (e) {
    // Unreachable, non-JSON — either way "cannot confirm," and cannot-
    // confirm fails closed, same as an unsupported --flag above: a silent
    // pass here is the exact bug this file exists to prevent, just moved
    // one level up.
    console.error(
      `probe: could not confirm ${base} is serving a disposable project\n` +
      `       (GET /__projects failed: ${e.message}).\n` +
      `       Refusing to run a mutation probe against an unverified target.`);
    process.exit(2);
  }

  if (!('boundProject' in projects)) {
    // Older server binary, pre-boundProject. This is unknown, not null —
    // do not treat it as "no project bound."
    console.error(
      `probe: could not confirm ${base} is serving a disposable project\n` +
      `       (GET /__projects has no "boundProject" field — this server\n` +
      `       binary predates that field). Refusing to run a mutation\n` +
      `       probe against a target this guard can't read.`);
    process.exit(2);
  }

  const { boundProject } = projects;

  if (boundProject === null) {
    // Stated fact, not missing information: nothing is overlaid, so
    // /__project_write has nothing to write into either (see comment
    // above). Nothing for a mutation probe to corrupt.
    console.log(`probe target: ${base} has no project bound (artifact-only) — proceeding.`);
    return;
  }

  if (typeof boundProject !== 'string' || !DISPOSABLE_RE.test(boundProject)) {
    console.error(
      `probe: ${base} is bound to project "${boundProject}", which is not\n` +
      `       disposable (its name must end in -probe or -test). This\n` +
      `       probe mutates whatever project it's pointed at — running it\n` +
      `       here risks the exact corruption this guard exists to stop.\n` +
      `       Make a disposable copy and serve THAT on a spare port:\n` +
      `         cp -R ~/.appbox/projects/${boundProject} ~/.appbox/projects/${boundProject}-probe\n` +
      `         dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --project ${boundProject}-probe --port 4330\n` +
      `       then run this probe with --base http://localhost:4330\n` +
      `       (boundProject is fixed at boot and belongs to this process\n` +
      `       alone, so --project is fine here — nothing to get out of\n` +
      `       sync with, unlike the old current-marker recipe.)`);
    process.exit(2);
  }

  console.log(`probe target: confirmed disposable project "${boundProject}" (boundProject)`);
}
