// The conversation body — shared by both form-factor siblings: transcript
// bubbles (user right/gray, assistant plain), pending approvals of this
// session threaded inline (the shared ApprovalCard), and the composer.
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelWidget;
import 'package:flutter/material.dart';

import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:arxa_studio_mobile/l10n/app_localizations.dart';

import '../../../../data/conversation/conversation.dart';
import '../../../../ui/widgets/approval_card.dart';
import 'code_conversation_viewmodel.dart';

class CodeConversationBody extends ViewModelWidget<CodeConversationViewModel> {
  const CodeConversationBody({
    super.key,
    required this.viewModel,
    this.constrainWidth = false,
  });

  final CodeConversationViewModel viewModel;

  /// Tablet wraps the transcript at a readable width; mobile runs
  /// full-bleed.
  final bool constrainWidth;

  @override
  Widget build(BuildContext context, _) {
    final l10n = AppLocalizations.of(context);
    Widget transcript = viewModel.messages.isEmpty &&
            viewModel.pendingApprovals.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.codeConversationEmpty),
                if (viewModel.loadError == CodeConversationError.offline)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l10n.codeConversationOffline),
                  ),
              ],
            ),
          )
        : ListView(
            key: const PageStorageKey('code-transcript'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final message in viewModel.messages)
                if (message.isThinking)
                  _ExpandRow(
                    key: ValueKey('think-${message.id}'),
                    icon: LucideIcons.brain,
                    label: 'Thought process',
                    onTap: () => _showThoughtSheet(context, message.text),
                  )
                else if (message.isTool)
                  _ExpandRow(
                    key: ValueKey('tool-${message.id}'),
                    icon: LucideIcons.wrench,
                    label: 'Ran ${message.toolLabel}',
                    onTap: () => _showToolSheet(context, message),
                  )
                else
                  _MessageBubble(
                    key: ValueKey(message.id),
                    message: message,
                    attachmentBytes: viewModel.attachmentBytes,
                  ),
              // Pending approvals of this session thread inline, after the
              // transcript — the ask sits where the conversation stopped.
              for (final approval in viewModel.pendingApprovals)
                ApprovalCard(
                  key: ValueKey('approval-${approval.id}'),
                  approval: approval,
                  busy: viewModel.decidingId == approval.id,
                  onDecide: (answers) => viewModel.decide(approval, answers),
                ),
            ],
          );
    if (constrainWidth) {
      transcript = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: transcript,
        ),
      );
    }
    // Keyboard discipline: taps outside the composer dismiss the keyboard
    // through the TextField's onTapOutside. Scroll-coupled dismissal is
    // deliberately gone — the animated resize while reading the thread read
    // as noise, and the transcript now scrolls with no animation of its own.
    return Column(
      children: [
        if (viewModel.loadError == CodeConversationError.offline)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              title: Text(l10n.codeConversationOffline,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
        Expanded(child: transcript),
        _Composer(viewModel: viewModel),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.attachmentBytes,
  });

  final ConversationMessage message;
  final Future<Uint8List?> Function(String attachmentId) attachmentBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final alignRight = isUser;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: isUser
          ? BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      // Plain Text, deliberately. SelectableText armed TWO movers that
      // fought the transcript scroll: its inner scrollable grabbed
      // drags on fractional device-font extents (fixed earlier with
      // NeverScrollable physics), and its gesture selection — hold
      // ~500ms then drag, which is how scrolls start while reading —
      // swept highlight + handles + magnifier + Copy toolbar across
      // the text ('the text animates every time I scroll'). Text
      // carries no recognizers at all: the transcript owns every
      // gesture, and a hold-then-drag just scrolls.
      child: Text(
        message.text,
        style: theme.textTheme.bodyMedium,
      ),
    );
    final thumbnails = [
      for (final attachmentId in message.images)
        _AttachmentThumb(
          key: ValueKey('thumb-$attachmentId'),
          attachmentId: attachmentId,
          attachmentBytes: attachmentBytes,
        ),
    ];
    Widget content = bubble;
    if (thumbnails.isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Same 16px screen inset the text bubble carries — the margins
            // live on the bubble Container only, so without this the
            // thumbnails sit flush against the screen edge.
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(spacing: 6, alignment: WrapAlignment.end, children: thumbnails),
          ),
          if (message.text.isNotEmpty) bubble,
        ],
      );
    }
    return Align(alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft, child: content);
  }
}

