import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/material.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart'
    show ArxaKitPlatform;

import '../../widgets/arxa_kit_frosted_surface.dart';
import '../../widgets/arxa_kit_native_button.dart';

/// The ask-surfaces behind [ArxaKitNotificationService]'s `confirm`/`prompt`/
/// `notice` verbs — kit-rendered so apps never register stacked dialog/sheet
/// variants for the generic cases. Service-internal: not barrel-exported.

/// Kit text-input dialog for `ArxaKitNotificationService.prompt`. iOS tier
/// mirrors [ArxaKitFrostedAlertDialog]'s idiom (frosted panel, stacked pill
/// buttons) with a [CupertinoTextField] — a CN platform-view field can
/// mis-size inside a dialog overlay, so the field is Flutter-drawn. M3 tier is
/// a stock [AlertDialog] with a [TextField]. Pops with the trimmed entry, or
/// null on cancel / barrier-dismiss / empty entry.
class ArxaKitPromptDialog extends StatefulWidget {
  const ArxaKitPromptDialog({
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
  State<ArxaKitPromptDialog> createState() => _ArxaKitPromptDialogState();
}

class _ArxaKitPromptDialogState extends State<ArxaKitPromptDialog> {
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
    if (ArxaKitPlatform.supportsComposeM3E) {
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
        child: ArxaKitFrostedSurface(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          // Opaque + saveLayer-free, always: the action column hosts CN
          // platform-view buttons on the glass tier and a BackdropFilter
          // cannot sample them (flutter#175048) — the same recipe as the
          // alert dialog (arxa_kit_native_dialog.dart:215-221) and the
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
                child: ArxaKitNativeButton(
                  label: widget.actionLabel,
                  style: ArxaKitButtonStyle.prominentGlass,
                  onPressed: _save,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ArxaKitNativeButton(
                  label: widget.cancelLabel,
                  style: ArxaKitButtonStyle.glass,
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

/// Kit notice-sheet body for `ArxaKitNotificationService.notice` — a
/// title + message column, dismissible by drag/barrier. The tier chrome
/// (M3 stock sheet / iOS glass body) comes from `arxaKitShowSheet`.
class ArxaKitNoticeSheetBody extends StatelessWidget {
  const ArxaKitNoticeSheetBody({
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
