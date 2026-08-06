---
name: appbox-builder
description: Use when filling the extension-point View/ViewModel bodies in an emitted target. Views COMPOSE the adaptive primitive layer (lib/ui/primitives.dart) once — the per-platform native family (glass/expressive/shadcn) lives in the primitives, not the views. Trigger on "build the screens", "implement the views", "fill the primitives", "builder".
---

# builder — fill extension points by composing adaptive primitives

## Core principle
The blueprint emits two things this role relies on:
1. the **adaptive primitive layer** (`lib/ui/primitives.dart`, generated) — `AdaptiveScaffold`, `AdaptiveButton`, `AdaptiveCard`, `AdaptiveTextField`, `AdaptiveSegmented`, `AdaptiveProgress`. Each reads `currentStrategy()` and renders the native family internally.
2. empty View/ViewModel **stubs** (`@appbox-extension-point`).

This role fills the stubs by **composing the primitives ONCE** from `breakdown.json`. A view never branches on platform and never writes a `switch(currentStrategy())` — that triplicated every view and is why glass/expressive went unfilled. Same breakdown → same widget code (freeze + replay — ADR-0002 #5).

## The three families (inside the primitives, not the views)
- **glass** (iOS) — real native Liquid Glass via `native_liquid_glass` (`UiKitView` → UIKit, iOS 26+; graceful fallback elsewhere). True-native, honors the mandate.
- **expressive** (Android) — real native Material 3 Expressive via Jetpack **Compose**, embedded as a Flutter `PlatformView` (`_ExpressiveView` → `AndroidView 'appbox/expressive'`; Kotlin `ExpressivePlatformView.kt` is emitted by `emit.py`, NOT the snapshot golden — it patches the `stacked create` scaffold: Compose plugin + `material3:1.5.0-alpha*` + AGP≥9.1 + Gradle≥9.3.1 + compileSdk 37). Compose-embed covers the LEAF primitives whose whole surface is the touch target — button, segmented, progress. Composite primitives (cards-with-content, text fields) and content-width inline buttons stay Flutter Material 3 (a platform view is a leaf — can't host Flutter children — and content-width needs an intrinsic-sizing leaf). All Material 3; diverges from iOS glass.
- **shadcn** (web/desktop) — `shadcn_ui` `Shad*` (^0.55.0).

> ⚠️ **Platform-view touch + coordinates.** Embedded-Compose primitives are platform views: drive their taps with a real motion sequence and exact on-screen coordinates (an off-by-a-card y looks like "the widget is dead" — it isn't). `EagerGestureRecognizer` is set so they receive taps inside scrollables.

## Input
- `.blueprint/<source>/breakdown.json` — `pages[].components[].primitives[]` = the widget inventory per screen.
- The emitted target (extension-point files carry `@appbox-extension-point`; `lib/ui/primitives.dart` is generated — read it for the available widgets).

## Per screen (screenFlow → pages join)
For each `<Screen>View` + `<Screen>ViewModel`:
1. Match the page by screen id; its `components[].primitives[]` is the inventory.
2. Map each breakdown primitive to the matching `Adaptive*` widget (`action.button`→`AdaptiveButton`, `surface.card`→`AdaptiveCard`, `input.text-field`→`AdaptiveTextField`, `action.segmented`→`AdaptiveSegmented`, `feedback.spinner`→`AdaptiveProgress`, the page scaffold→`AdaptiveScaffold`). Data-viz (`data.chart`, `display.stat`) is platform-identical — paint it with `CustomPainter`.
3. **Hybrid / jank rule:** scrolling list rows use `AdaptiveCard(lite: true)` (Flutter-drawn even under glass — platform views jank in long lists). Reserve real glass platform views for static surfaces (headers, buttons, segmented). Stat deck = content (solid paper/dark/accent fills in the scroll body) → opaque `AdaptiveCard`, never glass — see design-systems/liquid-glass.md THE RULE.
4. Style is automatic (primitives read `AppTokens`). Populate content + interactions from the ViewModel; async → `setBusy`/`setError` (ADR-0003); Ports locator-injected; Supabase stays in infrastructure.
5. If the design needs a primitive the layer lacks, ADD it to `lib/ui/primitives.dart` (generated, with all three family branches) — never hand-roll a native widget inside a view.

## Rules
- **Compose, don't branch.** No `switch(currentStrategy())` in a view; no raw `LiquidGlass*`/`Shad*`/`AndroidView` in a view. Those belong only in `primitives.dart`.
- **Native is real on both mobile platforms** — glass (iOS Liquid Glass) and expressive (Android Jetpack Compose M3). There is no silent approximation; any deviation is flagged and isolated to `primitives.dart`.
- **Gestures.** Swipe-to-delete (`Dismissible`), long-press menu (`showAdaptiveActions`), pull-to-refresh (`AdaptiveRefresh`), scroll-snap (`PageView`) are shared Flutter, native where the idiom differs (the menu/refresh dispatch on `currentStrategy()` inside the primitive). Swipe-to-delete with no repo `delete` is an optimistic local hide — flag it as not-persisted.
- **Don't touch generated-layer files** (`AUTO-GENERATED` marker) except `primitives.dart` when adding a primitive. Edit `@appbox-extension-point` files freely.
- **Determinism:** freeze filled Views/ViewModels into `.blueprint/<source>/built/` and replay. Drift → gated diff, not silent rebuild.

## i18n (when the design carries `l10n/`)
- **Never hardcode a user-visible string.** `Text('…')`/`label: '…'` copy literals in `lib/ui/views/**` fail the review gate's `no_hardcoded_strings` check. Views resolve copy via `AppLocalizations.of(context)!.<key>` (stock gen-l10n; keys come from the design's `app_en.arb` template).
- **ViewModels are context-free** — they read copy through a tiny app-layer service holding the latest `AppLocalizations`, attached once from the root view's builder:
  ```dart
  class L10nService {
    AppLocalizations? _l10n;
    AppLocalizations get l10n => _l10n!;
    void attach(BuildContext context) => _l10n = AppLocalizations.of(context)!;
  }
  ```
- **Capability wiring:** register `AppBoxKitI18n` + `AppBoxKitLocaleStore` (appbox_kit_i18n) in the stacked locator, and give the settings surface a language row — System / English / Polski (system locale + persisted override, live switch).
- **Generative UI:** every generative-UI prompt includes `appBoxKitI18n.llmLocaleDirective()` in the system prompt, so generated copy lands in the active locale.

## Kit wiring (when stub headers declare `kits`)

Stubs carry `//   kits (builder wires): <names>` — the designer's declaration,
threaded through `structure.json`. For each named kit:

- Wire its **real providers** via locator injection, per the kit's playbook
  (`kit/<name>/<name>_playbook.mdx`) and the providers + verification tiers in
  `config/kit-registry.json`.
- **Never offer a `stub`-tier provider to users.** A provider whose registry
  tier is `stub` is unproven — wire it only as a dev fallback and flag it; the
  advertise gate fails a shipped surface that presents one.
- Required credentials come from `config/credentials.catalog.json` (match by
  `module: kit/<name>`) and are read from the environment / credential store at
  runtime — **never hardcoded** in the app. Name the missing keys in your
  handoff notes instead of inventing values.

## Output
- Filled `*_view.dart` / `*_viewmodel.dart` composing the primitive layer. Run `arch_guard` → must PASS before handoff to tester.
