import 'package:flutter/material.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_motion/arxa_kit_motion.dart';

import 'arxa_kit_frosted_surface.dart';

/// The drawer skins the kit ships. The enum exists so apps pick a drawer
/// *kind* at the call site and the kit can add variants (the video sweep
/// found one; more will come) without a breaking signature change.
enum ArxaKitDrawerVariant {
  /// The video idiom (ADR 0011 item 4): a slide-over panel at ~85% of the
  /// screen width — the host page peeks at the trailing edge — with one
  /// large rounded corner on the trailing edge and a
  /// [ArxaKitFrostedSurface] skin (Flutter-drawn frosted glass, the ADR 0010
  /// content layer; a drawer slides and clips, so platform-view glass is
  /// off the table by the tier split).
  glassPeek,

  /// The stock themed `Drawer` look (M3 surface container, default 304dp
  /// width, 16dp trailing radius) — kept as a `ArxaKitDrawer` so hosts swap
  /// variants without changing call sites.
  plain,
}

/// The kit's slide-over drawer. Pure Flutter on every tier — there is **no**
/// native (Liquid-Glass / M3-Expressive) drawer surface on either platform,
/// so this widget is named `ArxaKitDrawer`, **not** `ArxaKitNativeDrawer` (the
/// `no_invented_native_widgets` allowlist).
///
/// **Composition, not re-implementation:** `ArxaKitDrawer` builds the stock
/// `Drawer` widget, so it drops into `Scaffold.drawer` / `Scaffold.endDrawer`
/// and the Scaffold's `DrawerController` supplies the machinery — edge-swipe
/// open, drag-to-close with 1:1 finger scrub, fling settle, scrim, and
/// drawer semantics — for free. The variant drives only what stock leaves
/// open: [Drawer.width], [Drawer.shape], and the skin.
///
/// Menu content composes per the kit's list idiom — a profile header, then
/// `ArxaKitListSection`s of glyph-leading `ArxaKitListTile` menu rows:
///
/// ```dart
/// Scaffold(
///   drawer: ArxaKitDrawer(
///     child: ListView(
///       children: [
///         const _ProfileHeader(),
///         ArxaKitListSection(
///           showDividers: false,
///           children: [
///             ArxaKitListTile(glyph: ArxaKitGlyphs.home, title: 'Home', onTap: () {}),
///             ArxaKitListTile(glyph: ArxaKitGlyphs.settings, title: 'Settings',
///                 onTap: () {}),
///           ],
///         ),
///       ],
///     ),
///   ),
/// )
/// ```
///
/// **Motion — stock first, driver seam when stock falls short.** The stock
/// path is the default and covers the video idiom: the drag itself scrubs
/// the panel 1:1 (that IS `DrawerController._handleDragUpdate`) and release
/// flings home. What stock does not expose is (a) a spring-curve settle and
/// (b) the open-progress as an animation, so content choreography — menu
/// rows waking in a stagger as the panel travels, parallax against the host
/// page — has nothing to ride. For that, drive your own
/// `ArxaKitGestureDriver` (with `ArxaKitSprings.snappy`, the drawer-settle preset)
/// from your gesture layer and pass it as [motionDriver]; the drawer's
/// content is wrapped in a `ArxaKitMotionScope` and `ArxaKitWake`-marked rows scrub
/// with your driver:
///
/// ```dart
/// final driver = ArxaKitGestureDriver(vsync: this); // settleSpring: snappy
/// ArxaKitDrawer(
///   motionDriver: driver,
///   child: ListView(children: menuRows.wakeAll()),
/// );
/// // your choreography: driver.scrubBy(dx / extent) on drag update,
/// // driver.settle(velocity: vx / extent) on release.
/// ```
///
/// Reach for the driver path only when you own the open/close choreography;
/// inside a plain `Scaffold.drawer` the stock gestures and a hand-driven
/// driver would fight. See `arxa_kit/motion/README.md` §5.
///
/// kimitail: no width cap on the 85% fraction — the idiom is phone-first;
/// add `max(width, cap)` if a tablet shell ever needs one.
class ArxaKitDrawer extends StatelessWidget {
  const ArxaKitDrawer({
    super.key,
    required this.child,
    this.variant = ArxaKitDrawerVariant.glassPeek,
    this.width,
    this.cornerRadius = 28,
    this.motionDriver,
  });

