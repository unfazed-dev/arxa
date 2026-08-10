# Icon Pipeline Consolidation

Follow-on to `lucide-only-icon-unification.md`. The pixelation bug is fixed and
verified (2026-08-10), but the fix had to be applied per-view because the icon
pipeline is duplicated at three layers. This plan collapses each layer to a
single owner so the next icon bug is fixed in one place.

## Current scatter (inventoried 2026-08-10)

**Dart vendor** (`kit/ui_library/vendor/cupertino_native_better/lib/`):
priority chain `imageAsset > customIcon > icon` + rasterize/FutureBuilder
scaffold copy-pasted across:

- `components/button.dart`
- `components/popup_menu_button.dart`
- `components/tab_bar.dart`
- `components/icon.dart`
- `components/split_button.dart` *(premise corrected in Stage 2: forwards to
  glass_button_group only, no pipeline of its own)*
- `components/glass_button_group.dart`

all calling `utils/icon_renderer.dart` with slightly different args.

**Swift** (`ios/.../Sources/cupertino_native_better/`): the 3-branch decode
(asset path → bytes → SF symbol) is reimplemented in each platform view —
`CupertinoButtonPlatformView` (twice: create ~L114 and update ~L422),
`CupertinoPopupMenuButtonPlatformView`, `CupertinoTabBarPlatformView`,
`CupertinoIconPlatformView`, `GlassButtonGroupView` — and again in the macOS
NSView twins. The pixelation bug lived precisely in this duplication: the
update path used `UIScreen.main.scale` while the create path honored
`iconScale`.

**Wire format**: param keys differ per component
(`buttonCustomIconBytes` vs `customIconBytes` vs menu-item variants), which
blocks Swift from sharing one decoder.

## Target: one name per layer

1. **Dart** — `IconSource` resolver: single async function owning the
   priority chain, returning a sealed type
   `asset(path, scale) | bytes(png, scale) | sfSymbol(name)`.
   Components await it; no per-component chains.
2. **Wire** — one key set for every view type:
   `iconSource`, `iconBytes`, `iconScale`, `iconSize`.
3. **Swift/AppKit** — `ImageUtils.resolveIcon(args:) -> UIImage?/NSImage?`
   used by all platform views on BOTH create and update paths.
   `SVGImageLoader` + `ImageCacheManager` become internals of it.

## Stages (each independently shippable, showcase-verified)

- **Stage 1 — Swift resolver (pure dedup, no wire change).** Extract the
  existing branch logic into `resolveIcon`, route all five views (iOS + macOS)
  through it, delete the inline copies. Regression surface: every icon
  surface; verify FAB, tab bar, home icon buttons, appbar search/menu at 1x/2x/3x.
- **Stage 2 — Dart `IconSource` resolver.** Same dedup on the Dart side;
  `icon_renderer.dart` becomes its only rasterization backend.
  **Done (2026-08-10).** `resolveIconSource` + sealed
  `IconSource` (`IconSourceAsset | IconSourceBytes | IconSourceSymbol`) live in
  `lib/utils/icon_renderer.dart`; the five components (button, icon, tab_bar,
  popup_menu_button, glass_button_group) route every asset-resolve /
  format-detect / glyph-rasterize through it. Wire keys untouched. The one
  normalization: format strings are lowercased at the resolver (Dart now
  guarantees the lowercase wire contract Stage 1 assumed on the Swift side).
  Dart-side divergences recorded below.
- **Stage 3 — wire-format rename.** Breaks both sides at once; do last, in a
  single commit, with a grep proving zero old-key references remain.

## Divergences found

Recorded during Stage 1 (2026-08-10). Each of these is a place where two call
sites disagree. **None were normalized** — Stage 1 preserved every one verbatim
and made it explicit at the call site. They are listed here so a later stage can
decide them deliberately.

### The premise correction

The brief for Stage 1 stated that the Button view's create/update scale split
*was* the pixelation bug and had been fixed. That is not what happened.
`git show 7399510` touches exactly two files — `Utils/SVGImageLoader.swift` and
`lib/utils/icon_renderer.dart`. It never touched any platform view. The fix
lives inside `SVGImageLoader.performSVGRendering`, which now rasterizes at
`size * UIScreen.main.scale` and re-wraps the bitmap at screen scale.

Two consequences:

