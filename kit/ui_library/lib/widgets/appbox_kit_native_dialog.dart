import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/common/appbox_kit_glyphs.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_frosted_surface.dart';
import 'appbox_kit_native_button.dart';

/// Style role for a [AppBoxKitNativeDialogAction] — drives the action button's
/// emphasis on the frosted tier and its tint on the M3 tier.
enum AppBoxKitDialogActionRole {
  /// The confirming CTA — filled accent pill (iOS 26 `prominentGlass` look).
  primary,

  /// A neutral alternative — subdued glass pill. The default.
  secondary,

  /// An irreversible action — tinted, with the glyph in [ColorScheme.error].
  destructive,
}

/// One action in [appBoxKitShowNativeDialog]'s stacked action column.
///
/// Primitives only ([label], optional [glyph], [role]) so hosts never import
/// the underlying button deps. [value] is handed back to the dialog's caller
/// when the action is tapped (`Navigator.pop(context, value)`); [onPressed]
/// fires first, for side effects. Both are optional — a bare action still
/// dismisses the dialog with a `null` result.
class AppBoxKitNativeDialogAction<T> {
  const AppBoxKitNativeDialogAction({
    required this.label,
    this.glyph,
    this.role = AppBoxKitDialogActionRole.secondary,
    this.value,
    this.onPressed,
  });

  /// The button label.
  final String label;

  /// Optional leading glyph — one token pairing the Material icon with its
  /// SF Symbol (see [AppBoxKitGlyphs]).
  final AppBoxKitGlyph? glyph;

  /// Emphasis role — see [AppBoxKitDialogActionRole].
  final AppBoxKitDialogActionRole role;

  /// Result the `appBoxKitShowNativeDialog` future resolves to when this action is
  /// tapped.
  final T? value;

  /// Side effect run on tap, before the dialog pops.
  final VoidCallback? onPressed;
}

/// Shows a platform-adaptive alert dialog and resolves to the tapped action's
/// [AppBoxKitNativeDialogAction.value] (`null` on barrier-dismiss / back).
///
/// Routing (mirrors [AppBoxKitNotificationService]'s tier-routing pattern):
///
/// - **Android** ([AppBoxKitPlatform.supportsComposeM3E]) → stock M3 [AlertDialog]
///   (title / content / text-button actions, destructive tinted
///   [ColorScheme.error]). There is no `m3e_collection` dialog class, and the
///   M3 dialog idiom is a plain surface — no frosted panel on this tier.
/// - **iOS / else** → the iOS 26 alert *idiom*, Flutter-drawn: a
///   [AppBoxKitFrostedSurface] panel (ADR 0010's content-layer frosted tier —
///   dialog bodies are Flutter glass; platform-view glass is pinned chrome
///   only) with a bold centered title, a gray message, and VERTICALLY STACKED
///   full-width [AppBoxKitNativeButton]s — the [AppBoxKitDialogActionRole.primary] action
///   filled (`prominentGlass`), the rest subdued glass, destructive tinted.
///   [showDialog] supplies the plain-dim barrier and the stock fade+scale
///   entrance, which IS the idiom — no custom transition.
///
/// The generic result is honored end-to-end: tapping an action pops the route
/// with its value, so `await appBoxKitShowNativeDialog<T>(...)` resolves to it.
///
/// Accepted ceiling (ADR 0011, item 2): no real `UIAlertController` — this
/// reproduces the alert *idiom* (glass panel + stacked pill actions), not
/// the system alert.
Future<T?> appBoxKitShowNativeDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AppBoxKitNativeDialogAction<T>> actions,
  bool barrierDismissible = true,
  bool opaqueGlass = true,
}) async {
  // Bump the shared modal depth for the dialog's lifetime (same bracket as
  // appBoxKitShowSheet): no navigator registers CNTabBarRouteObserver, so the
  // route push alone never moves anyModalDepth — without this, native glass
  // on the obscured page would composite above the dialog. Marking BEFORE the
  // push also lets AppBoxKitNativeChromeGates INSIDE the dialog snapshot the bumped
  // depth as their mount baseline, so they never self-hide.
  CNTabBarRouteObserver.markAnyModalActive();
  try {
    // Android → stock M3 AlertDialog (the M3 dialog idiom; no frosted panel).
    if (AppBoxKitPlatform.supportsComposeM3E) {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: [
            for (final action in actions)
              TextButton(
                onPressed: () {
                  action.onPressed?.call();
                  Navigator.of(dialogContext).pop(action.value);
                },
                style: action.role == AppBoxKitDialogActionRole.destructive
                    ? TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(dialogContext).colorScheme.error,
                      )
                    : null,
                child: Text(action.label),
              ),
          ],
        ),
      );
    }
    // iOS / macOS / else → Flutter-drawn frosted panel (the iOS 26 alert
    // idiom) over showDialog's plain-dim barrier.
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => AppBoxKitFrostedAlertDialog<T>(
        title: title,
        message: message,
        actions: actions,
        opaqueGlass: opaqueGlass,
      ),
    );
  } finally {
    // Future completes on pop → restore. `finally` keeps the depth balanced
    // even if the dialog route throws.
    CNTabBarRouteObserver.markAnyModalInactive();
  }
}

