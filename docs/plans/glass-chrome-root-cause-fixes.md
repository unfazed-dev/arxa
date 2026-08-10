# Glass Chrome Root-Cause Fixes — APPROVED, ALL CODE ITEMS CLOSED

**Status: C1–C6 all resolved as of 2026-08-10 (master `a3e615f`). The only remaining step is
the on-device pass — see "Closure" at the end of this file.**

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

> **⚠️ C1's stated mechanism was DISPROVEN on 2026-08-10 — see "C1 correction" below.
> It is a jank fix, not a flicker fix. The table row is kept as authored for the record.**

| # | Cause | Evidence | Explains |
|---|-------|----------|----------|
| C1 | ~~`future:` constructed inside `build()` in 5 vendor components → FutureBuilder identity-reset → `SizedBox` → UiKitView teardown/recreate + re-rasterize per rebuild~~ **(mechanism false; real cost is redundant re-resolution)** | `icon.dart:139,168` · `button.dart:385,413` · `glass_button_group.dart:266` · `popup_menu_button.dart:364,370` | ~~flicker (all contexts)~~, slowness |
| C2 | Chrome gate hides on **global static** transition counter, no mount-scope guard (contrast modal check's `_mountDepth` on same lines); nested routers each add an observer; watchdog holds ~1.35 s | `chrome_gate.dart:186-187`, `transition_observer.dart:51,40`, `nested_router.dart:93` | tab bar hidden during notes-shell transitions; obscure glitch |
| C3 | `appbox_kit_native_icon_button.dart:89` passes `customIcon:` unconditionally → shadows SF Symbol, forces raster branch on most numerous surface (FAB/split/toolbar guard it; rationale at `fab.dart:80-81`) | audit §3 | flicker + cold-start/build cost |
| C4 | **Scroll-edge tree-shape flip** (2026-08-10 trace, promoted): `scroll_edge_effect.dart:171` returns `widget.child` raw at `t == 0`, wrapped in 4 levels (`IgnorePointer > Opacity > ClipRect > ImageFiltered`) at `t > 0` → Element not reused → subtree unmounts, platform views destroyed/re-created at every crossing. **The remount is the visible artifact** (at flip: sigma 0.16, alpha ≈ 0.983 — imperceptible). No hysteresis: single boundary both directions at `:163` (`t <= 0.02`). Post-frame `_recompute` at `:124` → create→destroy→create on first mount for cards starting under chrome. 10 showcase sites; `showcase_notes_folder_view.mobile.dart:182-183` chains it twice per row; `showcase_split_button_card_widget.dart:53` puts glass card + `CNButton` under the flip. Pure Dart — zero channel traffic. **Independent of the cluster; survives fixing C1/C2/C3.** | audit §4 (rewritten) | scroll-edge breakage ("lists break all the time"), scroll flicker, first-load flicker |
| C5 (secondary) | Three uncoordinated tab-bar hide paths: 160 ms fade vs instant `SizedBox` swap vs `IndexedStack` swap | `chrome_gate` + `tab_bar.dart:540,566` | fade-then-pop artifacts |
| C6 (cost only) | ~~Scroll occlusion gate: per-scroll `getOffsetToReveal` + ≤50 `setState`s over platform-view subtrees~~ **MEASURED 2026-08-10: not a real cost, no fix made — see C6 postscript** | `scroll_occlusion_gate.dart:147-179` | ~~scroll stutter~~ |

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
6. ~~**C6 — occlusion-gate cost**~~ **CLOSED, no code change.** Measured after C4; the
   prescribed fix was already present. See postscript.
7. Re-verify on device (profile): the four symptom repros from the user, one by one.

**Execution order (user-confirmed 2026-08-10): C1 → C4 → C2 → C3 → C5 → C6.**
C4 touches only `scroll_edge_effect.dart` + showcase call sites — not gated on the Stage 2
icon-pipeline commit (which gates C1's five vendor files).

## Rollout

Single worktree, one fix per commit, vendor `flutter analyze` + targeted tests green per step,
device profile check after C1–C3 land (they compound; measure cluster effect there).

## Status (2026-08-10)

**Landed on master:** Stage 2 icon pipeline (`4f85531`), C4 scroll-edge shape stability +
hysteresis (`920d108`), C3 customIcon guard (`8a73281`), C2 chrome-gate scoping (`da41ad9`).
All merged clean.

**Green baseline, re-measured on the merged tree after each merge:**

| Suite | Baseline `2301f39` | After C2 | After C1 |
|---|---|---|---|
| `kit/ui_library` | 263 / 263 | 265 / 265 (＋C2's 2) | 265 / 265 |
| `kit/ui_library/vendor/cupertino_native_better` | 113 / 113 | 113 / 113 | 118 / 118 (＋C1's 5) |

C1 also passed `flutter build ios --simulator` (exit 0). C1 coverage gaps it declared
honestly: the `customIcon` path is untested headless (`iconDataToImageBytes` never completes
in `flutter_test`), CNIcon's native branch is hard-gated by
`PlatformViewGuard.isTestEnvironment`, and the tests assume a macOS 26+ host.

**Next:** C5 (single tab-bar hide authority) and the §3d tab-switch fade question above, which
is now the only open lead on the remaining flicker.

### C6 postscript — measured, already fine, deliberately not "fixed"

Second audit claim corrected by measurement (same class of error as C1: the *count* was right,
the *consequence* was not). Verified independently before acceptance.

Method: temporary widget-test harness (run, recorded, deleted), child hoisted to one `final`
instance so only the gate's own `setState` was counted. 300 × 1px steps — denser than any
60 fps fling.

| Shape | scroll notifications | alpha changes (setStates) | child rebuilds |
|---|---|---|---|
| gate in scrolling sliver under pinned bar | 300 | 48 | **0** |
| one setState, 7-element subtree | — | 1 | **0** |
| **production shape** (pinned `SliverPersistentHeader`) | 300 | **0** (alpha pinned 1.0) | **0** |

Why the audit was wrong: `build()` returns `IgnorePointer > Opacity > widget.child` with
`widget.child` an *identical instance* across the gate's own setState, so
`Element.updateChild` short-circuits — the rebuild scope is two wrapper widgets, never the
child subtree. And `appbox_kit_scroll_occlusion_gate.dart:177` (`if (alpha == _alpha) return;`,
above it alpha quantized to 1/50 with 0.98/0.02 deadbands) **already is** the "notify only on
change" fix this plan prescribed.

Production exposure: exactly **one** call site repo-wide —
`showcase_notes_folder_view.mobile.dart:128`, via the `.scrollOcclusion()` extension (a
`AppBoxKitScrollOcclusionGate` grep misses it). It does sit over a platform view
(`AppBoxKitNativeSearchBar` → `CNSearchBar` → `UiKitView`), and is still never rebuilt: the
header is pinned, so alpha stays 1.0 and `RenderOpacity` skips the saveLayer too. The
call-site comment at :117-119 already documented this.

Residual cost, named honestly: one `getOffsetToReveal` walk per scroll frame, O(depth ≈ 7),
× 1 live gate app-wide. Under frame noise — not zero.

Steelman (why it exists): on iOS every `CN*` `UiKitView` composites in a native layer *above*
the Flutter scene, so the compositor clip chain — unreliable during scroll (flutter/flutter
#25965, #76097, #154664) — is all that occludes it under pinned chrome, leaving a sharp ghost.
Driving alpha to exactly 0 drops it from the layer tree and detaches the native view. Per
ADR 0010 part 3 its residual duty is the modal-depth path
(`CNTabBarRouteObserver.anyModalDepth`) — event-driven, not per-frame. `scroll_edge_effect.dart:40`
records that C4's widget supersedes it for scroll duty.

Left `unknown`: on-device profile confirmation — widget tests cannot measure raster time.

### C1 correction — the top-ranked flicker cause was mechanically false

C1 landed (`d57d5e3`, `b710440`, `e5756e2`) but **disproved its own premise**, and the audit's
#1 ranking with it.

**Claimed:** a new `future:` identity per rebuild resets the FutureBuilder snapshot → the
`!hasData` placeholder (`SizedBox`) renders → the `UiKitView` subtree is torn down and
re-created → flicker.

**Disproven, primary source** (`flutter/lib/src/widgets/async.dart`, verified in this repo's
pinned SDK at `/Volumes/developer_ssd/dev/fvm/versions/stable`):

```dart
// :612 didUpdateWidget → :619, when the future identity changes
_snapshot = _snapshot.inState(ConnectionState.none);
// :280 — inState PRESERVES data
AsyncSnapshot<T> inState(ConnectionState state) =>
    AsyncSnapshot<T>._(state, data, error, stackTrace);
```

`data` survives, so `hasData` stays true and the placeholder branch is **never taken on a
rebuild** — only on genuine first load. Agent probe agreed: `UiKitView` count stayed at **1
across 5 parent rebuilds**, no placeholder frame.

**What was really wrong, and is now fixed:** unbounded redundant re-resolution — 2 asset-bundle
loads per parent rebuild (2 after first mount → 12 after 5 rebuilds), plus a redundant
`setState` per resolution. On the `customIcon` path each rebuild redid a full
`PictureRecorder → toImage → toByteData` **on the main isolate**. That is real per-frame jank
during scroll and route animation — it maps to the user's "scroll stutter / transition lag /
cold start", not to the flicker.

**Consequence for the remaining hunt:** flicker during **tab switching** now has no confirmed
mechanism. Scroll and first-load flicker are explained by C4 (a genuine remount), and the tab
bar vanishing during navigation by C2. The open suspect is audit §3d:
`animated_tab_stack.dart:277,281` fades tab layers, while `tab_host_widget.dart:53-54` states
"slide-only: fade ghosts platform views" — and commit `20616f2` deliberately *added* a
crossfade. Fading a `UiKitView` is exactly the operation that comment warns against.

### C2 postscript — the recovered patch was broken in four ways

The partial work salvaged from the killed agent looked plausible and was not. Kept: the
observer-registry + ancestor-walk design, the conservative detached-observer fallback, the
test's two-case shape. Rewritten:

1. **Infinite loop** — `Navigator.maybeOf(nav.context)` returns `nav` *itself* (Flutter SDK:
   `if (context case StatefulElement(:final NavigatorState state)) navigator = state;`).
   Replaced with `nav.context.findAncestorStateOfType<NavigatorState>()`.
2. **Prune race** — the lazy prune also matched a freshly-constructed, not-yet-attached
   observer, permanently dropping it. Hosts build observers from a closure
   (`navigatorObservers: () => [CNTransitionObserver()]`), so that window is hit on every
   router rebuild. Fixed with a `_wasAttached` latch.
3. Missing `@visibleForTesting` import.
4. **Vacuous assertion** — after a push settles, the Overlay stops building entries below the
   opaque top route, so the gate is *disposed*; a pop-then-check-restore passes even if restore
   is entirely broken. Rewritten to pop mid-flight and assert element identity against a
   pinned `Element`.

Known test-only hazard: `resetForTesting()` clears `_instances`, discarding `_wasAttached`
bookkeeping. Harmless as used (`setUp` precedes `pumpWidget`), but an observer constructed
before a reset and used after one would be silently deregistered — it registers only in its
constructor.

### Incident notes (cost real time — see the `agent-worktree-hazards` memory)

1. Subagent worktrees branch from `origin/master`, which was **12 commits behind** local
   master. One agent spent an entire run re-deriving `6b6dc8c`'s watchdog fix; its
   `transition_observer.dart` came out byte-identical to master's — a pure no-op — while the
   briefed `appbox_kit_native_chrome_gate.dart` scoping fix went untouched. Every dispatch now
   carries a mandatory `git merge master` step 0.
2. An agent whose worktree had been deleted (torn down when its parent coordinator stopped)
   fell back to editing the **main checkout**, then died mid-edit on `glass_button_group.dart`,
   leaving 300 lines of non-compiling changes. `flutter analyze` reported 76 errors that looked
   like they came from the Stage 2 merge but were entirely uncommitted working-tree state.
   Recovered to `stash@{0}`; drop it once C1 lands.
3. Agent-reported green checks were authored on stale bases and did **not** transfer — the
   baseline above was re-run on the merged tree, not inherited from their reports.

## §3d verdict + C5 landing (2026-08-10, base `4317b93`)

### §3d — the tab-stack fade contradiction is FALSE; the audit misread an opt-in branch

The audit read `appbox_kit_animated_tab_stack.dart:277,281` as fading tab layers. Both lines
sit behind `if (widget.fade)`. `fade` defaults to **`false`** (`:73`), and the **only**
production call site — `showcase_application_tab_host_widget.dart:56` — never sets it
(`grep` over `kit/`, non-test, finds one call site and no `fade:` argument on it). The
branches are dead at runtime. The comment at `tab_host_widget.dart:53-54` ("slide-only") and
the code therefore **agree**; there is no contradiction to reconcile. Pinned already by
`appbox_kit_animated_tab_stack_test.dart:250` ("fade stays off by default (platform-view
safety)", `expect(find.byType(FadeTransition), findsNothing)`) — green on this base.

### Steelman of `20616f2` — and its commit message is misleading

`20616f2` is titled "crossfade exiting tab layer…", but its diff **adds no fade**. It:
1. changed the incoming layer's travel from `begin: travel` (0.18) to `begin: Offset(_direction * 1.0, 0)` — full-width **cover** entry;
2. swapped paint order so the exiting layer is **under** the incoming one.

`docs/plans/tab-switch-pop-cover-parallax.md` states it explicitly: "`fade` stays opt-in with
unchanged semantics". **Why it exists:** with `fade: false` the old geometry painted the
opaque exit slot **on top**, travelling only 18% of the width; when the controller completed,
`_exitingIndex = null` removed a layer still covering ~82% of the frame **in one frame** —
regression `3b81414`, a measured one-frame pop. Cover geometry fixes it the platform-view-safe
way: completion happens while the exiting layer is fully occluded, so its removal is
invisible, and **no opacity is animated over a `UiKitView`**. This is the correct fix and was
left untouched. `6412916`'s live-run `ColoredBox` backing is the necessary companion —
background-less tab pages make a "cover" transparent, so the cover must carry the scaffold
color to actually occlude.

**The one live fade over platform views is elsewhere:** `appbox_kit_native_chrome_gate.dart:252-254`
wraps native chrome in `FadeTransition` + `ScaleTransition` **unconditionally**, and its own
doc at `:72` concedes opacity is only *"reliably"* applied to platform views under hybrid
composition and that scale is not. That runs on every push/pop over gated chrome. Whether it
ghosts on device is **`unknown`** — not decidable headless.

### Tab-switch flicker still has NO confirmed Flutter-side mechanism

With C1 corrected, C2/C3/C4 landed and §3d disproven, nothing found in this pass explains
flicker *on a tab switch specifically*. The C5 race below fires on **route push/pop over the
tab host**, not on a tab switch — see the discriminating fact. Status: **`unknown`**, needs a
device trace.

### C5 — single hide authority (landed)

**Discriminating fact:** `CNTabBar._pageTransitioning` is driven by
`ModalRoute.of(context).secondaryAnimation` (`vendor/.../tab_bar.dart:381-382`), **not** by
`CNTransitionObserver.activeTransitions`. A `StackedTabsRouter` tab switch pushes no route
above the host, so `secondaryAnimation` never runs and this path does **not** fire on a tab
switch. It fires when a route is pushed **over the tab host**.

**The race (real, test-confirmed):** on that event two authorities act on the same widget —
the chrome gate fades alpha 1→0 over 160 ms (`hideDuration`, `:99`), while `CNTabBar`'s
`IndexedStack` (`tab_bar.dart:566-574`) blanks it **instantly** in frame one. The instant swap
wins; the fade is spent on something already invisible. That is the "fade-then-pop".

**Fix:** `appbox_kit_tab_bar.dart:101` now passes `autoHideOnPageTransition: false` — the
gate is the single authority. Safe against the vendor warning at `tab_bar.dart:558-565` (which
guards against the wrapper toggling *while the feature is on*): a constant `false` returns the
bare platform view every build, so tree shape stays invariant and the `UiKitView` is never
re-created.

**Deliberately NOT collapsed:** `autoHideOnModal` stays `true`. The vendor requires the modal
hide to **destroy** the platform view (`tab_bar.dart:521-526`, Issue #31 — the UITabBar layer
otherwise renders over modal content); the gate's keep-alive alpha-0 does not destroy it, and
the gate's own doc `:71` concedes a fade kept the native view bleeding through. Those two
claims cannot be reconciled headless, so the third path is left as a **documented exception**
rather than an unverified z-order regression. Both states are pinned by
`appbox_kit_tab_bar_single_hide_authority_test.dart`.

**Verification on this base:** `flutter analyze --no-pub` clean in `kit/ui_library` and in the
vendor; `flutter test` **267 passing / 0 failing** in `kit/ui_library` (265 baseline + 2 new);
**118 passing** in `vendor/cupertino_native_better`. No `pubspec.lock` churn.

### C5 follow-ups from review

**The gate's signal is really installed** (this decides fix-vs-regression): removing
`autoHideOnPageTransition` hands sole authority to a path that only works if
`CNTransitionObserver` is registered on the navigator enclosing the gate. It is —
`kit/showcase_app/lib/main.dart:97`, `navigatorObservers: () => [CNTransitionObserver()]`.
Had it not been, this change would have deleted the only working hide and let the native bar
ride over an incoming page.

**The tab-switch negative is now watched, not inferred.** "A tab-index change hides nothing"
is pinned by the third case in `appbox_kit_tab_bar_single_hide_authority_test.dart`
(observer installed, boot push settled, index 0→1, `IgnorePointer.ignoring` stays false). If
that ever goes true, tab-switch flicker HAS a Flutter-side mechanism.

**`unknown` — bar height.** Dropping the `IndexedStack` changes the layout parent: the old
shape sized against `max(SizedBox(height: h), platformView)` under `StackFit.passthrough`
with `h = widget.height ?? _intrinsicHeight ?? 50.0`; the new shape sizes to the platform view
alone. If `h` ever exceeded the native view's height the bar's rendered height shifts a few
points. Not observable headless — the native tier does not render in a widget test. Verify on
device alongside the C5 fade-then-pop check.

## Closure (2026-08-10, master `a3e615f`)

All six items resolved. Green on every merge, re-run on the merged tree rather than trusted
from agent reports: `kit/ui_library` **268/268**, vendor `cupertino_native_better` **118/118**,
`flutter build ios --simulator` exit 0.

| Item | Outcome | Commit |
|---|---|---|
| C1 stable icon futures | landed — but a **jank** fix; its flicker premise was disproven | `e5756e2` |
| C2 chrome-gate scoping | landed — fixes the Notes tab-bar disappearance | `da41ad9` |
| C3 customIcon guard | landed — SF Symbols back on the native path | `8a73281` |
| C4 scroll-edge shape stability | landed — fixes the scrolling-list breakage | `920d108` |
| C5 single hide authority | landed | `034d55f` |
| C6 occlusion-gate cost | **closed, no code change** — measured, already fine | — |

### Three audit claims were corrected by evidence

The audit reliably located *where* things happen but repeatedly over-attributed *consequences*.
Weigh its remaining claims accordingly.

1. **C1** — `AsyncSnapshot.inState` preserves `data` (SDK `async.dart:280`, `:612-619`), so a
   rebuilt FutureBuilder never shows its placeholder. No teardown. Probe: `UiKitView` count
   stayed 1 across 5 rebuilds.
2. **C6** — the setState count was right (48/300 steps), the blast radius was not: identical
   `widget.child` instance ⇒ `Element.updateChild` short-circuits ⇒ **0** child rebuilds. The
   prescribed fix already existed at `:177`.
3. **§3d** — the tab-stack fade sits behind `if (widget.fade)`, default `false` (`:73`), and no
   production caller sets it; the only `fade: true` in the repo is the test that pins the
   opt-in. Code and the "slide-only" comment agree.

### Remaining: on-device pass (profile/release, physical device)

Symptoms 2, 3 and the slowness have Flutter-side fixes to confirm. **Symptom 1's tab-switch
case has no confirmed Flutter-side mechanism** — if it still flickers, the leads below are the
place to look, not the fixed items.

- [ ] Scrolling lists no longer "break" at the scroll-edge threshold (C4).
- [ ] Notes shell: tab bar stays put during push/pop inside a tab (C2).
- [ ] No fade-then-pop on the tab bar during route transitions over the tab host (C5).
- [ ] Scroll stutter / transition lag / cold start improved (C1).
- [ ] **Tab-switch flicker — now has a fix (C7 below), not just a lead.** Switches are an
      instant native cross-cut on iOS as of `0c2b2d8`. Confirm the flicker is gone; if any
      remains it is the return-visit `Offstage` re-add, which C7 documents as inherent.
      *(The old "Lead 1" pointing at the chrome gate was wrong twice — see the C7 correction.)*
- [ ] **Regression watch:** bar height. C5 dropped the `IndexedStack`, changing the layout
      parent from `max(SizedBox(h), platformView)` to the platform view alone. If `h` exceeded
      the native height the bar shifts a few points. Not observable headless.

## C7 — tab-switch flicker: the animation itself was the mechanism (2026-08-10, `0c2b2d8`)

**Found by asking the Phase 4.5 question rather than patching again.** `20616f2`
(cover-parallax geometry) and `6412916` (opaque live-run backing) were attempts 1 and 2 at
stopping the tab-switch animation from producing artifacts, and
`docs/plans/tab-switch-pop-cover-parallax.md` lists a third, deferred: *"first visit inflates a
full tab shell mid-animation → dropped frames"*. Three attempts on one symptom is the
systematic-debugging signal to stop fixing symptoms and question the architecture.

**The architecture answer is that iOS has no tab-switch animation.** `UITabBarController`
cross-cuts — it has never slid, faded or parallaxed (HIG "Tab bars"). The paired slide was a
non-native affordance, and it was not free: a run necessarily paints BOTH tabs at once, so the
frame's platform-view set and z-order change mid-switch, and the iOS embedder answers that by
recomposing its overlays and merging the raster and platform threads. Going instant drops the
exit slot as well, so the outgoing tab's `GlobalKey` reparent stops happening as a side effect.

**Fix:** `AppBoxKitAnimatedTabStack` gains `animated`, defaulting to `!AppBoxKitPlatform.isIOS`.
Instant is a real cross-cut, not a zero-duration animation — no controller run, no exit slot,
no reparent, one frame. Material keeps the paired slide, where tab bodies are Flutter-rendered
and cost nothing to have on stage together; `animated: true` forces the slide back.

**Verified:** `kit/ui_library` **272/272** (268 baseline + 4 new), `flutter analyze` clean. The
instant case asserts exactly one non-offstage `Offstage` per frame and zero slide translation.
The `animated: true` case under the same iOS override is its **control** — identical setup,
both tabs on stage — so the instant assertions are demonstrably not vacuous.

**Scope of the claim, stated honestly.** Two mechanisms were on the table; this removes one.

| Mechanism | Status |
|---|---|
| Both tabs on stage during a run → frame's platform-view set and z-order change mid-switch | **removed** (test-pinned, Flutter-side) |
| A returning tab leaves `Offstage` → its platform views were absent from the layer tree, so they are re-added to the native hierarchy | **remains** — inherent to any kept-alive tab stack, `IndexedStack` included |

The second is not fixable without painting every tab all the time, which trades a per-switch
cost for a permanent one and a worse cold start. What changed is that it now lands in a single
frame with **no animation for the thread merge to stall** — which is how the native control
behaves. The Flutter-side facts are test-pinned; the *native* consequence (overlay
recomposition / thread merge) is inferred from documented embedder behaviour and the chrome
gate's own rule at `:14-17` — **not** measured headlessly. The device pass decides it.

### Correction — the old "Lead 1" was wrong twice

The closure named `appbox_kit_native_chrome_gate.dart:252-254` the prime suspect, saying "its
own doc at `:72` concedes the scale is not reliably applied". Both halves fail:

1. **The doc says the opposite,** and lives at `:76-80`, not `:72` (`:72` is the blur-scrim
   paragraph): *"Opacity is the one mutator iOS hybrid composition applies to platform views
   fully reliably; the scale is kept slight (0.95) — larger transforms on platform views are
   dicier, and any translate would move pixels."* The slight scale is a deliberate, reasoned
   choice that masks the reattach. **No change made** — steelman, not defect.
2. **The gate never fires on a tab switch.** Already pinned by the third case in
   `appbox_kit_tab_bar_single_hide_authority_test.dart`, and by C5's discriminating fact: a
   `StackedTabsRouter` tab switch pushes no route, so `secondaryAnimation` never runs.

That is **four** audit/closure claims now corrected by evidence in this engagement. The pattern
holds: locations accurate, consequences over-attributed. Weigh any remaining claim accordingly.
