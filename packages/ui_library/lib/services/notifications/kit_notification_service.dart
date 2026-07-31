import 'dart:async' show Timer;

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNToast, CNToastDuration, CNToastPosition;
import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart'
    show SnackbarService, StackedService;

import 'package:appbox_kit_core/common/kit_colors.dart' show KitColors;
import 'package:appbox_kit_core/kit_locator.dart' show locator;
import 'package:ui_library/utils/kit_action/kit_snackbar_type.dart'
    show KitSnackbarType;
import '../../utils/kit_native_overlay.dart' show withNativeChromeHidden;
import 'package:appbox_kit_core/platform/kit_platform.dart' show KitPlatform;

/// Severity for [KitNotificationService.show]. Drives the M3E-tier snackbar
/// variant (Android / iOS action fallback) and the CNToast style preset (the
/// iOS default tier).
enum KitNotificationKind { info, success, error, warning }

/// Screen position for [KitNotificationService.show]'s `position` param.
/// The iOS CNToast tier honors all three values. The snackbar tiers honor
/// [center] with a kit-styled floating pill at screen center; [top]/[bottom]
/// render per the registered SnackbarConfig's anchor (bottom) — SnackPosition
/// has no center value, which is why the kit owns the center surface itself.
enum KitToastPosition { top, center, bottom }

/// The kit's transient-feedback service. One entry point that picks the right
/// native surface per platform — supersedes `kitShowNativeToast` and the
/// Material [SnackbarService] coexisting on iOS.
///
/// Routing:
/// - **Android** ([KitPlatform.supportsComposeM3E]) → host [SnackbarService]
///   (native Material `ScaffoldMessenger`), wrapped in [withNativeChromeHidden]
///   so the iOS hybrid-composition z-order fix applies where it matters.
/// - **iOS / else, no action** → [CNToast] (real Liquid Glass on iOS 26+,
///   Flutter Cupertino below). This is the default — there is no snackbar on
///   iOS unless an action is required.
/// - **iOS / else, with [actionLabel]** → [SnackbarService] fallback, because
///   CNToast is fire-and-forget and cannot host an action button. The action
///   parameter is the ONLY thing that promotes iOS from a toast to a snackbar;
///   without it the two never coexist.
/// - **Snackbar tier + `position: KitToastPosition.center`** → a kit-owned
///   floating pill ([_KitCenterToastPill]) at screen center instead of the
///   GetX snackbar. It still hosts the action button that promoted iOS onto
///   this tier.
///
/// Host boot requirement: `setupLocator()` (registers this service) +
/// `setupKitSnackbars()` (registers the SnackbarConfig variants the Android +
/// fallback tiers render).
class KitNotificationService {
  /// Shows transient native feedback for [message].
  ///
  /// [context] is honored on the iOS-toast tier (CNToast resolves the Overlay
  /// from it). When null, the service falls back to the app's navigator-key
  /// context ([StackedService.navigatorKey]) so context-less callers (KitAction
  /// notifications) still render on iOS. If neither is mounted (pre-boot), the
  /// iOS tier debugPrints and no-ops rather than throwing.
  ///
  /// [duration] is honored where the tier accepts a free-form [Duration] (the
  /// snackbar tiers); on the CNToast tier it is snapped to the nearest preset.
  ///
  /// [position] places the toast: the CNToast tier honors all three values;
  /// the snackbar tiers honor [KitToastPosition.center] with a kit-styled
  /// floating pill at screen center, and render top/bottom bottom-anchored
  /// (the registered SnackbarConfig's anchor). Defaults to
  /// [KitToastPosition.top] to clear the status bar / Dynamic Island.
  ///
  /// [actionLabel] / [onAction] render a snackbar action button on the snackbar
  /// tiers. Passing a non-null [actionLabel] forces iOS onto the snackbar tier.
  ///
  /// [title] and [variant] are snackbar-tier-only overrides (CNToast has no
  /// title or variant concept; it derives its style from [kind]). [variant] may
  /// be a [KitSnackbarType] or a host enum variant with a registered config —
  /// when null it defaults to the variant mapped from [kind].
  Future<void> show(
    String message, {
    KitNotificationKind kind = KitNotificationKind.info,
    Duration? duration,
    BuildContext? context,
    String? title,
    dynamic variant,
    String? actionLabel,
    VoidCallback? onAction,
    KitToastPosition position = KitToastPosition.top,
  }) {
    if (KitPlatform.supportsComposeM3E || actionLabel != null) {
      if (position == KitToastPosition.center) {
        return _centerPill(
            message, kind, duration, context, title, actionLabel, onAction);
      }
      // Resolve at call time (not construction) so tests can register a stub
      // SnackbarService before invoking show().
      final snackbar = locator<SnackbarService>();
      return withNativeChromeHidden(
        () => snackbar.showCustomSnackBar(
          message: message,
          title: title,
          variant: variant ?? _snackbarVariant(kind),
          duration: duration ?? const Duration(seconds: 3),
          mainButtonTitle: actionLabel,
          onMainButtonTapped: onAction,
        ),
      );
    }
    return _cnToast(message, kind, duration, context, position);
  }

