# Design-derived contract probes — probes for what arxa builds, not just for the studio

Status: approved by user 2026-08-03 ("the probes should be for any applications
designed, built by arxa and not arxa studio itself, that is being used as a
smoke test for the arxa engine"). Follows the wave-D retirement (5cafaf7);
task #21.

Trigger: after the one-engine consolidation, `arxa design probe` is honestly
"the arxa-studio smoke suite hosted in the engine" — every one of the ten
probe definitions hard-codes studio routes (`/design`, `/intake`, `/build`) and
is compiled into arxa via `registry.dart`. The harness, CLI, and CDP layer
are design-agnostic; the probe *content* is not. That is the same misplacement
shape the placement law exists to catch: the engine knows one design by name.
By contrast `design lint` (W1–W6), `selftest`, and `check-wiring` already take
any artifact dir.

## Vocabulary (one term each, D6 discipline)

- **Contract probe** — asserts the arxa opinion (panels, chips, no-reload
  HDA behavior) against ANY served design, deriving its targets from the
  design's own declarations. The behavioral sibling of the W-gate.
- **Studio suite** — the existing ten probes: the engine's smoke test, run
  through its reference design (arxa-studio). Legitimate engine concern,
  named for what it is.

## Deliverables

1. **Registry split** (`arxa/lib/probes/registry.dart`): two suites,
   `contract` and `studio`. Files move to `lib/probes/contract/` and
   `lib/probes/studio/` (git mv; probe_base.dart, probe_cli.dart,
   registry.dart stay at the root). CLI: suite names become selectable —
   `arxa design probe contract|studio|all|<name…>`. `all` = every suite,
   contract first (cheap, read-only-leaning probes lead, per the existing
   run-order doctrine). Existing `probe all` call sites gain contract coverage
   automatically — that is the opinionated behavior we want, not a regression.
2. **Route discovery** (engine-level, design-agnostic): contract probes need
   the design's surface list. Preference order, decided at implementation by
   what is already served: (a) the served route/registry artifact the server
   already exposes (design_server_test.dart:362 proves app.routes.js is
   served; registry.json is the authored source); (b) if neither parses
   cleanly from Dart, add a tiny `/__routes` JSON introspection endpoint to
   design_server (same family as `/__projects`), with a test. No probe may
   hard-code a route.
3. **Contract probe v1 set** — small, each mutation-tested, each REQUIRED to
   pass on BOTH arxa-studio and the hello-hda example (the proof of
   design-agnosticism):
   - `contract-panels`: for every discovered surface — declared role panels
     (header/main/activity/composer/footer) each mounted at most once;
     `.panel-*` structural classes appear only in the panel shape (behavioral
     twin of W3/W4).
   - `contract-chips`: for every discovered surface — every `.chip` obeys the
     box model (inline-flex, align-items center, pill radius by computed
     style) AND every glyph centers in its control: `button svg, summary svg,
     .chip .status-dot` vertical center within 1px of its container's center.
     This lands the icon-alignment gate from the a02ceaa fix as a UNIVERSAL
     check (supersedes the earlier note to add it to the studio
     panel-contract probe — universal placement is strictly better).
   - `contract-no-reload` (stretch, may defer to v2): a boosted GET
     navigation does not hard-reload — plant a window marker, click the first
     boosted link, assert the marker survives. If the generic form proves too
     design-variable, defer and record why in the capability map; do not ship
     a vacuous version.
4. **Docs**: capability map gains a "suites" section (contract vs studio, and
   why); VOCABULARY.md gains the two suite terms; this plan referenced from
   the map.

## Phase 3 (recorded, deliberately not built now)

The scaffolder emits a probe manifest per generated app (from the design's
registry + shell composition) and contract probes consume it — the same
"design declares, engine enforces" shape as W-gate. Blocked on the scaffolder
having per-app build evidence; see the data-static parked item.

## Rules (unchanged, from wave D)

- Disposable-project guard applies to every suite: `-probe`/`-test` names
  only; explicit target; `~/.arxa/current` untouched.
- Every new check is mutation-tested (kill widgets.css → contract-chips
  fails; unmount/duplicate a panel → contract-panels fails; each proves
  non-vacuous before it counts).
- Uniform non-zero exit on failure; harness-owned trailer.
- Probes for a design run against a served disposable copy, sequential,
  quiet machine, `dart test -j 2` on this hardware (disk finding, wave D).

## Verification (definition of done)

- `arxa design probe contract` green on arxa-studio AND hello-hda, from
  the same binary, no per-design code paths.
- `arxa design probe all` green (contract + studio) on arxa-studio.
- Mutation evidence per contract probe recorded in the capability map.
- `dart analyze` clean; `dart test -j 2` green (registry move breaks no test).
- Zero hard-coded routes in `lib/probes/contract/` (greppable: no `/design`,
  `/intake`, `/build` string literals).