1. **The Button create/update scale split still exists at HEAD.** The create
   path honours `iconScale`; `setButtonIcon` uses `UIScreen.main.scale`.
   Preserved, with a comment at the call site.
2. **`scale:` is inert on the SVG branch.** `SVGImageLoader.loadSVG` takes no
   scale parameter and always reads `UIScreen.main.scale` internally. So every
   `iconScale` vs `UIScreen.main.scale` disagreement below only affects *raster*
   bytes (`UIImage(data:scale:)`) and the tint/rescale passes — never SVG. This
   is why the splits were invisible in testing: lucide icons are SVG.

### Scale sources

| Site | Asset branch | Data branch | Template bytes |
| --- | --- | --- | --- |
| Button (create) | `iconScale` | `iconScale` | `iconScale` |
| Button (`setButtonIcon`) | `UIScreen.main.scale` | `UIScreen.main.scale` | `UIScreen.main.scale` |
| Icon | `UIScreen.main.scale` (default) | `iconScale` | `iconScale` |
| TabBar (×3) | `UIScreen.main.scale` (default) | `iconScale` | `iconScale` |
| PopupMenu | `iconScale` | `iconScale` | `iconScale` |
| GlassButtonGroup (×3) | `UIScreen.main.scale` | `UIScreen.main.scale` | n/a |

Icon and TabBar reached `UIScreen.main.scale` by *omitting* the argument and
inheriting the old default. `ImageUtils.iconFrom*` now requires `scale`, so
these are stated explicitly rather than inherited.

### Priority order

Two orders are in use, and Stage 2 must pick one deliberately:

- **asset-first**: Button, PopupMenu, GlassButtonGroup
- **data-first**: Icon, TabBar

GlassButtonGroup additionally has *two* data sources, tried in order:
`imageBytes` (with format) then `iconBytes` (forced `"png"`).

### Smaller disagreements

- **PopupMenu button icon size.** The untinted asset load defaulted a missing
  `btnIconSize` to 20pt while the tinted load passed `nil` (SVG then falls back
  to 24pt inside `loadFlutterAsset`). Preserved via a conditional; the two
  branches never agreed.
- **Format-string case.** Tinted paths ran `providedFormat` through
  `detectImageFormat`, which lowercases it; untinted paths passed the raw string
  straight to `loadFlutterAsset`/`createImageFromData`, which compares against
  `"svg"` without lowercasing. A caller passing `"SVG"` therefore got the SVG
  decoder when tinting and the raster decoder when not. Unified on the
  lowercasing form (what the tinted path did). This is the one change that
  applies at *every* rewired site, not just the one it was found in:
  `ImageUtils.iconFromAsset`/`iconFromData` always normalize, so TabBar's
  `imageAssetFormats[i]` and GlassButtonGroup's `imageFormat` are now
  lowercased too. Harmless if Dart only ever sends lowercase — worth confirming
  in Stage 2, which owns that end of the wire.
