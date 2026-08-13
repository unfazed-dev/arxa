# Perf measurement — Flutter/native coexistence cost (2026-08-13)

Goal: measurable frame-timing numbers for the law-governed compositions on the
real device (iPhone, iOS 26.6, ProMotion), not element counts. The
platform-view overlay work is compositor cost — it only exists on device, so
`kit/showcase_app/test/slowness_measurement_test.dart` (element census) cannot
see it.

## Method

- `--profile` build with a `PERF_PROBE` dart-define; probe code lives in the
  tab host (single file, reverted after the run).
- `SchedulerBinding.addTimingsCallback` collects per-frame `buildDuration`,
  `rasterDuration`, `totalSpan`, `vsyncOverhead`, tagged with the active
  scripted phase.
- Scripted tour, fixed distances/durations for comparability (600px legs,
  2s per leg, driven `animateTo` — physics-independent):
  1. `home_scroll` (8s) — icon-button rows, segmented, progress, split button
  2. `search_scroll` (8s) — search bar, sliders, switches
  3. `profile_scroll` (8s) — rail, toolbar, native buttons
  4. `motion_scroll` (8s) — pushed route: glass cards + segmented + switch
  5. `tab_switch` — 8 driven switches at 800ms (set-constancy path)
  6. `notes_scroll` (8s) — chrome scaffold with ZERO in-scroll platform
     views: the Flutter-only baseline the others are read against
- Scroll driver finds the live vertical `ScrollableState` by element-tree walk
  (no per-view controllers).
- Results JSON written to app Documents (`perfprobe_results.json`), pulled via
  `devicectl device copy from`, stats computed host-side: avg/p50/p90/p99/max
  for build and raster, % frames over the 8.3ms (120Hz) and 16.7ms (60Hz)
  budgets, per phase.

## Deliverable

`docs/research/perf-measurement-native-coexistence.md` with the numbers table
and a verdict: does any law-governed composition breach the frame budget, and
which phase is closest to the edge.
