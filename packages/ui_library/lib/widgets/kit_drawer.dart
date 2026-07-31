import 'package:flutter/material.dart';

import 'package:appbox_kit_motion/appbox_kit_motion.dart';

import 'kit_frosted_surface.dart';

/// The drawer skins the kit ships. The enum exists so apps pick a drawer
/// *kind* at the call site and the kit can add variants (the video sweep
/// found one; more will come) without a breaking signature change.
enum KitDrawerVariant {
  /// The video idiom (ADR 0011 item 4): a slide-over panel at ~85% of the
  /// screen width — the host page peeks at the trailing edge — with one
  /// large rounded corner on the trailing edge and a
  /// [KitFrostedSurface] skin (Flutter-drawn frosted glass, the ADR 0010
  /// content layer; a drawer slides and clips, so platform-view glass is
  /// off the table by the tier split).
  glassPeek,

  /// The stock themed `Drawer` look (M3 surface container, default 304dp
  /// width, 16dp trailing radius) — kept as a `KitDrawer` so hosts swap
  /// variants without changing call sites.
  plain,
}

/// The kit's slide-over drawer. Pure Flutter on every tier — there is **no**
/// native (Liquid-Glass / M3-Expressive) drawer surface on either platform,
/// so this widget is named `KitDrawer`, **not** `KitNativeDrawer` (the
/// `no_invented_native_widgets` allowlist).
///
/// **Composition, not re-implementation:** `KitDrawer` builds the stock
/// `Drawer` widget, so it drops into `Scaffold.drawer` / `Scaffold.endDrawer`
/// and the Scaffold's `DrawerController` supplies the machinery — edge-swipe
/// open, drag-to-close with 1:1 finger scrub, fling settle, scrim, and
/// drawer semantics — for free. The variant drives only what stock leaves
/// open: [Drawer.width], [Drawer.shape], and the skin.
///
/// Menu content composes per the kit's list idiom — a profile header, then
/// `KitListSection`s of glyph-leading `KitListTile` menu rows:
///
/// ```dart
/// Scaffold(
///   drawer: KitDrawer(
///     child: ListView(
///       children: [
///         const _ProfileHeader(),
///         KitListSection(
///           showDividers: false,
///           children: [
///             KitListTile(glyph: KitGlyphs.home, title: 'Home', onTap: () {}),
///             KitListTile(glyph: KitGlyphs.settings, title: 'Settings',
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
/// `KitGestureDriver` (with `KitSprings.snappy`, the drawer-settle preset)
/// from your gesture layer and pass it as [motionDriver]; the drawer's
/// content is wrapped in a `KitMotionScope` and `KitWake`-marked rows scrub
/// with your driver:
///
/// ```dart
/// final driver = KitGestureDriver(vsync: this); // settleSpring: snappy
/// KitDrawer(
///   motionDriver: driver,
///   child: ListView(children: menuRows.wakeAll()),
/// );
/// // your choreography: driver.scrubBy(dx / extent) on drag update,
/// // driver.settle(velocity: vx / extent) on release.
/// ```
///
/// Reach for the driver path only when you own the open/close choreography;
/// inside a plain `Scaffold.drawer` the stock gestures and a hand-driven
/// driver would fight. See `stacked_kit/motion/README.md` §5.
///
/// kimitail: no width cap on the 85% fraction — the idiom is phone-first;
/// add `max(width, cap)` if a tablet shell ever needs one.
class KitDrawer extends StatelessWidget {
  const KitDrawer({
    super.key,
    required this.child,
    this.variant = KitDrawerVariant.glassPeek,
    this.width,
    this.cornerRadius = 28,
    this.motionDriver,
  });

  /// The drawer content — typically a scroll view of a profile header,
  /// `KitListSection` menu groups, and a pinned footer. The app owns the
  /// content; the drawer owns the panel.
  final Widget child;

  /// Which drawer skin to build. Defaults to [KitDrawerVariant.glassPeek],
  /// the video idiom.
  final KitDrawerVariant variant;

  /// Panel width in dp. `null` (default) = the variant's width: 85% of the
  /// screen width for [KitDrawerVariant.glassPeek], the stock themed width
  /// (304dp, or the host's `DrawerTheme`) for [KitDrawerVariant.plain].
  final double? width;

  /// The trailing-edge corner radius for [KitDrawerVariant.glassPeek].
  /// Defaults to 28 (the kit's large sheet radius). Ignored by
  /// [KitDrawerVariant.plain], which takes the themed shape.
  final double cornerRadius;

  /// Optional explicit motion driver for the drawer's *content*: when set,
  /// [child] is wrapped in a `KitMotionScope(driver: …)` so `KitWake`-marked
  /// rows choreograph against it. Intended for hosts running custom open /
  /// close choreography through a `KitGestureDriver` — see the class doc.
  /// `null` (default) = no scope; stock `Scaffold` drawer motion only.
  final Animation<double>? motionDriver;

  /// The [KitDrawerVariant.glassPeek] panel width as a fraction of the
  /// screen width — the video's peek geometry.
  static const double peekWidthFraction = 0.85;

  @override
  Widget build(BuildContext context) {
    final content = motionDriver != null
        ? KitMotionScope(driver: motionDriver, child: child)
        : child;

    return switch (variant) {
      KitDrawerVariant.plain => Drawer(width: width, child: content),
      KitDrawerVariant.glassPeek => _buildGlassPeek(context, content),
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
      child: KitFrostedSurface(borderRadius: 0, child: content),
    );
  }
}
