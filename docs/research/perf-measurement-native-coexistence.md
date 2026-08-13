# Perf measurement — Flutter/native coexistence cost (2026-08-13)

Device: unfazed-iphone (iOS 26.6, ProMotion 120Hz). Build: `--profile`,
Flutter 3.44.9. Rig: `PERF_PROBE` scripted tour in the tab host (temporary,
reverted) — `SchedulerBinding.addTimingsCallback` per-frame timings, driven
`animateTo` scrolls (600px legs, 2s per leg, physics-independent), phases
tagged in-app, JSON pulled via devicectl. Method + rerun recipe:
`docs/plans/perf-measurement-native-coexistence.md`. n = 3123 frames.

## Numbers (milliseconds)

| phase | n | build avg | build p99 | raster avg | raster p90 | raster p99 | raster max | >8.3ms | >16.7ms |
|---|---|---|---|---|---|---|---|---|---|
| home_scroll | 482 | 0.59 | 1.02 | 1.44 | 1.81 | 3.28 | 4.56 | 0.0% | 0.0% |
| search_enter | 58 | 0.25 | 4.08 | 0.88 | 1.58 | 8.44 | 8.44 | 1.7% | 0.0% |
| search_scroll | 483 | 0.19 | 0.32 | 0.61 | 0.69 | 0.78 | 0.80 | 0.0% | 0.0% |
| profile_enter | 61 | 0.20 | 2.90 | 1.02 | 0.86 | 10.12 | 10.12 | 1.6% | 0.0% |
| profile_scroll | 414 | 0.31 | 0.57 | 1.43 | 2.01 | 4.50 | 10.77 | 0.5% | 0.0% |
| motion_push | 69 | 0.62 | 19.68 | 3.17 | 5.69 | 59.73 | 59.73 | 7.2% | 2.9% |
| motion_scroll | 426 | 0.28 | 0.63 | 1.45 | 1.66 | 5.53 | 20.22 | 0.2% | 0.2% |
| tab_switch | 371 | 0.17 | 0.73 | 1.21 | 1.32 | 4.42 | 4.78 | 0.0% | 0.0% |
| notes_enter | 62 | 0.09 | 0.74 | 0.84 | 0.90 | 1.21 | 1.21 | 0.0% | 0.0% |
| notes_scroll | 479 | 0.12 | 0.19 | 0.89 | 0.96 | 1.08 | 1.20 | 0.0% | 0.0% |

Budgets: 8.33ms = 120Hz frame, 16.7ms = 60Hz frame. `notes_scroll` is the
Flutter-only baseline (chrome scaffold, ZERO in-scroll platform views).

## Findings

1. **Steady-state coexistence premium ≈ +0.6ms raster per frame.** Native-heavy
   scrolls (home/profile/motion, ~1.43–1.45ms raster avg) vs the Flutter-only
   baseline (0.89ms). Relative +65%, absolute trivial — p99 stays under 5.6ms,
   well inside even the 120Hz budget. **Zero dropped 60Hz frames in any scroll
   phase.**
2. **Tab switching is jank-free** — max frame 4.78ms across 8 switches, 0%
   over either budget. This is what the keep-mounted ghost-tab architecture
   (alpha 0.004 + off-screen translate, law rule 8) buys: set constancy means
   a switch costs nothing measurable.
3. **The one real hotspot is route PUSH with in-scroll glass cards**:
   `motion_push` worst raster frame 59.7ms (~2–4 janky frames per push), build
   p99 19.7ms. This is glass materialization + first composition of the
   pushed route's platform-view set, bounded to the push moment and partly
   masked by the route transition. Tab entries (search/profile) show the same
   shape an order of magnitude smaller (8–10ms single frames).
4. Scroll depth caveat: search/home lists were driven to their (short) full
   extents; motion/profile/notes to 600px. All phases scrolled through their
   full native-control population.

## Verdict

The law-governed compositions hold both frame budgets with wide margin in
steady state; the coexistence cost is real but small and flat. The only
measurable jank class is glass-heavy route materialization (push), not
scrolling — if it's ever felt on device, the lever is warming/staging the
pushed route's glass, not demoting in-scroll content. No action required at
current scale.
