import 'dart:async' show Timer;

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNGlassEffect,
        CNGlassShadow,
        CNToast,
        CNToastDuration,
        CNToastPosition,
        LiquidGlassConfig,
        LiquidGlassContainer;
import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart'
    show SnackbarService, StackedService;

import 'package:appbox_kit_core/common/appbox_kit_colors.dart'
    show AppBoxKitColors;
import 'package:appbox_kit_core/appbox_kit_locator.dart' show appBoxKitLocator;
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_snackbar_type.dart'
    show AppBoxKitSnackbarType;
import '../../utils/appbox_kit_native_overlay.dart'
    show appBoxKitWithNativeChromeHidden;
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart'
    show AppBoxKitPlatform;

import '../../widgets/appbox_kit_native_dialog.dart';
import '../../widgets/appbox_kit_native_sheet.dart' show appBoxKitShowSheet;
import 'appbox_kit_ask_surfaces.dart';

/// Severity for [AppBoxKitNotificationService.show]. Drives the M3E-tier snackbar
/// variant (Android / iOS action fallback) and the CNToast style preset (the
/// iOS default tier).
enum AppBoxKitNotificationKind { info, success, error, warning }

/// Screen position for [AppBoxKitNotificationService.show]'s `position` param.
/// The iOS CNToast tier honors all three values. The snackbar tiers honor
/// [center] with a kit-styled floating pill at screen center; [top]/[bottom]
/// render per the registered SnackbarConfig's anchor (bottom) — SnackPosition
/// has no center value, which is why the kit owns the center surface itself.
enum AppBoxKitToastPosition { top, center, bottom }