- **ARGB round-trip.** Call sites converted `UIColor → ARGB Int → UIColor`
  before tinting, and silently skipped tinting when `colorToARGB` returned nil
  (colors whose components can't be read). Preserved inside
  `ImageUtils.normalizedTint`; it can be dropped once someone confirms no caller
  depends on the nil case.

### Stage 2 (Dart side, 2026-08-10)

Recorded during Stage 2. Same rule as above: preserved verbatim, made explicit
with a `// Divergence (Stage 2)` comment at each call site.

- **Premise correction: `split_button.dart` has no icon pipeline.** The
  inventory listed it among the six copy-paste sites; it only forwards
  `CNButtonData` (including `customIcon`) to `CNGlassButtonGroup` and never
  rasterizes or resolves anything itself. Five files were rewired, not six.
- **GlassButtonGroup runs parallel payloads, not a priority chain.** It
  computes BOTH `iconBytes` (rasterized `customIcon`) and
  `imageBytes`/`imageFormat`/`assetPath` (imageAsset) and sends both;
  the Swift side picks (`imageBytes` first, then `iconBytes` forced `"png"`,
  see Stage 1 notes). `resolveIconSource` is therefore invoked once per
  payload there instead of once per button.
- **Custom-icon raster sizes differ per component.** Button:
  `config.customIconSize ?? 20.0`; Icon: `widget.size ?? symbol?.size ?? 24.0`;
  GlassButtonGroup face: `icon?.size ?? 20.0`, its menu items: fixed `18.0`;
  PopupMenu and TabBar have their own per-item sizes. All preserved.
- **Async placeholder sizing differs per branch.** `icon.dart`'s asset branch
  sizes its placeholder from `imageAsset.size`, its custom-icon branch from
  `symbol?.size`; `button.dart` uses `minHeight ?? 44.0` in both. The outer
  branch structure was kept at those call sites so placeholders stay identical.
- **Format null-fallback.** Some sites send `format ?? 'png'`
  (tab bar), others omit/send null (button, icon).
  Preserved as `source.format ?? 'png'` at the sites that had it.
  *Premise correction:* the Stage 2 brief said popup_menu_button's old L563
  used `?? 'png'`; ground truth is `?? ''`, and `?? ''` was preserved.
- **PopupMenu divergences (rewire-popup).** Button custom-icon default tint is
  white while per-item icons default `CupertinoColors.label` — preserved. The
  old button-asset `isNotEmpty` pre-guard was dropped (wire values unchanged;
  resolver returns null for empty paths). `_syncPropsToNativeIfNeeded`'s
  per-item path still sends the raw unresolved path with only format
  auto-detected — pre-existing behavior, preserved (same class of divergence
  as the TabBar update path above). Per-item format resolution is hoisted into
  a separate `Future.wait` pass after the context captures, keeping the
  await-free loop invariant, with an `if (!mounted) return;` guard.
- **Custom-icon raster failure never falls through to the symbol branch.**
  Encoded in `resolveIconSource` (returns null), matching every prior call
  site; FutureBuilder placeholders stay up on failure exactly as before.
- **Lowercase format guarantee (the sanctioned change).**
  `IconSourceAsset.format` is `(assetFormat ?? detectImageFormat(...))?.toLowerCase()`.
  Previously a caller-supplied `CNImageAsset.imageFormat` like `"SVG"` went
  over the wire raw; Stage 1's Swift resolver already lowercases on receipt,
  so the wire contract is now enforced at both ends. Audit confirmed all
  format strings on the wire originate in the five rewired files.
- **TabBar update path keeps direct `detectImageFormat` calls (decided).**
  `_syncPropsToNativeIfNeeded` sends the RAW unresolved `assetPath` in
  `imageAssetPaths` (unlike the create path, which sends the pixel-ratio-resolved
  one). Routing it through `resolveIconSource` would either change
  `imageAssetPaths`' wire value or add a discarded async I/O call per sync —
  both unsanctioned. Decision: the two flagged call sites in `tab_bar.dart`
  call `detectImageFormat` directly. No new resolver variant was added because
  `detectImageFormat` is *defined in* `icon_renderer.dart` — it already is the
  backend's format-only entry point, so the single-backend invariant holds.
  The one gap this left — caller-supplied `imageFormat` bypassing the
  resolver's lowercase guarantee on this path — was closed by applying the
  sanctioned `?.toLowerCase()` to the combined
  `imageFormat ?? detectImageFormat(...)` expression at both sites.
  The grep gate for Stage 2 therefore allows exactly these two commented
  `detectImageFormat` occurrences in `tab_bar.dart`; everything else in
  `lib/components/` must be zero.

### macOS

macOS has **no asset-path or SVG icon pipeline at all**. Every macOS view
resolves its icon from `NSImage(systemSymbolName:)`; `CupertinoTabBarNSView` is
the only one that decodes bytes. The macOS `Utils/ImageUtils.swift` therefore
carries only `colorFromARGB` (7 identical copies collapsed) and
`iconFromTemplateBytes` (the one byte-decode site) — mirroring the iOS surface
any further would have invented API with no caller.

`private extension NSImage { func tinted(with:) }` exists in four macOS files.
Three are identical (mask via `.destinationIn`); **`CupertinoButtonNSView`'s
differs** — it guards on `isTemplate`, fills with `.sourceAtop`, and clears
`isTemplate` afterwards. Not merged, because merging would silently change
button tinting. Worth deciding in a later stage.

## Risks

- Vendored fork: upstream merges get harder after Stage 3's rename; acceptable,
  fork already diverged.
- Both OS families must move together in Stage 1 (shared Sources dir).
- Snapshot-style manual verification only; no golden tests exist for native views.
