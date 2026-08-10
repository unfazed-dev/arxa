# Glass Chrome Root-Cause Fixes (Phase 3 hypothesis — awaiting user sign-off)

Date: 2026-08-10. Advisor consult attempted, recorded **skipped** (no API key in env or
`~/.config/consult-mode/api-key.json`); proceeding on primary sources.

## Symptoms (user-confirmed, device profile/release — real, not debug artifacts)

1. Flicker in ALL contexts: navigation push/pop, screen first-load, scrolling, tab switching.
2. Scroll-edge ("obscure"): trigger visibly flips; scrolling lists "break all the time".
3. Notes shell: tab bar hidden **only during** push/pop transition, returns on settle.
4. Slowness: scroll stutter, transition lag, cold start. Touch response fine (hit path healthy).

## Evidence

- `docs/research/showcase-glass-wiring-audit.md` (pinned to HEAD `34c53b0`, 14 file:line cites spot-checked)
- `docs/research/liquid-glass-native-best-practices.md` (Apple primary sources, 55 links)
- `docs/research/flutter-platform-view-best-practices.md` (Flutter docs/engine + upstream cupertino_native)

## Hypothesis (single cluster; items compound multiplicatively)

**H: Every symptom reduces to platform views being torn down / hidden by Flutter-side rebuild
machinery, not by native glass behavior.**