/// One sent image in the transcript — the engine's stored bytes, fetched
/// once per id and cached by the viewmodel.
class _AttachmentThumb extends StatefulWidget {
  const _AttachmentThumb({
    super.key,
    required this.attachmentId,
    required this.attachmentBytes,
  });

  final String attachmentId;
  final Future<Uint8List?> Function(String attachmentId) attachmentBytes;

  @override
  State<_AttachmentThumb> createState() => _AttachmentThumbState();
}

class _AttachmentThumbState extends State<_AttachmentThumb> {
  late final Future<Uint8List?> _bytes = widget.attachmentBytes(widget.attachmentId);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 132,
        height: 100,
        color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFECEAE2),
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return Icon(LucideIcons.imageOff,
                  size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant);
            }
            return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}

// ---- expandable transcript rows (thinking / tool) and their content sheets
// Same sheet rules as every picker here: hug the content, cap at 86% height,
// scroll only when the content outlasts the cap.

/// The model's reasoning, verbatim — blank-line separated paragraphs, the
/// "Thought process" sheet.
Future<void> _showThoughtSheet(BuildContext context, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _showSheet(context, 'Thought process', [_SheetProse(text: text)]);
}

/// One tool execution: Input (the pretty arguments) + Output (the paired
/// result, honest when the engine flagged it as an error or none arrived).
Future<void> _showToolSheet(
    BuildContext context, ConversationMessage message) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _showSheet(context, message.toolLabel, [
    if (message.toolInput != null && message.toolInput!.isNotEmpty)
      _SheetMonoBlock(label: 'Input', text: message.toolInput!),
    if (message.text.isNotEmpty)
      _SheetMonoBlock(
        label: message.toolError ? 'Output (error)' : 'Output',
        text: message.text,
        error: message.toolError,
      )
    else
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Text(
          'No output was recorded.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF8E8E93)
                  : const Color(0xFF98928A)),
        ),
      ),
  ]);
}

/// A collapsed thread row ("Thought process", "Ran …") — grey, quiet, one
/// chevron; the tap opens the content sheet.
class _ExpandRow extends StatelessWidget {
  const _ExpandRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF98928A);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: hint),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: hint)),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 15, color: hint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prose paragraphs (the thinking sheet) — plain body text, roomy leading.
class _SheetProse extends StatelessWidget {
  const _SheetProse({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = [
      for (final paragraph in text.split('\n\n'))
        if (paragraph.trim().isNotEmpty) paragraph.trim(),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, paragraph) in paragraphs.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            // Plain Text — same contract as the bubbles: no selection
            // recognizers to sweep highlight/handles across the text
            // mid-scroll, no inner scrollable to grab the sheet's drag.
            Text(
              paragraph,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled monospace block (the tool sheet's Input / Output sections) —
/// the reference "Ctx Batch Execute" anatomy: label over one rounded box.
class _SheetMonoBlock extends StatelessWidget {
  const _SheetMonoBlock({
    required this.label,
    required this.text,
    this.error = false,
  });

  final String label;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 0, 8),
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: error ? const Color(0xFFE5484D) : null,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFECEAE2),
              borderRadius: BorderRadius.circular(14),
            ),
            // Plain Text — same contract as the bubbles and prose:
            // the sheet's scroll view is the only scroller, and no
            // selection gestures ride the text.
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-height picker sheet: X close + centered title over one rounded
/// card of option rows (icon, title, subtitle, check) — the Claude composer
/// anatomy. Hides the keyboard on open; the CALLER re-focuses on close.
Future<void> _showSheet(
    BuildContext context, String title, List<Widget> children) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final dark = Theme.of(sheetContext).brightness == Brightness.dark;
      final bg = dark ? const Color(0xFF141414) : const Color(0xFFF5F4EF);
      final card = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
      return Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.86),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          // HUG the content: the sheet is exactly as tall as its rows — up
          // to the cap. Short content -> content-height sheet, nothing to
          // scroll; long content -> the sheet sits at the cap and the rows
          // scroll inside it.
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  _SheetCloseButton(dark: dark),
                  Expanded(
                    child: Center(
                      child: Text(title,
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(children: children),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Circular X close — the sheet's only chrome besides the title.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: dark ? const Color(0xFF3A3A3C) : const Color(0xFFDDD9D0)),
        ),
        child: const Icon(LucideIcons.x, size: 20),
      ),
    );
  }
}

