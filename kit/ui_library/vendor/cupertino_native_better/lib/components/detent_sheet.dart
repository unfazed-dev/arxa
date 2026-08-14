import 'package:flutter/cupertino.dart';

import 'bottom_sheet.dart' show CNSheetGeometryProbe;

/// The `UISheetPresentationController` detent model, recreated in Flutter.
///
/// This is the presentation UIKit gives a share-sheet-style modal: the sheet
/// rises to a **medium** stop (half the screen), shows a grabber, and can be
/// dragged up to **large** (full height minus the standard top gap) or down to
/// dismiss. The page behind stays put at medium and recedes — scale-back,
/// corner rounding, slide — only as the sheet travels medium → large, exactly
/// UIKit's behaviour where the parent stack recedes at the `.large` detent
/// only.
///
/// `CupertinoSheetRoute` cannot express this: it is a full-height cover sheet
/// with no detent stops, and it recedes the parent unconditionally on push.
/// This route instead owns its height as a draggable fraction of the screen
/// and leaves the presenting page full-size and static — matching native
/// detent sheets, which do not transform the page below. Detent progress
/// drives only the barrier dim, painted by the route itself so it tracks the
/// drag frame-for-frame instead of the route push.
///
/// Framework-derived constants, kept bit-identical so the two presentations
/// are visually interchangeable where they overlap:
///
/// - large top gap `0.08` (`cupertino/sheet.dart` `_kTopGapRatio`),
/// - fling threshold `2.0` screen-heights/sec (`_kMinFlingVelocity`),
/// - top-corner radius 12 (`cupertino/sheet.dart:335`),
/// - push/pop duration 500 ms, `linearToEaseOut`/`easeInToLinear` curves.
enum CNSheetDetent {
  /// Half the screen height — UIKit's `.medium()`.
  medium(0.5),

  /// Full height minus the framework's 8% top gap — UIKit's `.large()`.
  large(0.92);

  const CNSheetDetent(this.fraction);

  /// Sheet height as a fraction of screen height at this detent.
  final double fraction;
}

/// Framework `_kMinFlingVelocity` — screen heights per second.
const double _kMinFlingVelocity = 2.0;

/// Framework sheet top-corner radius (`cupertino/sheet.dart:335`).
const double _kCornerRadius = 12.0;

const Duration _kRouteDuration = Duration(milliseconds: 500);

/// Detent-to-detent snap duration. Shorter than the route transition: it
/// covers at most the medium→large span, not the full screen.
const Duration _kSnapDuration = Duration(milliseconds: 350);

