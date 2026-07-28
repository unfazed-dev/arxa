# Select deploy targets — wire the ship

Actor: Evan (founder, ship mode, P4) · Shell: ship-shell · Surfaces:
`ship.targets` → `stage_shell_ship_targets_view` (fastlane · shorebird ·
CF Pages) · Decision refs: architecture.md §17 (deployer — wired/stubbed
target table; `KitProcessRunner`; `doctor()` preflight)

## Trigger

The build passed Gate 2 (accepted). Evan enters `ship-shell` to pick which
deploy targets the release will write to before the Gate 3 confirm.

## Entry / exit

- Entry criteria: Gate 2 accepted (green build bound to the design hash);
  `stacked_kit_deploy` vendored at the recorded SHA (architecture.md §17).
- Exit states: **primed** — at least one wired target selected, `doctor()`
  preflight passed, route to `confirm-ship.md` (Gate 3) · **blocked** —
  `doctor()` failed on a missing credential, signing identity, shorebird
  install, or CF Pages token; route to settings · **empty** — no target
  selected; the ship cannot proceed, the surface holds Evan here.

## Happy path

1. `ship.targets` renders the deploy target list from
   `stacked_kit_deploy`'s registry, each row carrying a wired/stubbed
   badge: **fastlane-android** WIRED, **fastlane-ios** WIRED,
   **shorebird-release** WIRED, **shorebird-patch** WIRED,
   **cloudflare-pages** WIRED (architecture.md §17).
2. **Vercel is a stub** (throws `UnimplementedError`). It does not render
   as a selectable row — a kit that throws is never offered without a
   STUBBED label, and this one is not offered at all (architecture.md §17).
3. Evan selects one or more wired targets. Selection is the only state the
   person owns here; it lives in `work/run.json` (ship phase, targets set),
   not in the paint.
4. `doctor()` preflight runs against the selected set: store credentials,
   signing identity (iOS), shorebird install, CF Pages API token.
   Preflight is readiness, not a gate — it never goes red for payment
   (architecture.md §17).
5. Preflight passes → route to `confirm-ship.md` **(Gate 3)**, the selected
   targets carried forward as the target column of the triple.

## Decision points

- **Which targets to select:** Evan picks the subset the release should
  reach — store only (fastlane-ios + fastlane-android), a hot patch
  (shorebird-patch on an existing release), a new version
  (shorebird-release), web (cloudflare-pages), or any combination. Each
  confirmed target becomes its own line in the Gate 3 blast radius.
- **`doctor()` pass vs fail:** pass → proceed to Gate 3; fail → blocked,
  the missing item named (credential, signing identity, token, shorebird
  install). Routes to `../settings-shell/configure-credentials.md`, not a
  red gate.

## Edge cases

- **Vercel offered (forbidden):** the stub throws `UnimplementedError`. It
  must not appear as a selectable row. If it ever does, that is a bug in
  the target enumeration, not a valid choice — never advertised while it
  throws (architecture.md §17).
- **`doctor()` fails on missing credential:** blocks with the missing item
  named; routes to `../settings-shell/configure-credentials.md`. No deploy
  executes; nothing is written to the outside world.
- **`doctor()` fails on missing signing identity (iOS):** same block,
  routes to settings — the signing identity must exist before fastlane-ios
  can be primed.
- **Offline:** `doctor()` cannot verify store credentials or the CF Pages
  token against their APIs. The preflight blocks with a clear message, not
  a silent green — never let a target reach Gate 3 unverified.
- **Design moved after Gate 2 but before ship:** Gate 2's approval was
  bound to the design hash; if the design moved, the acceptance is
  invalidated and `ship.targets` cannot prime. Route back to design
  (architecture.md §6).
- **No target selected:** the ship phase cannot proceed; the surface holds
  here with an empty-state message rather than advancing to Gate 3.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–2 | `stage_shell_ship_targets_view` — target list, wired/stubbed badges |
| 3 | `stage_shell_ship_targets_view` — selection state |
| 4 | `doctor()` preflight result (inline, not a separate surface) |
| 5 | route to `stage_shell_ship_confirm_view` (Gate 3) |

## Notes

- `stacked_kit_deploy` is **pure Dart and standalone** — no flutter,
  stacked, or stacked_kit dependency (architecture.md §17). The
  `KitProcessRunner` port lets `ScriptedProcessRunner` assert every
  command shape with no toolchain in CI, so the ship phase self-tests.
- The surface is a **viewer over pipeline state**, never the source of
  truth: selected targets, `doctor()` result, and vendored SHA all come
  from `work/` (`run.json`, `history.jsonl`). Closing the app loses
  nothing.
- Sibling flows: `confirm-ship.md` (Gate 3, consumes the selected targets
  as the triple's target column); `../settings-shell/configure-credentials.md`
  (the route when `doctor()` blocks).
