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
- `components/split_button.dart`
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
- **Stage 3 — wire-format rename.** Breaks both sides at once; do last, in a
  single commit, with a grep proving zero old-key references remain.

## Risks

- Vendored fork: upstream merges get harder after Stage 3's rename; acceptable,
  fork already diverged.
- Both OS families must move together in Stage 1 (shared Sources dir).
- Snapshot-style manual verification only; no golden tests exist for native views.