/// One picker row: optional tinted glyph, title + subtitle, check when
/// selected, hairline divider beneath (except the last row).
Widget _sheetRow({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData? icon,
  Color? iconColor,
  bool selected = false,
  bool isLast = false,
  double dividerIndent = 0,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final divider = dark ? const Color(0xFF2C2C2E) : const Color(0xFFE7E4DC);
  final subtitleColor =
      dark ? const Color(0xFF98989F) : theme.colorScheme.onSurfaceVariant;
  final checkColor = dark ? const Color(0xFF4A9EFF) : const Color(0xFFD97757);
  return Column(
    children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 24, color: iconColor),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: subtitleColor)),
                  ],
                ),
              ),
              if (selected) Icon(LucideIcons.check, size: 22, color: checkColor),
            ],
          ),
        ),
      ),
      if (!isLast)
        Divider(height: 1, thickness: 0.5, indent: dividerIndent, color: divider),
    ],
  );
}

/// Human label + glyph for a sandbox mode; 'Manual' is the neutral
/// never-switched presentation (matches the studio composer's wording).
String _modeLabel(String? mode) => switch (mode) {
      'danger-full-access' => 'Full access',
      'workspace-write' => 'Workspace write',
      'read-only' => 'Read only',
      _ => 'Manual',
    };

IconData _modeIcon(String? mode) => switch (mode) {
      'danger-full-access' => LucideIcons.hand,
      'workspace-write' => LucideIcons.penLine,
      'read-only' => LucideIcons.eye,
      _ => LucideIcons.hand,
    };

/// The Claude-style composer: one rounded card, placeholder line on top,
/// controls row below — attach circle, model pill, mode pill, spacer,
/// mic circle, terracotta send circle (bright when the field has text,
/// muted when empty, spinner while sending). + / mic / pills are chrome:
/// attachment, model and permission-mode pickers are not built yet, so
/// they render as static status surface, never as dead buttons.
class _Composer extends StatefulWidget {
  const _Composer({required this.viewModel});