/// The kit's transient-feedback service. One entry point that picks the right
/// native surface per platform — supersedes `appBoxKitShowNativeToast` and the
/// Material [SnackbarService] coexisting on iOS.
///
/// Routing:
/// - **Android** ([AppBoxKitPlatform.supportsComposeM3E]) → host [SnackbarService]
///   (native Material `ScaffoldMessenger`), wrapped in [appBoxKitWithNativeChromeHidden]
///   so the iOS hybrid-composition z-order fix applies where it matters.
/// - **iOS / else, no action** → [CNToast] (Flutter-drawn capsule on every
///   OS: the vendor's glass tier is disabled — `useGlassEffect: false` on
///   every kind per `docs/liquid-glass-allowlist.md` rule 12; only an
///   invisible `plain` native anchor + CALayer shadow remain on iOS 26+).
///   This is the default — there is no snackbar on iOS unless an action is
///   required.
/// - **iOS / else, with [actionLabel]** → [SnackbarService] fallback, because
///   CNToast is fire-and-forget and cannot host an action button. The action
///   parameter is the ONLY thing that promotes iOS from a toast to a snackbar;
///   without it the two never coexist.
/// - **Snackbar tier + `position: AppBoxKitToastPosition.center`** → a kit-owned
///   floating pill ([_KitCenterToastPill]) at screen center instead of the
///   GetX snackbar. It still hosts the action button that promoted iOS onto
///   this tier.
///
/// Host boot requirement: `setupLocator()` (registers this service) +
/// `setupAppBoxKitSnackbars()` (registers the SnackbarConfig variants the Android +
/// fallback tiers render).
class AppBoxKitNotificationService {
  /// Shows transient native feedback for [message].
  ///
  /// [context] is honored on the iOS-toast tier (CNToast resolves the Overlay
  /// from it). When null, the service falls back to the app's navigator-key
  /// context ([StackedService.navigatorKey]) so context-less callers (AppBoxKitAction
  /// notifications) still render on iOS. If neither is mounted (pre-boot), the
  /// iOS tier debugPrints and no-ops rather than throwing.
  ///
  /// [duration] is honored where the tier accepts a free-form [Duration] (the
  /// snackbar tiers); on the CNToast tier it is snapped to the nearest preset.
  ///
  /// [position] places the toast: the CNToast tier honors all three values;
  /// the snackbar tiers honor [AppBoxKitToastPosition.center] with a kit-styled
  /// floating pill at screen center, and render top/bottom bottom-anchored
  /// (the registered SnackbarConfig's anchor). Defaults to
  /// [AppBoxKitToastPosition.top] to clear the status bar / Dynamic Island.
  ///
  /// [actionLabel] / [onAction] render a snackbar action button on the snackbar
  /// tiers. Passing a non-null [actionLabel] forces iOS onto the snackbar tier.
  ///
  /// [title] and [variant] are snackbar-tier-only overrides (CNToast has no
  /// title or variant concept; it derives its style from [kind]). [variant] may
  /// be a [AppBoxKitSnackbarType] or a host enum variant with a registered config —
  /// when null it defaults to the variant mapped from [kind].
  Future<void> show(
    String message, {
    AppBoxKitNotificationKind kind = AppBoxKitNotificationKind.info,
    Duration? duration,
    BuildContext? context,
    String? title,
    dynamic variant,
    String? actionLabel,
    VoidCallback? onAction,
    AppBoxKitToastPosition position = AppBoxKitToastPosition.top,
  }) {
    if (AppBoxKitPlatform.supportsComposeM3E || actionLabel != null) {
      if (position == AppBoxKitToastPosition.center) {
        return _centerPill(
            message, kind, duration, context, title, actionLabel, onAction);
      }
      // Resolve at call time (not construction) so tests can register a stub
      // SnackbarService before invoking show().
      final snackbar = appBoxKitLocator<SnackbarService>();
      // ADR 0010 second amendment: on the Liquid Glass tier the GetX
      // BackdropFilter scrim is a structural no-op (in-page CN platform views
      // slice the scene; only the dim composites), so the configs register
      // overlayBlur 0 there and the frost comes from a kit-owned native glass
      // scrim entry inserted before the GetX entries. Other tiers keep the
      // sigma-20 GetX path and pass no overlay.
      OverlayState? scrimOverlay;
      if (AppBoxKitPlatform.supportsLiquidGlass) {
        final ctx =
            _overlayContext(context, 'snackbar scrim skipped: "$message"');
        if (ctx != null) {
          scrimOverlay = Overlay.maybeOf(ctx, rootOverlay: true);
        }
      }
      return appBoxKitWithNativeChromeHidden(
        () => snackbar.showCustomSnackBar(
          message: message,
          title: title,
          variant: variant ?? _snackbarVariant(kind),
          duration: duration ?? const Duration(seconds: 3),
          mainButtonTitle: actionLabel,
          onMainButtonTapped: onAction,
        ),
        scrimOverlay: scrimOverlay,
      );
    }
    return _cnToast(message, kind, duration, context, position);
  }

  /// The currently-shown center pill, so a new one replaces it (GetX-style
  /// replace semantics) instead of stacking two capsules at screen center.
  OverlayEntry? _activeCenterPill;

  /// Tells the user something in a modal dialog — kit-rendered
  /// ([appBoxKitShowNativeDialog]) with a single action, so apps never
  /// register a stacked alert variant. Fire-and-forget. This is also the
  /// surface AppBoxKitAction's `dialog` notification type routes through.
  /// Pre-boot no-ops.
  Future<void> alert({
    required String title,
    String? message,
    String actionLabel = 'OK',
    bool barrierDismissible = true,
    BuildContext? context,
  }) async {
    final ctx = _overlayContext(context, 'alert dropped: "$title"');
    if (ctx == null) return;
    await appBoxKitShowNativeDialog<void>(
      context: ctx,
      title: title,
      message: message,
      barrierDismissible: barrierDismissible,
      actions: [
        AppBoxKitNativeDialogAction(
          label: actionLabel,
          role: AppBoxKitDialogActionRole.primary,
        ),
      ],
    );
  }

