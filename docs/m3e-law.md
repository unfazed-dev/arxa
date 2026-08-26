# The M3E law — Material 3 Expressive on Android, ratified

**THE M3E law** (opened 2026-08-13, ratified alongside the liquid-glass law):
single source of truth for how arxa apps render Android's Material 3
Expressive tier — the first-class Android idiom, not a fallback. Sibling of
the liquid-glass law (docs/liquid-glass-allowlist.md); same discipline:
device evidence in, rules out, enforcement by gates + lint, never prose
alone. Governing principle mirrors Apple-fidelity: **the kit does exactly
what Material 3 Expressive does on stock Android, nothing more, nothing
less** — disputes resolve against Google's own M3E apps and the m3e
collection's documented behavior, not taste.

## Status

Seeded from the kit's existing M3E findings; grows the way the liquid-glass
law did — every rule lands with the device clip or source line that proved
it. Rules below are the current corpus.

## Rules (device/source-proven)

1. **Top bars meet the status bar edge-to-edge.** `AppBarM3E` paints its
   container on an internal Material whose shape token rounds the bar's
   corners — wrong at the screen edge. The kit makes the package container
   transparent and paints its own unrounded, theme-colored rectangle behind
   it (`arxa_kit_native_app_bar.dart` M3E tier; same fix as
   `ArxaKitNativeTabBar._m3e`). Any new M3E chrome must repeat this shape
   discipline.
2. **The tier gate is `wantNative && ArxaKitPlatform.supportsComposeM3E`**
   — the same two-way structural gate shape `ArxaKitNativeTabBar`
   established. Never key M3E rendering off bare `Platform.isAndroid`.
3. **Chrome, where a design declares it, comes from the chrome scaffold.**
   `ArxaKitChromeScaffold` resolves the Android branch to the boxed
   `ArxaKitNativeAppBar` (→ `AppBarM3E`). Hand-assembled top chrome is a
   law violation on this tier exactly as on the glass tier. Scope (ruling
   2026-08-13): this is an ASSEMBLY rule, not an inventory one — the
   designer's frozen anatomy decides whether a surface has top chrome at
   all, resolved per surface through the scaffolder's appbar kind, and a
   surface designed bar-less ships bar-less. A surface never wraps a nested
   router in chrome its pushed routes would inherit (the double-bar ban;
   liquid-glass law → *Chrome existence is the design's call*).
4. **Expressive motion/morph:** M3E's container/scroll motion comes from the
   m3e collection driven by the kit's `M3ETheme` — do not re-implement
   expressive motion in app code. (Morph specifics: no device-proven rules
   yet — first Android device pass owes this section its clips.)
5. **App fidelity mode — sanctioned exception (QF-4, 2026-08-14).** The
   scaffolder's per-platform fidelity map may set Android to `flutter`,
   shipping the Flutter tier wholesale with M3E wiring tree-shaken out —
   the one lawful global demotion, mirroring the liquid-glass law's
   deselect-ladder exception. `mix` is the default (rule 2's gate as-is);
   `native` is strict — an unsupported tier is a build/assert error, never
   a silent fallback. Inside a running `mix`/`native` Android app, demotion
   still follows the allowlist's deselect ladder. Rulings:
   docs/plans/designer-scaffolder-grill-decisions.md QF-1…QF-4.

## Open questions (owed to the first Android device pass)

- Scroll-away behavior parity: does the chrome scaffold's minimize map to an
  M3E-idiomatic collapse (M3E prefers collapsing/large top bars over tucks)?
- Platform-view analog: Android hybrid composition artifacts under M3E
  surfaces — does any liquid-glass-law composition rule transfer?
- FAB menu + expressive shapes under the gallery's Android headroom shim
  (`showcase_gallery_chrome_widget.dart` FAB SizedBox note).

## Sources

m3e_collection package docs; Material 3 Expressive guidance (m3.material.io);
kit sources: `arxa_kit_native_app_bar.dart` (M3E tier),
`arxa_kit_native_tab_bar` `_m3e`, `M3ETheme`;
docs/liquid-glass-allowlist.md (the sibling law whose structure this
follows).