/// Shows [builder] in a [CNDetentSheetRoute] on the root navigator.
///
/// The sheet opens at the first entry of [detents] (default: medium) and is
/// draggable between all of them. Returns the value passed to
/// `Navigator.pop`, like every other sheet entry point in this package.
Future<T?> showCNDetentSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  List<CNSheetDetent> detents = const <CNSheetDetent>[
    CNSheetDetent.medium,
    CNSheetDetent.large,
  ],
  bool showDragHandle = true,
  bool enableDrag = true,
  Color? barrierColor,
  bool barrierDismissible = true,
  bool injectGeometryProbe = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    CNDetentSheetRoute<T>(
      builder: builder,
      detents: detents,
      showDragHandle: showDragHandle,
      enableDrag: enableDrag,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      injectGeometryProbe: injectGeometryProbe,
      barrierLabel: CupertinoLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// See [showCNDetentSheet].
class CNDetentSheetRoute<T> extends PopupRoute<T> {
  /// Creates a detent sheet route; see [showCNDetentSheet] for the semantics
  /// of each argument.
  CNDetentSheetRoute({
    required this.builder,
    required this.detents,
    required this.showDragHandle,
    required this.enableDrag,
    required Color? barrierColor,
    required bool barrierDismissible,
    required this.injectGeometryProbe,
    required String barrierLabel,
  })  : assert(detents.isNotEmpty),
        _barrierColor = barrierColor,
        _barrierDismissible = barrierDismissible,
        _barrierLabel = barrierLabel;

  /// Builds the sheet's content, below the grabber.
  final WidgetBuilder builder;

  /// Reachable stops, any order; the sheet opens at the first entry.
  final List<CNSheetDetent> detents;

  /// Draws the 36×5 grabber above the content.
  final bool showDragHandle;

  /// Governs drag-to-dismiss below the lowest detent. Dragging *between*
  /// detents is always available — UIKit separates these too
  /// (`isModalInPresentation` blocks dismissal, not detent changes).
  final bool enableDrag;

  /// Wraps the sized sheet box in a [CNSheetGeometryProbe] (see
  /// `CNBottomSheet.showCupertino` for when to opt out).
  final bool injectGeometryProbe;

  final Color? _barrierColor;
  final bool _barrierDismissible;
  final String _barrierLabel;

  /// Detent progress 0 → 1 (lowest → highest detent), consumed by the page
  /// below as its recede progress. A [ProxyAnimation] so the barrier/below
  /// route can hold a reference before the controller exists — the parent
  /// defaults to [kAlwaysDismissedAnimation].
  final ProxyAnimation recedeProgress = ProxyAnimation();
  AnimationController? _recede;

  double get _lowestFraction =>
      detents.map((CNSheetDetent d) => d.fraction).reduce(
            (double a, double b) => a < b ? a : b,
          );
  double get _highestFraction =>
      detents.map((CNSheetDetent d) => d.fraction).reduce(
            (double a, double b) => a > b ? a : b,
          );

  /// Lazily created here rather than in `install()`: `navigator` (the vsync)
  /// is guaranteed by the time the page first builds.
  AnimationController _ensureRecede() {
    final AnimationController? existing = _recede;
    if (existing != null) return existing;
    final AnimationController created = AnimationController(
      vsync: navigator!,
      duration: _kSnapDuration,
    );
    _recede = created;
    recedeProgress.parent = created;
    return created;
  }

  /// Always null: the framework's [ModalBarrier] fades with the *push*
  /// animation, which would dim the page below even while the sheet rests at
  /// its lowest detent. UIKit only dims past the largest undimmed detent, so
  /// the dim is painted in [buildTransitions] driven by [recedeProgress]
  /// instead. The colorless barrier the framework still inserts keeps
  /// tap-to-dismiss and the [barrierLabel] semantics.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String get barrierLabel => _barrierLabel;

  @override
  Duration get transitionDuration => _kRouteDuration;

  @override
  Duration get reverseTransitionDuration => _kRouteDuration;

  // Deliberately NO delegatedTransition: UIKit detent sheets leave the
  // presenting page full-size and static (verified frame-by-frame against a
  // native recording). Routing [recedeProgress] through
  // CupertinoSheetTransition.delegateTransition re-snapshotted the page below
  // on every drag frame — with frosted BackdropFilter content the snapshot
  // lags, so background widgets blanked out and reappeared late. The recede
  // signal now drives only the detent-tracked dim in [buildTransitions].

  @override
  bool didPop(T? result) {
    // Un-recede in step with the sheet's exit so the page below is full-size
    // when the barrier finishes fading. Without this, popping from large
    // leaves the parent frozen at 92% behind a dismissed route.
    _recede?.animateTo(0.0, curve: Curves.easeInToLinear);
    return super.didPop(result);
  }

  @override
  void dispose() {
    _recede?.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _CNDetentSheet<T>(route: this);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Color? dimColor = _barrierColor;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Detent-tracked dim: opacity follows recede progress (0 at the
        // lowest detent → full at the highest), scaled by the route animation
        // so it also fades during push/pop. Ignores pointers so taps reach
        // the framework's colorless dismiss barrier underneath the page.
        if (dimColor != null)
          IgnorePointer(
            key: const Key('cn_detent_sheet_dim'),
            child: AnimatedBuilder(
              animation: Listenable.merge(
                <Listenable>[animation, recedeProgress],
              ),
              builder: (BuildContext context, Widget? _) {
                final Color resolved =
                    CupertinoDynamicColor.resolve(dimColor, context);
                final double t =
                    (animation.value * recedeProgress.value).clamp(0.0, 1.0);
                return ColoredBox(
                  color: resolved.withValues(alpha: resolved.a * t),
                );
              },
            ),
          ),
        // Slide is a fraction of the *child's* size, so a sheet popped from
        // any detent height travels exactly its own height — no dead time.
        SlideTransition(
          position: animation.drive(
            Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).chain(
              CurveTween(
                curve: navigator!.userGestureInProgress
                    ? Curves.linear
                    : Curves.linearToEaseOut,
              ),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _CNDetentSheet<T> extends StatefulWidget {
  const _CNDetentSheet({required this.route});

  final CNDetentSheetRoute<T> route;

  @override
  State<_CNDetentSheet<T>> createState() => _CNDetentSheetState<T>();
}

class _CNDetentSheetState<T> extends State<_CNDetentSheet<T>>
    with SingleTickerProviderStateMixin {
  CNDetentSheetRoute<T> get route => widget.route;

  /// Current sheet height as a fraction of screen height. Set directly during
  /// a drag; animated between detents on release.
  late final AnimationController _fraction;

  @override
  void initState() {
    super.initState();
    _fraction = AnimationController(
      vsync: this,
      value: route.detents.first.fraction,
      duration: _kSnapDuration,
    )..addListener(_publishRecede);
    // First publish, so the parent recedes correctly even when the sheet
    // *opens* at large ([detents] starting with [CNSheetDetent.large]).
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishRecede());
  }

  void _publishRecede() {
    final double lowest = route._lowestFraction;
    final double highest = route._highestFraction;
    final double span = highest - lowest;
    // Tracked, not animated: _fraction itself is what animates or follows the
    // finger, so recede stays glued to the sheet edge frame-for-frame.
    route._ensureRecede().value =
        span <= 0 ? 0 : ((_fraction.value - lowest) / span).clamp(0.0, 1.0);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final double screenHeight = MediaQuery.sizeOf(context).height;
    _fraction.stop();
    // Below the lowest detent the sheet follows the finger only when it may
    // dismiss; otherwise it pins there, like isModalInPresentation.
    final double floor = route.enableDrag ? 0.0 : route._lowestFraction;
    _fraction.value = (_fraction.value - details.delta.dy / screenHeight)
        .clamp(floor, route._highestFraction);
  }

  void _onDragEnd(DragEndDetails details) {
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double vy = details.velocity.pixelsPerSecond.dy / screenHeight;
    final double at = _fraction.value;

    double? target;
    if (vy.abs() >= _kMinFlingVelocity) {
      if (vy < 0) {
        // Fling up → nearest detent above; stay at the top if already there.
        target = route.detents
            .map((CNSheetDetent d) => d.fraction)
            .where((double f) => f > at)
            .fold<double?>(null, (double? m, double f) =>
                m == null || f < m ? f : m) ??
            route._highestFraction;
      } else {
        // Fling down → nearest detent below, or dismiss past the lowest.
        target = route.detents
            .map((CNSheetDetent d) => d.fraction)
            .where((double f) => f < at)
            .fold<double?>(null, (double? m, double f) =>
                m == null || f > m ? f : m);
        if (target == null) {
          if (route.enableDrag) {
            Navigator.of(context).pop();
            return;
          }
          target = route._lowestFraction;
        }
      }
    } else {
      // No fling: snap to the nearest detent; below halfway under the lowest
      // detent counts as a dismissal.
      target = route.detents
          .map((CNSheetDetent d) => d.fraction)
          .reduce((double a, double b) =>
              (a - at).abs() <= (b - at).abs() ? a : b);
      if (route.enableDrag && at < route._lowestFraction / 2) {
        Navigator.of(context).pop();
        return;
      }
    }

    _fraction.animateTo(target, curve: Curves.linearToEaseOut);
  }

  @override
  void dispose() {
    _fraction.removeListener(_publishRecede);
    _fraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = ClipRSuperellipse(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(_kCornerRadius),
      ),
      child: Column(
        children: <Widget>[
          if (route.showDragHandle) const _CNDetentGrabber(),
          Expanded(child: Builder(builder: route.builder)),
        ],
      ),
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints constraints) {
          final double screenHeight = MediaQuery.sizeOf(ctx).height;
          final Widget dragged = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _fraction,
              child: content,
              builder: (_, Widget? child) {
                return SizedBox(
                  height: (_fraction.value * screenHeight)
                      .clamp(0.0, constraints.maxHeight),
                  // Load-bearing: Align passes loose constraints, and a
                  // height-only SizedBox would collapse to intrinsic width.
                  width: double.infinity,
                  child: child,
                );
              },
            ),
          );
          if (!route.injectGeometryProbe) return dragged;
          // Coverage is evaluated against the LARGEST detent, fixed for the
          // sheet's whole lifetime — NOT the live dragged rect. Hiding a
          // native Liquid Glass view is instant, but every re-show replays
          // Apple's ~300ms materialize animation (iOS 26), so live-rect
          // toggling makes background widgets pop in mid-drag. A stable
          // cover rect means gates settle once at open and release once as
          // the sheet slides out. The probe wraps an empty spacer so the
          // opaque GestureDetector above keeps the *visible* sheet's hit
          // area and taps above the sheet still reach the barrier.
          final double coverHeight = (route._highestFraction * screenHeight)
              .clamp(0.0, constraints.maxHeight);
          return Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              ExcludeSemantics(
                child: IgnorePointer(
                  child: CNSheetGeometryProbe(
                    child: SizedBox(
                      height: coverHeight,
                      width: double.infinity,
                    ),
                  ),
                ),
              ),
              dragged,
            ],
          );
        },
      ),
    );
  }
}

/// The framework's 36×5 grabber geometry (`cupertino/sheet.dart:704-708`),
/// spacing matched to the kit's stand-in so tests can treat them alike.
class _CNDetentGrabber extends StatelessWidget {
  const _CNDetentGrabber();

  static const Key grabberKey = Key('cn_detent_sheet_grabber');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 10),
      child: SizedBox(
        key: grabberKey,
        width: 36,
        height: 5,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.tertiaryLabel,
              context,
            ),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}