  /// The currently-shown center pill, so a new one replaces it (GetX-style
  /// replace semantics) instead of stacking two capsules at screen center.
  OverlayEntry? _activeCenterPill;

  /// Snackbar-tier center path: a kit-owned floating pill at screen center.
  /// SnackPosition (stacked_services/GetX) has no center value, so the kit
  /// presents this surface directly on the Overlay. Can host the action
  /// button that promoted iOS onto this tier.
  Future<void> _centerPill(
    String message,
    KitNotificationKind kind,
    Duration? duration,
    BuildContext? context,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  ) async {
    // Same de-mix guard as _cnToast: never stack the pill on an open GetX
    // snackbar (an action snackbar's onAction may chain this call).
    final snackbar = locator<SnackbarService>();
    if (snackbar.isSnackbarOpen) {
      await snackbar.closeSnackbar();
    }
    // Resolved after the await, mirroring _cnToast: the caller's context may
    // have unmounted while the snackbar animated off.
    final ctx = (context != null && context.mounted)
        ? context
        : StackedService.navigatorKey?.currentContext;
    final overlay = (ctx != null && ctx.mounted) ? Overlay.maybeOf(ctx) : null;
    if (overlay == null) {
      // Pre-boot: no Overlay to host the pill. No-op; never throw.
      debugPrint('KitNotificationService: no Overlay for center pill tier; '
          'message dropped: "$message"');
      return;
    }
    // Not wrapped in withNativeChromeHidden: the pill paints no blur scrim,
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
    KitNotificationKind kind,
    Duration? duration,
    BuildContext? context,
    KitToastPosition position,
  ) async {
    // An action snackbar's onAction often chains a follow-up toast (e.g. the
    // showcase split button's Confirm → 'Sent'). The two surfaces never
    // coexist on iOS: dismiss the open snackbar first and wait for its exit
    // animation — closeSnackbar()'s future resolves only once the Get overlay
    // entry is removed, i.e. the snackbar is completely off screen.
    final snackbar = locator<SnackbarService>();
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
      debugPrint('KitNotificationService: no BuildContext for iOS toast tier; '
          'message dropped: "$message"');
      return;
    }
    final pos = _cnPosition(position);
    final preset = _cnDuration(duration);
    switch (kind) {
      case KitNotificationKind.info:
        CNToast.info(
            context: ctx, message: message, duration: preset, position: pos);
      case KitNotificationKind.warning:
        CNToast.warning(
            context: ctx, message: message, duration: preset, position: pos);
      case KitNotificationKind.success:
        CNToast.success(
            context: ctx, message: message, duration: preset, position: pos);
      case KitNotificationKind.error:
        CNToast.error(
            context: ctx, message: message, duration: preset, position: pos);
    }
  }

  static KitSnackbarType _snackbarVariant(KitNotificationKind kind) =>
      switch (kind) {
        KitNotificationKind.info => KitSnackbarType.kitAutoProcessInfo,
        KitNotificationKind.success => KitSnackbarType.kitAutoProcessSuccess,
        KitNotificationKind.error => KitSnackbarType.kitAutoProcessError,
        KitNotificationKind.warning => KitSnackbarType.kitAutoProcessWarning,
      };

  static CNToastPosition _cnPosition(KitToastPosition p) => switch (p) {
        KitToastPosition.top => CNToastPosition.top,
        KitToastPosition.center => CNToastPosition.center,
        KitToastPosition.bottom => CNToastPosition.bottom,
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
/// [KitNotificationService.show] gets `position: KitToastPosition.center` on
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
  final KitNotificationKind kind;

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
  // Matches setupKitSnackbars' animationDuration / curves.
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
    // Per-kind palette mirrors setupKitSnackbars (kit_snackbar_setup.dart) —
    // keep the two in sync.
    final (bg, fg, icon) = switch (widget.kind) {
      KitNotificationKind.info => (
          KitColors.surface2,
          KitColors.muted,
          Icons.info_outline
        ),
      KitNotificationKind.success => (
          KitColors.good,
          KitColors.onAccent,
          Icons.check_circle_outline
        ),
      KitNotificationKind.error => (
          KitColors.danger,
          Colors.white,
          Icons.error_outline_rounded
        ),
      KitNotificationKind.warning => (
          const Color(0xFFFFF7ED),
          KitColors.warn,
          Icons.warning_amber_outlined
        ),
    };

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Align(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  key: const Key('kitCenterToastPill'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
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
    );
  }
}
