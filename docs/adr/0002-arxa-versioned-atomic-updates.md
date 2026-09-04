---
status: accepted
date: 2026-09-05
---

# Updates ship as arxa-versioned atomic bundles over a frozen platform pin

arxa studio consumes DeepSeek Harness (dsh) — a pre-1.0 npm platform
publishing 0.x-rc releases roughly weekly under a `next` dist-tag whose
`latest` tag is stale — but its users must never ride that calendar. Every
release is ONE signed/notarized Tauri bundle (shell + studio server + its
exact `@deepseek-ai/*` platform pin + the AOT engine) carrying exactly one
user-visible version: arxa studio's. The team tracks dsh's `next`
deliberately — automated lockstep bump PRs merged only on a green tiered
gate, a never-merged canary CI job against `alpha`, at most one `next`
release behind without a documented hold — and a human presses the stable
release button. Two clocks, one version: the platform's release calendar
never drives the product's (React-canary doctrine; semver §4 makes every
0.x minor a major, so a frozen tested snapshot is the only semver-compliant
thing to ship).

## Considered options

- **A. arxa-versioned atomic bundles over an exact platform pin** —
  chosen. Tauri cannot update sidecars independently, so atomic is also the
  path of least resistance; kits keep their separate ADR-0001 lane.
- **B. Let user installs track dsh `next`** — rejected: hands a pre-1.0
  vendor veto power over arxa's release quality, and no support surface
  exists for "which dsh broke you".
- **C. Split update lanes (app / engine / studio server)** — rejected: a
  13 MB engine does not justify a second custom updater plus a
  version-compatibility matrix.
- **D. Fork dsh** — rejected 2026-08-21 (depend-don't-fork amendment): a
  fork pays a rebase tax on every upstream release, forever.

## Consequences

- Atomic means no delta updates (Tauri has none): bundle size is a
  budgeted number, and the embedded platform makes it worst-case.
- Agent sessions stay open for days: apply-on-restart alone starves
  updates — install-on-quit is required, and the restart affordance must
  never kill unsaved work.
- The merge gate needs a WKWebView boot proof (WebdriverIO/Tauri service),
  not just headless Chromium — Chrome proves the wrong engine — plus
  behavioral contract tests: green CI cannot see semantic drift on a 0.x
  platform.
- Breakage doctrine: hold the pin by default; bridges (config patch / npm
  override / npm ≥12 native `npm patch` with lockfile hash and DEP-3
  headers) carry an upstream issue and a removal condition, with a max-hold
  clock so holds cannot become silent version debt. Custom runtime
  needle-patching is a last resort, not the mechanism. Fork stays banned by
  default, with one documented escape valve.
- Rollback = ship a higher version (Tauri refuses downgrades by default);
  the kill-switch/rollback script exists before the first incident.
- Update feed: R2 primary (`latest.json` `max-age ≤ 300s`, immutable
  artifacts, error pages never 200), GitHub raw fallback — the first
  endpoint returning 200+valid JSON wins, so primary cache discipline is
  load-bearing.
- The minisign release key lives in a protected CI environment with one
  offline encrypted backup; rotation (no revocation exists) rides a
  transition release, and the runbook predates the need.

Full decision log and adversarial cross-check: amendment 2026-09-05 in
`docs/plans/arxa-harness-and-distribution.md`.
