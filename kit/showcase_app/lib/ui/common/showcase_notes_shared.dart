import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

// The grouped-row sections these helpers used to back (`NotesSection`) are
// gone — the kit now owns that idiom: `KitListSection` + `KitListTile`
// (glass-card group, header, hairline dividers). Call sites migrated; the
// dialogs below are the remaining shared pieces.

/// True where dialogs should render Cupertino-style (iOS / macOS).
bool _isCupertino(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

/// Platform-adaptive dialog action: [CupertinoDialogAction] on iOS/macOS,
/// [TextButton] elsewhere. Used by [textInputDialog] only — [confirmDialog]
/// presents through the kit now.
Widget _dialogAction(
  BuildContext ctx, {
  required String label,
  required VoidCallback onPressed,
  bool isDefault = false,
}) =>
    _isCupertino(ctx)
        ? CupertinoDialogAction(
            onPressed: onPressed,
            isDefaultAction: isDefault,
            child: Text(label),
          )
        : TextButton(
            onPressed: onPressed,
            child: Text(label),
          );

/// Cancel/confirm dialog. Returns true only on confirm; [destructive] gives
/// the action the destructive role (error tint). Presents through the kit's
/// adaptive alert — [kitShowNativeDialog] (stock M3 AlertDialog on Android,
/// the Flutter-drawn frosted iOS-26 alert idiom elsewhere) — replacing the
/// hand-rolled [AlertDialog.adaptive] composition this used to build.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String actionLabel = 'OK',
  bool destructive = false,
}) async {
  final confirmed = await kitShowNativeDialog<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      const KitNativeDialogAction<bool>(label: 'Cancel', value: false),
      KitNativeDialogAction<bool>(
        label: actionLabel,
        role: destructive
            ? KitDialogActionRole.destructive
            : KitDialogActionRole.primary,
        value: true,
      ),
    ],
  );
  return confirmed == true;
}

/// Single-field text dialog. Returns the trimmed non-empty text, else null.
/// Renders the native alert per platform; the field is a [CupertinoTextField]
/// inside Cupertino alerts so it matches the iOS rename-folder sheet.
/// Stays on [AlertDialog.adaptive] (unlike [confirmDialog]) because
/// `kitShowNativeDialog` exposes only title/message/actions — there is no
/// input-field slot to migrate to.
Future<String?> textInputDialog(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showAdaptiveDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      // flutter-only: this field is embedded in a platform AlertDialog.adaptive
      // and deliberately matches the alert's own chrome (CupertinoTextField in a
      // Cupertino alert / Material TextField in a Material one). A CN platform-view
      // field can mis-size inside a dialog overlay, so the native tiering is done
      // by the alert here, not KitNativeTextField.
      content: _isCupertino(ctx)
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: hint,
              ),
            )
          : TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
            ),
      actions: [
        _dialogAction(ctx,
            label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
        _dialogAction(ctx,
            label: 'Save',
            isDefault: true,
            onPressed: () => Navigator.pop(ctx, controller.text)),
      ],
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