| # | Cause | Evidence | Explains |
|---|-------|----------|----------|
| C1 | `future:` constructed inside `build()` in 5 vendor components → FutureBuilder identity-reset → `SizedBox` → UiKitView teardown/recreate + re-rasterize per rebuild | `icon.dart:139,168` · `button.dart:385,413` · `glass_button_group.dart:266` · `popup_menu_button.dart:364,370` | flicker (all contexts), slowness |
| C2 | Chrome gate hides on **global static** transition counter, no mount-scope guard (contrast modal check's `_mountDepth` on same lines); nested routers each add an observer; watchdog holds ~1.35 s | `chrome_gate.dart:186-187`, `transition_observer.dart:51,40`, `nested_router.dart:93` | tab bar hidden during notes-shell transitions; obscure glitch |
| C3 | `appbox_kit_native_icon_button.dart:89` passes `customIcon:` unconditionally → shadows SF Symbol, forces raster branch on most numerous surface (FAB/split/toolbar guard it; rationale at `fab.dart:80-81`) | audit §3 | flicker + cold-start/build cost |
| C4 | **Scroll-edge tree-shape flip** (2026-08-10 trace, promoted): `scroll_edge_effect.dart:171` returns `widget.child` raw at `t == 0`, wrapped in 4 levels (`IgnorePointer > Opacity > ClipRect > ImageFiltered`) at `t > 0` → Element not reused → subtree unmounts, platform views destroyed/re-created at every crossing. **The remount is the visible artifact** (at flip: sigma 0.16, alpha ≈ 0.983 — imperceptible). No hysteresis: single boundary both directions at `:163` (`t <= 0.02`). Post-frame `_recompute` at `:124` → create→destroy→create on first mount for cards starting under chrome. 10 showcase sites; `showcase_notes_folder_view.mobile.dart:182-183` chains it twice per row; `showcase_split_button_card_widget.dart:53` puts glass card + `CNButton` under the flip. Pure Dart — zero channel traffic. **Independent of the cluster; survives fixing C1/C2/C3.** | audit §4 (rewritten) | scroll-edge breakage ("lists break all the time"), scroll flicker, first-load flicker |
| C5 (secondary) | Three uncoordinated tab-bar hide paths: 160 ms fade vs instant `SizedBox` swap vs `IndexedStack` swap | `chrome_gate` + `tab_bar.dart:540,566` | fade-then-pop artifacts |
| C6 (cost only) | Scroll occlusion gate: per-scroll `getOffsetToReveal` + ≤50 `setState`s over platform-view subtrees | `scroll_occlusion_gate.dart:147-179` | scroll stutter (demoted: not the flip mechanism) |

Cluster: C1/C2/C3 compound multiplicatively. C4 is independent. Audit's severity ranking:
C1 > C4 > C2 > C3 > C5 > C6.

### Verified negatives (do NOT re-chase)
- Notes tab bar does not structurally unmount (sits above the nested Navigator). Correct per platform-view doc rule "mount chrome once at root above per-tab Navigator".
- No per-frame method-channel traffic; no SVG re-rasterization.
- Tab bar returns nil `UITabBarAppearance` **deliberately** (iOS 26 glass opt-in) — do not "fix".
- Interactive glass shimmer on touch is by-design (`Glass.interactive`).
- `PlatformViewGuard` 500 ms startup swap is debug-only (`kReleaseMode` → immediately ready); ruled out by release repro.
- Scroll-edge is pure Dart — no `invokeMethod` for scroll/edge/obscure anywhere; native `scrollEdgeAppearance` only in `CupertinoTabBarPlatformView.swift:224,357,946` (tab bar).
- Home has **5** platform views, not 8 — `AppBoxKitNative*` prefix is naming convention, not a platform-view marker (`AppBoxKitNativeProgress`/`LoadingIndicator` are `CupertinoActivityIndicator`).
- `cn_transition_observer_test.dart` does **not** exist; the transition tests are `appbox_kit_directional_tab_transition_test.dart`, `appbox_kit_glass_transition_gate_test.dart`, `appbox_kit_tab_switch_transition_test.dart`.

## Constraints

- **Gated on Stage 2 icon-pipeline commit** (dart-resolver worktree touches the same 5 files). No edits before it lands.
- User decisions: prefer system-native behavior over custom reproductions; root-cause cluster first.
- Systematic-debugging: one hypothesis test at a time, minimal failing test before each fix.

## Fix order + minimal failing test per item

1. **C1 — stable futures.** Resolve icon source in `initState`/`didUpdateWidget` (or memoize keyed on inputs), never in `build()`; keep last-good child while re-resolving (no `SizedBox` gap).
   *Failing test:* pump widget, trigger unrelated parent rebuild, assert platform-view child is **not** re-created (same state object / no second create call on the mocked channel).
2. **C2 — scope the chrome gate.** Hide only when the transition belongs to the gate's own navigator scope (mirror the `_mountDepth` pattern already used for modals); make counter per-scope, not static.
   *Failing test:* nested-router push inside one tab; assert root tab bar's gate never receives hide. New test file beside `appbox_kit_glass_transition_gate_test.dart` (no `cn_transition_observer_test.dart` exists).
3. **C3 — guard `customIcon` at `appbox_kit_native_icon_button.dart:89`** exactly as FAB does.
   *Failing test:* construct with SF-symbol-only input, assert creationParams carry symbol, not raster bytes.
4. **C4 — scroll-edge tree-shape stability + hysteresis.** Primary property: **constant tree shape across the threshold** — keep the 4-level wrapper mounted always, drive sigma/opacity to identity at `t == 0` (never return raw child). Hysteresis is secondary (reduces frequency; each flip stays visible without shape stability): dead band replacing the single `:163` boundary. Kill the `:124` post-frame first-mount create→destroy→create. Per glass-docs rule 6 / system-native preference, evaluate whether native-side appearance can drive the effect instead of Dart entirely.
   *Failing tests:* (a) pump child containing a stateful marker, cross threshold both ways, assert same Element/State survives; (b) oscillation around `t ≈ 0.02` produces ≤1 rebuild; (c) first mount under chrome produces exactly 1 mount.
5. **C5 — single hide authority for tab bar** (chrome gate owns it; remove the two ad-hoc swaps) — expected to shrink after C2.
6. **C6 — occlusion-gate cost** (notify only on state change, no `setState` over platform-view subtrees) — re-measure after C4; may be absorbed by it.
7. Re-verify on device (profile): the four symptom repros from the user, one by one.

**Execution order (user-confirmed 2026-08-10): C1 → C4 → C2 → C3 → C5 → C6.**
C4 touches only `scroll_edge_effect.dart` + showcase call sites — not gated on the Stage 2
icon-pipeline commit (which gates C1's five vendor files).

## Rollout

Single worktree, one fix per commit, vendor `flutter analyze` + targeted tests green per step,
device profile check after C1–C3 land (they compound; measure cluster effect there).
