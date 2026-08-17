import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/material.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart'
    show AppBoxKitPlatform;

import '../../widgets/appbox_kit_frosted_surface.dart';
import '../../widgets/appbox_kit_native_button.dart';

/// The ask-surfaces behind [AppBoxKitNotificationService]'s `confirm`/`prompt`/
/// `notice` verbs — kit-rendered so apps never register stacked dialog/sheet
/// variants for the generic cases. Service-internal: not barrel-exported.

/// Kit text-input dialog for `AppBoxKitNotificationService.prompt`. iOS tier
/// mirrors [AppBoxKitFrostedAlertDialog]'s idiom (frosted panel, stacked pill
/// buttons) with a [CupertinoTextField] — a CN platform-view field can
/// mis-size inside a dialog overlay, so the field is Flutter-drawn. M3 tier is
/// a stock [AlertDialog] with a [TextField]. Pops with the trimmed entry, or
/// null on cancel / barrier-dismiss / empty entry.
class AppBoxKitPromptDialog extends StatefulWidget {
  const AppBoxKitPromptDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.cancelLabel,
    this.message,
    this.placeholder,
    this.initialValue,
  });

  final String title;
  final String? message;
  final String? placeholder;
  final String? initialValue;
  final String actionLabel;
  final String cancelLabel;

  @override
  State<AppBoxKitPromptDialog> createState() => _AppBoxKitPromptDialogState();
}

class _AppBoxKitPromptDialogState extends State<AppBoxKitPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void initState() {
    super.initState();
    CNTabBarRouteObserver.markAnyModalActive();
  }

  @override
  void dispose() {
    CNTabBarRouteObserver.markAnyModalInactive();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _controller.text.trim();
    Navigator.of(context).pop(trimmed.isEmpty ? null : trimmed);
  }

  @override
  Widget build(BuildContext context) {
    if (AppBoxKitPlatform.supportsComposeM3E) {
      return AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.placeholder),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.cancelLabel),
          ),
          TextButton(onPressed: _save, child: Text(widget.actionLabel)),
        ],
      );
    }
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: AppBoxKitFrostedSurface(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          // Opaque + saveLayer-free, always: the action column hosts CN
          // platform-view buttons on the glass tier and a BackdropFilter
          // cannot sample them (flutter#175048) — the same recipe as the
          // alert dialog (appbox_kit_native_dialog.dart:215-221) and the
          // sheet's opaqueGlass branch. The opaque base also pins one
          // luminance for the glass buttons.
          platformViewSafe: true,
          tint:
              theme.colorScheme.surfaceContainerLowest.withValues(alpha: 1.0),
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
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _controller,
                autofocus: true,
                placeholder: widget.placeholder,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AppBoxKitNativeButton(
                  label: widget.actionLabel,
                  style: AppBoxKitButtonStyle.prominentGlass,
                  onPressed: _save,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AppBoxKitNativeButton(
                  label: widget.cancelLabel,
                  style: AppBoxKitButtonStyle.glass,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kit notice-sheet body for `AppBoxKitNotificationService.notice` — a
/// title + message column, dismissible by drag/barrier. The tier chrome
/// (M3 stock sheet / iOS glass body) comes from `appBoxKitShowSheet`.
class AppBoxKitNoticeSheetBody extends StatelessWidget {
  const AppBoxKitNoticeSheetBody({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