/// The iOS-tier dialog panel: a [AppBoxKitFrostedSurface] body (radius 24, ~300pt
/// wide) with centered title/message and a stacked full-width action column.
///
/// Hosts usually go through [appBoxKitShowNativeDialog]. Embed it directly when a
/// dialog framework owns the route (e.g. stacked's DialogService builders):
/// pass `popOnAction: false` so the framework's completer owns dismissal, and
/// pair each action's [AppBoxKitNativeDialogAction.onPressed] with that completer.
/// The widget self-brackets the shared modal depth (initState/dispose), so
/// embedded use keeps native glass compositing correct; the bracket pairs
/// harmlessly with [appBoxKitShowNativeDialog]'s own pre-push mark (the depth is a
/// clamped counter).
class AppBoxKitFrostedAlertDialog<T> extends StatefulWidget {
  const AppBoxKitFrostedAlertDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.popOnAction = true,
    this.opaqueGlass = true,
  });

  final String title;
  final String? message;
  final List<AppBoxKitNativeDialogAction<T>> actions;

  /// Whether tapping an action pops the route with the action's value.
  /// [appBoxKitShowNativeDialog] wants the pop; embedded hosts (stacked
  /// DialogService) set false and dismiss via their own completer.
  final bool popOnAction;

  /// Opaque panel (default `true`): the frosted surface takes the tint token
  /// at alpha 1.0 on the platform-view-safe branch — the panel hosts CN
  /// native buttons (platform views), and a BackdropFilter saveLayer cannot
  /// span the frame slices UiKitViews create (flutter#175048). `false`
  /// restores the translucent frosted panel.
  final bool opaqueGlass;

  @override
  State<AppBoxKitFrostedAlertDialog<T>> createState() =>
      _KitFrostedAlertDialogState<T>();
}

class _KitFrostedAlertDialogState<T> extends State<AppBoxKitFrostedAlertDialog<T>> {
  @override
  void initState() {
    super.initState();
    CNTabBarRouteObserver.markAnyModalActive();
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.markAnyModalInactive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Transparent, elevation-less Dialog: a positioning + semantics wrapper
    // only — the frosted surface owns every painted pixel (and the Dialog's
    // own transparent Material supplies the ink/text ancestry the buttons
    // need).
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: AppBoxKitFrostedSurface(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          // Opaque-by-default ruling: a fully opaque fill makes the backdrop
          // blur invisible anyway, so take the platform-view-safe branch (the
          // action column hosts CN native buttons).
          platformViewSafe: widget.opaqueGlass,
          tint: widget.opaqueGlass
              ? theme.colorScheme.surfaceContainerLowest.withValues(alpha: 1.0)
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (widget.message != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              for (var i = 0; i < widget.actions.length; i++) ...[
                // Tight full-width constraint — the stacked-pill look on every
                // tier (a tight parent width wins over AppBoxKitNativeButton's
                // content-sized shrinkWrap).
                SizedBox(
                  width: double.infinity,
                  child: _actionButton(context, widget.actions[i]),
                ),
                if (i < widget.actions.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    AppBoxKitNativeDialogAction<T> action,
  ) {
    return AppBoxKitNativeButton(
      label: action.label,
      glyph: action.glyph,
      style: switch (action.role) {
        AppBoxKitDialogActionRole.primary => AppBoxKitButtonStyle.prominentGlass,
        AppBoxKitDialogActionRole.secondary => AppBoxKitButtonStyle.glass,
        AppBoxKitDialogActionRole.destructive => AppBoxKitButtonStyle.tinted,
      },
      // kimitail: only the glyph takes the error tint — AppBoxKitNativeButton
      // exposes no label/tint color. If a red LABEL is ever required, the
      // upgrade path is a `tint` passthrough on AppBoxKitNativeButton (CNButton
      // already supports it — see kit_native_toolbar.dart).
      sfSymbolColor: action.role == AppBoxKitDialogActionRole.destructive
          ? Theme.of(context).colorScheme.error
          : null,
      onPressed: () {
        action.onPressed?.call();
        if (widget.popOnAction) Navigator.of(context).pop(action.value);
      },
    );
  }
}
