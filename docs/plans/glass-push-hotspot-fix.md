# Glass route-push hotspot fix (2026-08-14)

Goal: eliminate the one measured jank class — route push with in-scroll glass
cards (`motion_push` worst raster frame 59.7ms, 2.9% > 16.7ms, see
`docs/research/perf-measurement-native-coexistence.md`) — with a REUSABLE
arxa primitive, so any route full of glass can be pushed clean.

Advisor consult: skipped (no API key configured — standing protocol), decided
on device evidence.

## Phase 1 — decompose the cost (measurement before fix)

The 59.7ms is "glass materialization + first composition of the pushed
route's platform-view set". Two candidate mechanisms with DIFFERENT fixes:

- **First-push-only** (per-process pipeline/shader/material warm-up): pushes
  2..n are cheap. Fix = a one-time warmer at app boot that materializes a
  tiny off-screen glass view (rule-8 translate keeps it slicing-safe).
- **Every-push** (per-push UiKitView creation + overlay/texture allocation,
  roughly linear in platform-view count): all pushes jank equally. Fix =
  stage the pushed route's glass — defer the native tier until the route
  transition settles (Flutter frosted tier during transition, swap after),
  or stagger platform-view mounting across frames.

Probe: `PERF_PROBE` dart-define rig back in the tab host (temporary,
reverted after) — same `addTimingsCallback` collection, but the tour is
3 repeated `pushNamed('motion')` / `pop()` cycles on the profile tab's stack,
phases `push1..3` / `settled1..3` / `pop1..3`. JSON to app Documents, pulled
via devicectl, stats host-side.

Decision rule: `push2`,`push3` worst raster < 2× steady-state p99 (~11ms)
while `push1` still spikes → warm-up primitive. `push2/3` ≈ `push1` →
staging primitive. Mixed (both real) → warmer first, re-measure, then stage
what remains.

## Phase 2 — the reusable primitive (shape depends on Phase 1)

Lives in `kit/ui_library`; law doc gets the rule; a widget test pins the
mechanism. Candidates:

- `ArxaKitGlassWarmup` — boot-time, self-removing (or kept, translated
  100000px off-screen per law rule 8) 1-instance glass materializer.
- Route-entrance staging scope consumed by the existing tier machinery
  (glass card & friends already resolve native-vs-Flutter tier), keyed off
  the enclosing route's transition animation.

## Phase 3 — verify

Re-run the push probe; motion_push must drop under the 16.7ms budget
(target: 0% > 16.7ms, worst frame ideally < 2× steady p99). Update
`docs/research/perf-measurement-native-coexistence.md` with before/after.
Revert probe, clean build back on device.

## Outcome (2026-08-14) — DONE, warm-up branch taken

Decomposition said first-push-only → `ArxaKitGlassWarmup` shipped
(ui_library, law rule 9). Two kinds needed warming for the Motion route:
the surface container (glass card) and the switch; boot-visible kinds warm
themselves. Verified over two relaunches: first push worst frame 11–12ms,
0% > 16.7ms (was 39.6ms / 4.8%). Numbers table in the research doc. The
staging branch (Phase 2 alternative) was not needed and was not built.
