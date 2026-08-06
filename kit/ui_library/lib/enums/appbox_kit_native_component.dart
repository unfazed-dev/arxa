/// Native-chrome components the kit exposes — registry mirroring
/// `core/NATIVE_COMPONENTS.md`. Each delegates its native tier
/// to `cupertino_native_better` (Liquid Glass on iOS/macOS 26+) and/or
/// `m3e_collection` (Material 3 Expressive on Android); both self-gate their
/// tiers and self-register their platform views, so the kit owns no
/// platform-view `viewType`. Off the native tier each falls back to
/// Material/Cupertino. See NATIVE_COMPONENTS.md for the per-component tier map.
///
/// Note: a documentation mirror — currently has no programmatic consumer (no
/// feature-flag/analytics hook reads it). Kept in parity with the matrix so the
/// registry stays honest; delete only if the matrix becomes the sole SSOT.
enum AppBoxKitNativeComponent {
  // Bars / chrome (shipped first).
  tabBar,
  button,
  segmentedControl,
  // Controls.
  switchControl,
  slider,
  rangeSlider,
  iconButton,
  // Actions.
  fab,
  fabMenu,
  popupMenu,
  splitButton,
  // Feedback.
  loadingIndicator,
  progress,
  toast,
  // Bars.
  searchBar,
  appBar,
  toolbar,
  navigationRail,
  // Surfaces.
  glassCard,
  sheet,
}