  /// The drawer content — typically a scroll view of a profile header,
  /// `ArxaKitListSection` menu groups, and a pinned footer. The app owns the
  /// content; the drawer owns the panel.
  final Widget child;

  /// Which drawer skin to build. Defaults to [ArxaKitDrawerVariant.glassPeek],
  /// the video idiom.
  final ArxaKitDrawerVariant variant;

  /// Panel width in dp. `null` (default) = the variant's width: 85% of the
  /// screen width for [ArxaKitDrawerVariant.glassPeek], the stock themed width
  /// (304dp, or the host's `DrawerTheme`) for [ArxaKitDrawerVariant.plain].
  final double? width;

  /// The trailing-edge corner radius for [ArxaKitDrawerVariant.glassPeek].
  /// Defaults to 28 (the kit's large sheet radius). Ignored by
  /// [ArxaKitDrawerVariant.plain], which takes the themed shape.
  final double cornerRadius;

  /// Optional explicit motion driver for the drawer's *content*: when set,
  /// [child] is wrapped in a `ArxaKitMotionScope(driver: …)` so `ArxaKitWake`-marked
  /// rows choreograph against it. Intended for hosts running custom open /
  /// close choreography through a `ArxaKitGestureDriver` — see the class doc.
  /// `null` (default) = no scope; stock `Scaffold` drawer motion only.
  final Animation<double>? motionDriver;

  /// The [ArxaKitDrawerVariant.glassPeek] panel width as a fraction of the
  /// screen width — the video's peek geometry.
  static const double peekWidthFraction = 0.85;

  @override
  Widget build(BuildContext context) {
    final content = motionDriver != null
        ? ArxaKitMotionScope(driver: motionDriver, child: child)
        : child;

    return switch (variant) {
      ArxaKitDrawerVariant.plain => Drawer(width: width, child: content),
      ArxaKitDrawerVariant.glassPeek => _buildGlassPeek(context, content),
    };
  }

  Widget _buildGlassPeek(BuildContext context, Widget content) {
    // The rounded corner lives on the *trailing* edge — the edge the host
    // page peeks past. End drawers mirror it, resolved the same way stock
    // `Drawer` picks `shape` vs `endShape` (public API since the M3 drawer).
    final isEnd =
        DrawerController.maybeOf(context)?.alignment == DrawerAlignment.end;
    final radius = BorderRadiusDirectional.horizontal(
      start: isEnd ? Radius.circular(cornerRadius) : Radius.zero,
      end: isEnd ? Radius.zero : Radius.circular(cornerRadius),
    ).resolve(Directionality.of(context));

    // iOS 26: the host page behind this panel hosts UiKitViews (native tab
    // bar, glass controls) and a BackdropFilter cannot sample them
    // (flutter#175048) — take the vibrant-fill branch, the same recipe as the
    // sheet/dialog opaqueGlass paths. Below the tier there are no platform
    // views behind the panel and the blur IS the frosted material (ADR 0010).
    final glassTier = ArxaKitPlatform.supportsLiquidGlass;
    return Drawer(
      width: width ?? MediaQuery.widthOf(context) * peekWidthFraction,
      // Transparent, elevation-less Material: the shape clip owns the
      // trailing rounding (hardEdge), the frosted skin below owns the look.
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.hardEdge,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // borderRadius 0: the surface must NOT round its own corners — the
      // panel's leading edge sits flush against the screen edge, and
      // self-rounding would leave scrim-colored notches there. The Drawer's
      // shape clip cuts the trailing corner (rim highlight and all).
      child: ArxaKitFrostedSurface(
        borderRadius: 0,
        platformViewSafe: glassTier,
        tint: glassTier
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerLowest
                .withValues(alpha: 1.0)
            : null,
        child: content,
      ),
    );
  }
}