  final CodeConversationViewModel viewModel;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    final accepted = await widget.viewModel.send(text);
    if (accepted && mounted) _controller.clear();
  }

  /// The model menu: the engine's advisory directory, current selection
  /// checked; picking one POSTs the selection to the studio.
  Future<void> _showModelMenu() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.viewModel.loadModels();
    if (!mounted) return;
    final current = widget.viewModel.currentModel;
    final rows = <Widget>[
      for (final option in widget.viewModel.models)
        _sheetRow(
          context: context,
          title: option.id,
          subtitle:
              option.groupName == null ? option.name : option.groupName!,
          selected: option.id == current,
          onTap: () {
            Navigator.pop(context);
            widget.viewModel.selectModel(option.provider, option.id);
          },
        ),
      if (widget.viewModel.models.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No models available')),
        ),
    ];
    await _showSheet(context, 'Select model', rows);
    if (mounted) _focus.requestFocus();
  }

  /// The approval-mode menu — the same read-only / workspace-write /
  /// full-access switch the studio composer owns, backed by the session's
  /// sandbox-mode log.
  Future<void> _showModeMenu() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final modes = <(String, String, String, IconData, Color)>[
      ('read-only', 'Read only', 'The agent can look, but change nothing',
          LucideIcons.eye, const Color(0xFF60A5FA)),
      ('workspace-write', 'Workspace write',
          'Changes stay inside the project workspace', LucideIcons.penLine,
          const Color(0xFFA78BFA)),
      ('danger-full-access', 'Full access',
          'No sandbox — the agent acts with full permissions',
          LucideIcons.hand, const Color(0xFFD97757)),
    ];
    if (!mounted) return;
    final current = widget.viewModel.sessionMode;
    final rows = <Widget>[
      for (final (i, (mode, label, subtitle, icon, tint)) in modes.indexed)
        _sheetRow(
          context: context,
          icon: icon,
          iconColor: tint,
          title: label,
          subtitle: subtitle,
          selected: mode == current,
          dividerIndent: 52,
          isLast: i == modes.length - 1,
          onTap: () {
            Navigator.pop(context);
            widget.viewModel.setMode(mode);
          },
        ),
    ];
    await _showSheet(context, 'Select mode', rows);
    if (mounted) _focus.requestFocus();
  }

  /// The Add-context sheet: camera / photos / files tiles plus the recent
  /// photos grid — the Claude composer's '+' anatomy, wired to the real
  /// pickers. Text files come back inline; images stage as chips.
  Future<void> _showContextSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _showSheet(
      context,
      'Add context',
      [
        _AddContextSheet(
          viewModel: widget.viewModel,
          onInlineText: (block) {
            final current = _controller.text;
            _controller.text =
                current.isEmpty ? '$block\n' : '$current\n$block\n';
          },
          onPickMode: () {
            Navigator.pop(context);
            _showModeMenu();
          },
          onPickModel: () {
            Navigator.pop(context);
            _showModelMenu();
          },
        ),
      ],
    );
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final chip = dark ? const Color(0xFF2C2C2E) : const Color(0xFFECEAE2);
    final chipText = dark ? const Color(0xFFE8E8E6) : const Color(0xFF3D3D3A);
    final hint = dark ? const Color(0xFF8E8E93) : const Color(0xFF98928A);
    final canSend =
        (_controller.text.trim().isNotEmpty || widget.viewModel.pendingImages.isNotEmpty) &&
            !widget.viewModel.sending;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
                color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE3E0D8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: !widget.viewModel.sending,
                maxLines: 3,
                minLines: 1,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: chipText),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l10n.codeComposerHint,
                  hintStyle: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: hint),
                ),
                onSubmitted: (_) => _send(),
                // THE canonical dismiss: any tap outside the editable —
                // transcript, app bar, edges.
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              ),
              if (widget.viewModel.pendingImages.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final staged in widget.viewModel.pendingImages)
                      _PendingImageChip(
                        image: staged,
                        onRemove: () => widget.viewModel.removePendingImage(staged),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showContextSheet,
                    child: _CircleAction(
                      dark: dark,
                      chip: chip,
                      chipText: chipText,
                      icon: LucideIcons.plus,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // BOTH pills flex: model ids and mode names are the
                  // variable-length content — they shrink with ellipsis
                  // instead of ever overflowing the row.
                  Flexible(
                    child: GestureDetector(
                      onTap: _showModelMenu,
                      child: _Pill(
                        label: widget.viewModel.currentModel,
                        chip: chip,
                        chipText: chipText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: GestureDetector(
                      onTap: _showModeMenu,
                      child: _Pill(
                        icon: _modeIcon(widget.viewModel.sessionMode),
                        label: _modeLabel(widget.viewModel.sessionMode),
                        chip: chip,
                        chipText: chipText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleAction(
                    dark: dark,
                    chip: chip,
                    chipText: chipText,
                    icon: LucideIcons.mic,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  _SendCircle(
                    enabled: canSend,
                    sending: widget.viewModel.sending,
                    dark: dark,
                    onTap: canSend ? _send : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circular action chip (+, mic) — flat dark-gray disc, centered glyph.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.dark,
    required this.chip,
    required this.chipText,
    required this.icon,
    required this.size,
  });

  final bool dark;
  final Color chip;
  final Color chipText;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: chip, shape: BoxShape.circle),
      child: Icon(icon, size: size, color: chipText),
    );
  }
}

/// The capsule pill (model name, permission mode) — dark capsule, optional
/// leading glyph, white label.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.chip,
    required this.chipText,
    this.icon,
  });

  final String label;
  final Color chip;
  final Color chipText;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration:
          BoxDecoration(color: chip, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: chipText),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: chipText)),
          ),
        ],
      ),
    );
  }
}

/// One staged composer image: thumbnail + remove disc.
class _PendingImageChip extends StatelessWidget {
  const _PendingImageChip({required this.image, required this.onRemove});

  final PendingImage image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final preview = image.preview;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: preview == null
              ? Container(width: 52, height: 52, color: const Color(0xFF2C2C2E))
              : Image.file(preview,
                  width: 52, height: 52, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3A3A3C),
                border: Border.all(color: const Color(0xFF141414), width: 2),
              ),
              child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Add-context body: three tiles (Camera / Photos / Files), the blue
/// recent-photos row, and — when opened — the inline library grid. Every
/// control is wired: the tiles pick for real, a grid tap stages the photo.
class _AddContextSheet extends StatefulWidget {
  const _AddContextSheet({
    required this.viewModel,
    required this.onInlineText,
    required this.onPickMode,
    required this.onPickModel,
  });

  final CodeConversationViewModel viewModel;
  final ValueChanged<String> onInlineText;

