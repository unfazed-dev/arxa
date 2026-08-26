import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';

import 'package:arxa_kit_core/common/arxa_kit_glyphs.dart';
import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';

import 'arxa_kit_frosted_surface.dart';
import 'arxa_kit_native_button.dart';

/// Style role for a [ArxaKitNativeDialogAction] — drives the action button's
/// emphasis on the frosted tier and its tint on the M3 tier.
enum ArxaKitDialogActionRole {
  /// The confirming CTA — filled accent pill (iOS 26 `prominentGlass` look).
  primary,

  /// A neutral alternative — subdued glass pill. The default.
  secondary,

  /// An irreversible action — tinted, with the glyph in [ColorScheme.error].
  destructive,
}

/// One action in [arxaKitShowNativeDialog]'s stacked action column.
///
/// Primitives only ([label], optional [glyph], [role]) so hosts never import
/// the underlying button deps. [value] is handed back to the dialog's caller
/// when the action is tapped (`Navigator.pop(context, value)`); [onPressed]
/// fires first, for side effects. Both are optional — a bare action still
/// dismisses the dialog with a `null` result.
class ArxaKitNativeDialogAction<T> {
  const ArxaKitNativeDialogAction({
    required this.label,
    this.glyph,
    this.role = ArxaKitDialogActionRole.secondary,
    this.value,
    this.onPressed,
  });

  /// The button label.
  final String label;

  /// Optional leading glyph — one token pairing the Material icon with its
  /// SF Symbol (see [ArxaKitGlyphs]).
  final ArxaKitGlyph? glyph;

  /// Emphasis role — see [ArxaKitDialogActionRole].
  final ArxaKitDialogActionRole role;

  /// Result the `arxaKitShowNativeDialog` future resolves to when this action is
  /// tapped.
  final T? value;

  /// Side effect run on tap, before the dialog pops.
  final VoidCallback? onPressed;
}

/// Shows a platform-adaptive alert dialog and resolves to the tapped action's
/// [ArxaKitNativeDialogAction.value] (`null` on barrier-dismiss / back).
///
/// Routing (mirrors [ArxaKitNotificationService]'s tier-routing pattern):
///
/// - **Android** ([ArxaKitPlatform.supportsComposeM3E]) → stock M3 [AlertDialog]
///   (title / content / text-button actions, destructive tinted
///   [ColorScheme.error]). There is no `m3e_collection` dialog class, and the
///   M3 dialog idiom is a plain surface — no frosted panel on this tier.
/// - **iOS / else** → the iOS 26 alert *idiom*, Flutter-drawn: a
///   [ArxaKitFrostedSurface] panel (ADR 0010's content-layer frosted tier —
///   dialog bodies are Flutter glass; platform-view glass is pinned chrome
///   only) with a bold centered title, a gray message, and VERTICALLY STACKED
///   full-width [ArxaKitNativeButton]s — the [ArxaKitDialogActionRole.primary] action
///   filled (`prominentGlass`), the rest subdued glass, destructive tinted.
///   [showDialog] supplies the plain-dim barrier and the stock fade+scale
///   entrance, which IS the idiom — no custom transition.
///
/// The generic result is honored end-to-end: tapping an action pops the route
/// with its value, so `await arxaKitShowNativeDialog<T>(...)` resolves to it.
///
/// Accepted ceiling (ADR 0011, item 2): no real `UIAlertController` — this
/// reproduces the alert *idiom* (glass panel + stacked pill actions), not
/// the system alert.
Future<T?> arxaKitShowNativeDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<ArxaKitNativeDialogAction<T>> actions,
  bool barrierDismissible = true,
  bool opaqueGlass = true,
}) async {
  // Bump the shared modal depth for the dialog's lifetime (same bracket as
  // arxaKitShowSheet): no navigator registers CNTabBarRouteObserver, so the
  // route push alone never moves anyModalDepth — without this, native glass
  // on the obscured page would composite above the dialog. Marking BEFORE the
  // push also lets ArxaKitNativeChromeGates INSIDE the dialog snapshot the bumped
  // depth as their mount baseline, so they never self-hide.
  CNTabBarRouteObserver.markAnyModalActive();
  try {
    // Android → stock M3 AlertDialog (the M3 dialog idiom; no frosted panel).
    if (ArxaKitPlatform.supportsComposeM3E) {
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
                style: action.role == ArxaKitDialogActionRole.destructive
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
      builder: (_) => ArxaKitFrostedAlertDialog<T>(
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

/// The iOS-tier dialog panel: a [ArxaKitFrostedSurface] body (radius 24, ~300pt
/// wide) with centered title/message and a stacked full-width action column.
///
/// Hosts usually go through [arxaKitShowNativeDialog]. Embed it directly when a
/// dialog framework owns the route (e.g. stacked's DialogService builders):
/// pass `popOnAction: false` so the framework's completer owns dismissal, and
/// pair each action's [ArxaKitNativeDialogAction.onPressed] with that completer.
/// The widget self-brackets the shared modal depth (initState/dispose), so
/// embedded use keeps native glass compositing correct; the bracket pairs
/// harmlessly with [arxaKitShowNativeDialog]'s own pre-push mark (the depth is a
/// clamped counter).
class ArxaKitFrostedAlertDialog<T> extends StatefulWidget {
  const ArxaKitFrostedAlertDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.popOnAction = true,
    this.opaqueGlass = true,
  });

  final String title;
  final String? message;
  final List<ArxaKitNativeDialogAction<T>> actions;

  /// Whether tapping an action pops the route with the action's value.
  /// [arxaKitShowNativeDialog] wants the pop; embedded hosts (stacked
  /// DialogService) set false and dismiss via their own completer.
  final bool popOnAction;

  /// Opaque panel (default `true`): the frosted surface takes the tint token
  /// at alpha 1.0 on the platform-view-safe branch — the panel hosts CN
  /// native buttons (platform views), and a BackdropFilter saveLayer cannot
  /// span the frame slices UiKitViews create (flutter#175048). `false`
  /// restores the translucent frosted panel.
  final bool opaqueGlass;

  @override
  State<ArxaKitFrostedAlertDialog<T>> createState() =>
      _KitFrostedAlertDialogState<T>();
}

class _KitFrostedAlertDialogState<T>
    extends State<ArxaKitFrostedAlertDialog<T>> {
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
        child: ArxaKitFrostedSurface(
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
                // tier (a tight parent width wins over ArxaKitNativeButton's
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
    ArxaKitNativeDialogAction<T> action,
  ) {
    return ArxaKitNativeButton(
      label: action.label,
      glyph: action.glyph,
      style: switch (action.role) {
        ArxaKitDialogActionRole.primary =>
          ArxaKitButtonStyle.prominentGlass,
        ArxaKitDialogActionRole.secondary => ArxaKitButtonStyle.glass,
        ArxaKitDialogActionRole.destructive => ArxaKitButtonStyle.tinted,
      },
      // kimitail: only the glyph takes the error tint — ArxaKitNativeButton
      // exposes no label/tint color. If a red LABEL is ever required, the
      // upgrade path is a `tint` passthrough on ArxaKitNativeButton (CNButton
      // already supports it — see kit_native_toolbar.dart).
      sfSymbolColor: action.role == ArxaKitDialogActionRole.destructive
          ? Theme.of(context).colorScheme.error
          : null,
      onPressed: () {
        action.onPressed?.call();
        if (widget.popOnAction) Navigator.of(context).pop(action.value);
      },
    );
  }
}
