# Confirm ship — Gate 3 (the strictest)

Actor: Evan (founder, ship mode) · Shell: ship-shell · Surfaces:
`ship.confirm` → `stage_shell_ship_confirm_view` (Gate 3 — the triple) ·
Decision refs: architecture.md §17 (deploy is a third human gate, the strictest)

## Trigger

The build passed Gate 2 (accepted). Evan navigates to `ship.confirm` to release.

## Entry / exit

- Entry criteria: Gate 2 accepted (green build); deploy targets selected
  (`ship.targets`); `doctor()` preflight passed.
- Exit states: **released** — the triple confirmed, deploy executed, artefacts
  shipped to the named target · **abandoned** — person cancels before confirm;
  nothing is written to the outside world · **blocked** — `doctor()` preflight
  failed (missing credentials, signing identity, shorebird install).

## Happy path

1. `ship.targets` selected: fastlane-ios, fastlane-android, shorebird-release,
   cloudflare-pages — each showing wired/stubbed status. **Vercel is a stub
   (throws `UnimplementedError`) and must not be advertised** (architecture.md
   §17).
2. `doctor()` preflight runs: checks credentials, signing identity, shorebird
   install, CF Pages API token. Preflight is not a gate — it is a readiness
   check. Failures route to settings, not to a red gate.
3. `ship.confirm` renders **the triple**: target (e.g. "App Store, account
   leo-strength-co"), version (e.g. "1.2.0, build 47"), account (the store
   account that will receive the submission). The blast radius is stated:
   *"This submits version 1.2.0 to the App Store under account leo-strength-co.
   An App Store submission cannot be rolled back by re-running a stage."*
4. Evan confirms the exact triple. The approval token is minted by the person —
   an agent may prepare, run `doctor()`, reach the gate, and stop; it cannot
   mint the token (architecture.md §12, §17).
5. Deploy executes: fastlane submits, shorebird patches, CF Pages deploys.
   `ship.released` shows shipped version and rollback info (where available).

## Decision points

- **Confirm vs cancel:** confirm → deploy executes (irreversible); cancel →
  nothing written, return to `ship.targets`.
- **Multiple targets:** the triple names each target separately — confirming
  "ios + android" confirms two submissions, each with its own account and
  version. The blast radius states all of them.
- **`doctor()` pass vs fail:** pass → proceed to confirm; fail → blocked with
  the missing item named (credential, signing identity, token). Route to
  settings.

## Edge cases

- **Design moved after Gate 2 approval but before ship:** the approval hash
  check at Gate 2 was bound to the design hash. If the design moved, Gate 2's
  approval is invalidated — `done` exits non-zero. Ship is blocked; route back
  to design (architecture.md §6).
- **Shorebird patch vs release:** a patch updates an existing release (hot
  patch); a release creates a new version. The triple distinguishes them —
  "shorebird-patch on 1.2.0" vs "shorebird-release 1.3.0".
- **CF Pages deploy fails:** the deploy is a write to the outside world; a
  network failure mid-deploy leaves a partial state. The ledger records what
  completed; the person decides whether to retry or roll back.
- **Offline:** `doctor()` cannot verify credentials or tokens offline — the
  preflight blocks with a clear message, not a silent green.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `stage_shell_ship_targets_view` — target selection, wired/stubbed status |
| 2 | `doctor()` preflight result (inline, not a separate surface) |
| 3–4 | `stage_shell_ship_confirm_view` — the triple + blast radius + confirm |
| 5 | `ship.released` (null surface) — shipped version, rollback info |

## Notes

- Gate 3 is the only gate that writes to the outside world. Every other gate is
  a read-only assertion; this one is irreversible (architecture.md §17).
- Deploy targets are already wired in `stacked_kit_deploy`: fastlane-android,
  fastlane-ios, shorebird-release, shorebird-patch, cloudflare-pages. Vercel
  throws and must not be offered (architecture.md §17).
- The `KitProcessRunner` port lets `ScriptedProcessRunner` assert every command
  shape with no toolchain in CI — a deploy stage that can self-test
  (architecture.md §17).
- Michelle's counterpart: `../michelle-buyer/ship-shell/take-code-and-leave.md`
  — she takes the output repo, not a deployed artefact. Her journey ends at the
  code, not the store.