  /// Asks the user to confirm — kit-rendered native dialog
  /// ([appBoxKitShowNativeDialog]), so apps never register a stacked confirm
  /// variant. Resolves `true` only when the action button is tapped;
  /// cancel / barrier-dismiss / pre-boot resolve `false`.
  Future<bool> confirm({
    required String title,
    String? message,
    String actionLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    BuildContext? context,
  }) async {
    final ctx = _overlayContext(context, 'confirm dropped: "$title"');
    if (ctx == null) return false;
    final result = await appBoxKitShowNativeDialog<bool>(
      context: ctx,
      title: title,
      message: message,
      actions: [
        AppBoxKitNativeDialogAction(label: cancelLabel, value: false),
        AppBoxKitNativeDialogAction(
          label: actionLabel,
          value: true,
          role: destructive
              ? AppBoxKitDialogActionRole.destructive
              : AppBoxKitDialogActionRole.primary,
        ),
      ],
    );
    return result ?? false;
  }

  /// Asks the user for a short text entry — kit-rendered [AppBoxKitPromptDialog]
  /// (frosted panel + CupertinoTextField on iOS, M3 AlertDialog elsewhere), so
  /// apps never register a stacked text-input variant. Resolves the trimmed
  /// entry, or null on cancel / barrier-dismiss / empty entry / pre-boot.
  Future<String?> prompt({
    required String title,
    String? message,
    String? placeholder,
    String? initialValue,
    String actionLabel = 'Save',
    String cancelLabel = 'Cancel',
    BuildContext? context,
  }) {
    final ctx = _overlayContext(context, 'prompt dropped: "$title"');
    if (ctx == null) return Future.value();
    return showDialog<String>(
      context: ctx,
      builder: (_) => AppBoxKitPromptDialog(
        title: title,
        message: message,
        placeholder: placeholder,
        initialValue: initialValue,
        actionLabel: actionLabel,
        cancelLabel: cancelLabel,
      ),
    );
  }

  /// Tells the user something in a modal sheet — kit-rendered
  /// [AppBoxKitNoticeSheetBody] presented through [appBoxKitShowSheet]
  /// (CNBottomSheet glass on iOS, M3 modal sheet on Android), so apps never
  /// register a stacked notice-sheet variant. Fire-and-forget: dismissible by
  /// drag/barrier. Pre-boot no-ops.
  Future<void> notice({
    required String title,
    required String message,
    BuildContext? context,
  }) async {
    final ctx = _overlayContext(context, 'notice dropped: "$title"');
    if (ctx == null) return;
    await appBoxKitShowSheet<void>(
      context: ctx,
      builder: (_) => AppBoxKitNoticeSheetBody(title: title, message: message),
    );
  }

  /// Context for the dialog/sheet tiers: the caller's when mounted, else the
  /// app's navigator-key context (context-less callers). Null pre-boot — the
  /// caller no-ops with a debugPrint instead of throwing, mirroring `_cnToast`.
  BuildContext? _overlayContext(BuildContext? context, String dropMessage) {
    if (context != null && context.mounted) return context;
    final fallback = StackedService.navigatorKey?.currentContext;
    if (fallback != null && fallback.mounted) return fallback;
    debugPrint('AppBoxKitNotificationService: no BuildContext for dialog/sheet '
        'tier; $dropMessage');
    return null;
  }