  /// The permission/model palette rows route to the composer's own
  /// native pickers (pop this sheet first) — the same sheets the
  /// composer pills open.
  final VoidCallback onPickMode;
  final VoidCallback onPickModel;

  @override
  State<_AddContextSheet> createState() => _AddContextSheetState();
}

class _AddContextSheetState extends State<_AddContextSheet> {
  bool _recentOpen = false;
  bool _commandsOpen = false;
  late final Future<List<AssetEntity>> _recent =
      widget.viewModel.media.recentPhotos();

  @override
  void initState() {
    super.initState();
    // The palette rides the engine's registry — fetch once, quietly.
    widget.viewModel.loadCommands();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  /// Stage an image and close; a refused file toasts and stays open.
  Future<void> _stage(Future<XFile?> pick) async {
    final file = await pick;
    if (file == null) return; // the user backed out of the picker
    final error = await widget.viewModel.stageImage(file);
    if (!mounted) return;
    if (error != null) {
      _toast(error);
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _pickFile() async {
    final file = await widget.viewModel.media.pickFile();
    if (file == null || !mounted) return;
    final outcome = await widget.viewModel.stageFile(file);
    if (!mounted) return;
    if (outcome.error != null) {
      _toast(outcome.error!);
      return;
    }
    if (outcome.inline != null) widget.onInlineText(outcome.inline!);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final tile = dark ? const Color(0xFF2C2C2E) : const Color(0xFFECEAE2);
    final media = widget.viewModel.media;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (media.hasCamera)
              Expanded(
                child: _ContextTile(
                  icon: LucideIcons.camera,
                  label: 'Camera',
                  color: tile,
                  onTap: () => _stage(media.capturePhoto()),
                ),
              ),
            if (media.hasCamera) const SizedBox(width: 10),
            Expanded(
              child: _ContextTile(
                icon: LucideIcons.image,
                label: 'Photos',
                color: tile,
                onTap: () => _stage(media.pickPhoto()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ContextTile(
                icon: LucideIcons.fileUp,
                label: 'Files',
                color: tile,
                onTap: _pickFile,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ContextRow(
          icon: LucideIcons.images,
          label: _recentOpen ? 'Hide recent photos' : 'Show recent photos',
          tint: const Color(0xFF4A9EFF),
          onTap: () => setState(() => _recentOpen = !_recentOpen),
        ),
        if (_recentOpen)
          _RecentPhotoGrid(
            recent: _recent,
            originFile: media.originFile,
            onPicked: (file) =>
                _stage(Future.value(XFile(file.path))),
          ),
        const SizedBox(height: 12),
        _ContextRow(
          icon: LucideIcons.terminal,
          label: _commandsOpen ? 'Hide commands' : 'Show commands',
          tint: const Color(0xFF4A9EFF),
          onTap: () => setState(() => _commandsOpen = !_commandsOpen),
        ),
        if (_commandsOpen)
          _CommandList(
            viewModel: widget.viewModel,
            onRun: _runCommand,
            onPickMode: widget.onPickMode,
            onPickModel: widget.onPickModel,
          ),
      ],
    );
  }

  /// Execute one slash-command line and toast the engine's own answer
  /// (the registry's refusals are honest — show them verbatim).
  Future<void> _runCommand(String line) async {
    final text = await widget.viewModel.runCommand(line);
    if (!mounted) return;
    if (text != null) _toast(text);
    if (Navigator.of(context).canPop()) Navigator.pop(context);
  }
}

/// The engine's human-command palette — the studio composer's `+` list,
/// verbatim from the engine registry. Special-cased rows route to native
/// surfaces: permission → the mode picker, model → the model picker,
/// export → the share sheet; everything else runs as a slash line
/// (prompting first when the command reads an argument).
class _CommandList extends StatelessWidget {
  const _CommandList({
    required this.viewModel,
    required this.onRun,
    required this.onPickMode,
    required this.onPickModel,
  });

  final CodeConversationViewModel viewModel;
  final Future<void> Function(String line) onRun;
  final VoidCallback onPickMode;
  final VoidCallback onPickModel;

  Future<void> _execute(
      BuildContext context, EngineCommand command) async {
    switch (command.name) {
      case 'permission':
        onPickMode();
        return;
      case 'model':
        onPickModel();
        return;
      case 'export':
        final shared = await viewModel.exportTranscript();
        if (shared && context.mounted) Navigator.pop(context);
        return;
    }
    final hint = command.inputHint;
    if (hint == null || hint.isEmpty) {
      await onRun('/${command.name}');
      return;
    }
    if (!context.mounted) return;
    final line = await _promptCommandLine(context, command);
    if (line != null && line.isNotEmpty) await onRun(line);
  }

  @override
  Widget build(BuildContext context) {
    // The model row is composer-native on the phone (it opens the model
    // picker, not a slash run), and the engine registers it outside the
    // command registry — synthesize it so the palette matches the
    // studio's list verbatim.
    final commands = <EngineCommand>[...viewModel.commands];
    if (!commands.any((c) => c.name == 'model')) {
      const row = EngineCommand(
          name: 'model', description: 'Select the model for this conversation');
      final idx = commands.indexWhere((c) => c.name.compareTo('model') > 0);
      idx < 0 ? commands.add(row) : commands.insert(idx, row);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (commands.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            viewModel.commandBusy ? '…' : 'No commands available',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: dark ? const Color(0xFF8E8E93) : const Color(0xFF98928A)),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, command) in commands.indexed)
          _CommandRow(
            command: command,
            enabled: !viewModel.commandBusy,
            isLast: i == commands.length - 1,
            onTap: () => _execute(context, command),
          ),
      ],
    );
  }
}

/// One palette row: the bold command name and its description — the
/// studio composer's menu anatomy.
class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.onTap,
    required this.enabled,
    required this.isLast,
  });

  final EngineCommand command;
  final VoidCallback onTap;
  final bool enabled;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = dark ? const Color(0xFF8E8E93) : const Color(0xFF98928A);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('/${command.name}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(command.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: hint)),
              ),
            ]),
            if (command.inputHint != null &&
                command.inputHint!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(command.inputHint!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: hint)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ask for a command's free-text argument (`/feedback <text>`, `/goal` …).
/// Returns the complete slash line, or null when cancelled.
Future<String?> _promptCommandLine(
    BuildContext context, EngineCommand command) async {
  final controller = TextEditingController();
  final line = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('/${command.name}'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext,
              '/${command.name} ${controller.text.trim()}'),
          child: const Text('Run'),
        ),
      ],
    ),
  );
  return line?.trim();
}

/// A wide rounded row (icon + label) — the sheet's secondary actions.
class _ContextRow extends StatelessWidget {
  const _ContextRow({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFECEAE2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: tint),
            const SizedBox(width: 12),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}

/// One big picker tile (glyph over label) — the sheet's primary actions.
class _ContextTile extends StatelessWidget {
  const _ContextTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 104,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// The inline recent-library grid — a fixed window that scrolls inside the
/// sheet when the library outlasts it. A tap stages the original photo.
class _RecentPhotoGrid extends StatelessWidget {
  const _RecentPhotoGrid({
    required this.recent,
    required this.originFile,
    required this.onPicked,
  });

  final Future<List<AssetEntity>> recent;
  final Future<File?> Function(AssetEntity asset) originFile;
  final ValueChanged<File> onPicked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 288,
        child: FutureBuilder<List<AssetEntity>>(
          future: recent,
          builder: (context, snapshot) {
            final assets = snapshot.data;
            if (assets == null) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (assets.isEmpty) {
              return Center(
                child: Text('No recent photos',
                    style: Theme.of(context).textTheme.bodyMedium),
              );
            }
            return GridView.builder(
              physics: const ClampingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4),
              itemCount: assets.length,
              itemBuilder: (context, index) => _AssetThumb(
                asset: assets[index],
                originFile: originFile,
                onPicked: onPicked,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  const _AssetThumb({
    required this.asset,
    required this.originFile,
    required this.onPicked,
  });

  final AssetEntity asset;
  final Future<File?> Function(AssetEntity asset) originFile;
  final ValueChanged<File> onPicked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final file = await originFile(asset);
        if (file != null) onPicked(file);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<Uint8List?>(
          future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest);
            }
            return Image.memory(bytes,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                gaplessPlayback: true);
          },
        ),
      ),
    );
  }
}

/// The terracotta send circle — bright with a white up-arrow when sendable,
/// muted clay when empty, spinner while sending.
class _SendCircle extends StatelessWidget {
  const _SendCircle({
    required this.enabled,
    required this.sending,
    required this.dark,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = enabled
        ? const Color(0xFFD97757)
        : (dark ? const Color(0xFF573D33) : const Color(0xFFE8CDBF));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Center(
          child: sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(LucideIcons.arrowUp,
                  size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