  /// Snackbar-tier center path: a kit-owned floating pill at screen center.
  /// SnackPosition (stacked_services/GetX) has no center value, so the kit
  /// presents this surface directly on the Overlay. Can host the action
  /// button that promoted iOS onto this tier.
  Future<void> _centerPill(
    String message,
    AppBoxKitNotificationKind kind,
    Duration? duration,
    BuildContext? context,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  ) async {
    // Same de-mix guard as _cnToast: never stack the pill on an open GetX
    // snackbar (an action snackbar's onAction may chain this call).
    final snackbar = appBoxKitLocator<SnackbarService>();
    if (snackbar.isSnackbarOpen) {
      await snackbar.closeSnackbar();
    }
    // Resolved after the await, mirroring _cnToast: the caller's context may
    // have unmounted while the snackbar animated off.
    final ctx = (context != null && context.mounted)
        ? context
        : StackedService.navigatorKey?.currentContext;
    // `rootOverlay: true` — the pill must outrank every surface in the app
    // (mirrors the CNToast tier). The nearest overlay can be a nested
    // navigator's, whose entries paint under the shell's own chrome.
    final overlay = (ctx != null && ctx.mounted)
        ? Overlay.maybeOf(ctx, rootOverlay: true)
        : null;
    if (overlay == null) {
      // Pre-boot: no Overlay to host the pill. No-op; never throw.
      debugPrint(
          'AppBoxKitNotificationService: no Overlay for center pill tier; '
          'message dropped: "$message"');
      return;
    }
    // Not wrapped in appBoxKitWithNativeChromeHidden: the pill paints no blur scrim,
    // so the iOS hybrid-composition z-order bug that helper guards cannot
    // trigger — hiding the native chrome would be pure regression.
    final old = _activeCenterPill;
    _activeCenterPill = null;
    if (old != null && old.mounted) old.remove();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _KitCenterToastPill(
        message: message,
        kind: kind,
        title: title,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration ?? const Duration(seconds: 3),
        onDismissed: () {
          if (_activeCenterPill == entry) _activeCenterPill = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _activeCenterPill = entry;
    overlay.insert(entry);
  }

  Future<void> _cnToast(
    String message,
    AppBoxKitNotificationKind kind,
    Duration? duration,
    BuildContext? context,
    AppBoxKitToastPosition position,
  ) async {
    // An action snackbar's onAction often chains a follow-up toast (e.g. the
    // showcase split button's Confirm → 'Sent'). The two surfaces never
    // coexist on iOS: dismiss the open snackbar first and wait for its exit
    // animation — closeSnackbar()'s future resolves only once the Get overlay
    // entry is removed, i.e. the snackbar is completely off screen.
    final snackbar = appBoxKitLocator<SnackbarService>();
    if (snackbar.isSnackbarOpen) {
      await snackbar.closeSnackbar();
    }
    // Resolved after the await: the caller's context may have unmounted while
    // the snackbar animated off — fall back to the navigator key then.
    final ctx = (context != null && context.mounted)
        ? context
        : StackedService.navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) {
      // Pre-boot: no Overlay to host CNToast. No-op; never throw.
      debugPrint(
          'AppBoxKitNotificationService: no BuildContext for iOS toast tier; '
          'message dropped: "$message"');
      return;
    }
    final pos = _cnPosition(position);
    final preset = _cnDuration(duration);
    // `useGlassEffect: false` on every kind — the Flutter-drawn toast tier.
    //
    // NOT a design downgrade; the glass tier is unshippable as the vendor
    // builds it. `CNToast` wraps its body in a real `LiquidGlassContainer`
    // platform view (vendor toast.dart:503) and then runs it through
    // `ScaleTransition` + `FadeTransition` on both edges (:571-577) — which is
    // precisely the idiom this repo's law forbids over a platform view
    // (ghosting UIViews; see this gate's own citation in
    // appbox_kit_native_chrome_gate.dart). Worse, it is mounted through a bare
    // `OverlayEntry` (:302) with no `.chromeGated()` and no listener on
    // `CNTransitionObserver`/`CNTabBarRouteObserver`, so it is the one native
    // glass surface in the kit that cannot leave the frame for a route slide —
    // it would sit on top of a transition, sharp, exactly the leak the gate
    // exists to prevent. A toast fires most often right after a nav action, so
    // that window is the common case, not a corner.
    //
    // The Flutter tier keeps the fade (safe over Flutter-drawn content) and
    // matches `_centerPill`, this service's other toast surface, which is
    // already Flutter-drawn. Revisit only if the vendor gates the overlay AND
    // stops alpha-animating it.
    // transition-exempt: every CNToast call below passes `useGlassEffect:
    // false`, so the vendor takes its Flutter-drawn branch. That branch DOES
    // mount one platform view — the PLAIN slicer anchor (vendor toast.dart,
    // non-glass branch; same mechanism as the kit input bar and this
    // service's center pill) that keeps the toast's Flutter ops in the
    // topmost overlay layer while native glass scrolls beneath it. `plain`
    // renders nothing (clear fill, Glass.identity), so if it rides over a
    // route slide it shows nothing — there is still nothing visible to gate.
    // If this ever flips back to the glass tier, DELETE this exemption — the
    // toast's bare OverlayEntry cannot be gated from the kit and the leak
    // returns.
    const bool glass = false;
    switch (kind) {
      case AppBoxKitNotificationKind.info:
        CNToast.info(
            context: ctx,
            message: message,
            duration: preset,
            position: pos,
            useGlassEffect: glass);
      case AppBoxKitNotificationKind.warning:
        CNToast.warning(
            context: ctx,
            message: message,
            duration: preset,
            position: pos,
            useGlassEffect: glass);
      case AppBoxKitNotificationKind.success:
        CNToast.success(
            context: ctx,
            message: message,
            duration: preset,
            position: pos,
            useGlassEffect: glass);
      case AppBoxKitNotificationKind.error:
        CNToast.error(
            context: ctx,
            message: message,
            duration: preset,
            position: pos,
            useGlassEffect: glass);
    }
  }

  static AppBoxKitSnackbarType _snackbarVariant(
          AppBoxKitNotificationKind kind) =>
      switch (kind) {
        AppBoxKitNotificationKind.info =>
          AppBoxKitSnackbarType.appBoxKitAutoProcessInfo,
        AppBoxKitNotificationKind.success =>
          AppBoxKitSnackbarType.appBoxKitAutoProcessSuccess,
        AppBoxKitNotificationKind.error =>
          AppBoxKitSnackbarType.appBoxKitAutoProcessError,
        AppBoxKitNotificationKind.warning =>
          AppBoxKitSnackbarType.appBoxKitAutoProcessWarning,
      };

  static CNToastPosition _cnPosition(AppBoxKitToastPosition p) => switch (p) {
        AppBoxKitToastPosition.top => CNToastPosition.top,
        AppBoxKitToastPosition.center => CNToastPosition.center,
        AppBoxKitToastPosition.bottom => CNToastPosition.bottom,
      };

  /// Snaps a free-form [Duration] to CNToast's short/medium/long presets.
  /// `null` → medium (CNToast's own default).
  static CNToastDuration _cnDuration(Duration? d) {
    if (d == null) return CNToastDuration.medium;
    final ms = d.inMilliseconds;
    if (ms <= 2000) return CNToastDuration.short;
    if (ms <= 3500) return CNToastDuration.medium;
    return CNToastDuration.long;
  }
}

/// Kit-styled floating pill presented at screen center when
/// [AppBoxKitNotificationService.show] gets `position: AppBoxKitToastPosition.center` on
/// a snackbar tier. M3-idiomatic floating-snackbar look (capsule, kind-tinted,
/// icon + message + optional action). The overlay layout mirrors the vendored
/// CNToast `_ToastOverlay` fixes: a transparent [Material] supplies a real
/// DefaultTextStyle, and the full-screen box claims hits only on the capsule —
/// no IgnorePointer, so the action button stays tappable and taps outside the
/// pill fall through.
class _KitCenterToastPill extends StatefulWidget {
  const _KitCenterToastPill({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismissed,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppBoxKitNotificationKind kind;

  /// Time fully on screen before the exit animation starts.
  final Duration duration;

  /// Called when the pill's time is up or its action is tapped; the owner
  /// removes the entry.
  final VoidCallback onDismissed;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_KitCenterToastPill> createState() => _KitCenterToastPillState();
}

class _KitCenterToastPillState extends State<_KitCenterToastPill>
    with SingleTickerProviderStateMixin {
  // Matches setupAppBoxKitSnackbars' animationDuration / curves.
  static const _animDuration = Duration(milliseconds: 300);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _exitTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: _animDuration, vsync: this);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    _fade = curved;
    _scale = Tween<double>(begin: 0.9, end: 1).animate(curved);
    _controller.forward();
    // Best-effort exit animation, starting _animDuration before removal.
    _exitTimer = Timer(widget.duration - _animDuration, () {
      if (mounted) _controller.reverse();
    });
    // Authoritative dismissal is Timer-driven, never ticker-future-driven: a
    // muted/paused ticker (TickerMode off, app backgrounded) must not strand
    // the pill on screen. Same philosophy as the vendored CNToast, which
    // hard-removes its entry from a Timer.
    _removeTimer = Timer(widget.duration, () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _removeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Per-kind palette mirrors setupAppBoxKitSnackbars (kit_snackbar_setup.dart) —
    // keep the two in sync.
    final (bg, fg, icon) = switch (widget.kind) {
      AppBoxKitNotificationKind.info => (
          AppBoxKitColors.surface2,
          AppBoxKitColors.muted,
          Icons.info_outline
        ),
      AppBoxKitNotificationKind.success => (
          AppBoxKitColors.good,
          AppBoxKitColors.onAccent,
          Icons.check_circle_outline
        ),
      AppBoxKitNotificationKind.error => (
          AppBoxKitColors.danger,
          Colors.white,
          Icons.error_outline_rounded
        ),
      AppBoxKitNotificationKind.warning => (
          const Color(0xFFFFF7ED),
          AppBoxKitColors.warn,
          Icons.warning_amber_outlined
        ),
    };

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Align(
          // PLAIN native anchor — same mechanism as the CNToast Flutter tier
          // (vendor toast.dart) and the kit input bar: the pill is
          // Flutter-drawn in the root overlay above platform-view-bearing
          // scrollables, and the engine's view slicer (flow/view_slicer.cc)
          // keeps Flutter ops in the topmost overlay layer only while they
          // intersect a platform-view rect — otherwise passing in-scroll
          // native glass renders OVER the pill. This stationary anchor is the
          // scene-last platform view, so the pill's ops always hoist above
          // every earlier platform view.
          //
          // The anchor sits INNERMOST, wrapping exactly the opaque decorated
          // pill (same geometry as the vendor CNToast fallback). `plain` is
          // NOT pixel-free in practice — though the cost is a SLICE, not a
          // fill: LiquidGlassContainerView.swift renders plain as
          // `.fill(Color(tint ?? .clear))` with the glass modifier held at
          // `Glass.identity`, so with no tint it paints nothing at all. What
          // shows is the engine's view slicer splitting Flutter layers at the
          // platform view's UNCLIPPED rect (the same mechanism
          // AppBoxKitGlassWarmup's off-screen translate exists to dodge), so
          // any anchor margin exposed beyond the pill surfaces as a faint
          // hard-edged seam on the glass tier — observed on-device
          // 2026-08-15 when the anchor wrapped the fade/scale + 32px padding.
          // Full occlusion by the pill is the invariant; keep transitions and
          // padding OUTSIDE.
          //
          // The pill also paints NO BoxShadow of its own (LOCAL PATCH #11,
          // vendor toast.dart / LiquidGlassContainerView.swift): a shadow
          // painted inside the anchored subtree spills past the pill's layer
          // bounds, and the slicer + the fade's opacity surface clip it at
          // the pill's rectangular bounding box — observed on-device
          // 2026-08-15 as a hard-edged rectangle where the soft shadow should
          // be. Elevation rides the anchor config instead: a native CALayer
          // shadow on the glass tier (composited by Core Animation, outside
          // every Flutter layer bound) and a shape-matched ShapeDecoration
          // shadow on the fallback tier — identical geometry either way.
          // Pill-sized on purpose — a full-screen native anchor would also
          // swallow touches destined for content behind the toast.
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: LiquidGlassContainer(
                  config: const LiquidGlassConfig(
                    effect: CNGlassEffect.plain,
                    shadow: CNGlassShadow(
                      opacity: 0.15,
                      radius: 16,
                      offset: Offset(0, 6),
                    ),
                  ),
                  child: Container(
                    key: const Key('appBoxKitCenterToastPill'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: fg),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.title != null)
                                Text(
                                  widget.title!,
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              Text(
                                widget.message,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.actionLabel != null) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () {
                              widget.onAction?.call();
                              // Authoritative removal (no ticker dependency).
                              widget.onDismissed();
                            },
                            child: Text(
                              widget.actionLabel!,
                              style: TextStyle(
                                  color: fg, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
