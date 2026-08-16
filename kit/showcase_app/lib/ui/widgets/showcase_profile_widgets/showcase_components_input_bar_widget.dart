/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the input-bar demo — a fully usable docked
/// composer over the live thread. The add action opens the kit sheet
/// (camera / photo / file / location — fake picks rendered as contrast-safe
/// option rows, the iOS `+`-menu idiom, NOT glass buttons: on the sheet's
/// opaque bright base the native button tier reads washed out — measured on
/// the iOS 26.5 simulator 2026-08-16).
///
/// The record flow is tap-to-toggle on the NATIVE trailing action: the mic
/// is a real [AppBoxKitNativeIconButton] — a Liquid Glass circle on iOS 26 —
/// whose glyph follows the recorder phase and animates mic → stop → mic
/// through the SF Symbol replace transition on the Apple tiers (the button
/// tree updates in place, so the native view survives the swap and can
/// animate it). TAP mic to record — the OS microphone-permission prompt
/// fires through the kit on the first tap — TAP stop to stop and send; the
/// strip's Cancel aborts, and a stop under a second discards as a fumble.
/// A tap-driven model is what makes the native button viable at all: its
/// UIKit surface claims the touch stream, so Flutter could never see the
/// hold — but the button's own `onPressed` carries taps natively.
///
/// The kit bar's action taps keep the keyboard up (the bar joins the input
/// tap group), so the add action never dismisses mid-composition; starting a
/// recording drops the keyboard deliberately, as the messengers do.
///
/// Requirements:
/// 1. [Input bar] — browse-the-components-gallery
/// A docked native multiline composer with attach and voice actions and a
/// submit handler.
/// 2. [Input bar — tap-to-toggle record] — browse-the-components-gallery
/// Tapping the mic records through the kit audio service; the glyph swaps
/// to stop; tapping stop sends, the strip's cancel discards.
///
/// Relationships: stateful for draft state only; the thread and the recorder
/// are the viewmodel's — text/attachment drafts and finished voice notes go
/// up through [ShowcaseComponentsViewModel.sendDraft], the record button's
/// taps through start/stop/cancelRecording.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_input_bar_widget.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_composer_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

/// One fake pick per attach kind — the seeded data behind the sheet.
ShowcaseComposerAttachmentModel _fakeAttachment(
        ShowcaseComposerAttachmentKind kind) =>
    switch (kind) {
      ShowcaseComposerAttachmentKind.camera =>
        const ShowcaseComposerAttachmentModel(
            kind: ShowcaseComposerAttachmentKind.camera,
            name: 'IMG_0816.jpg',
            detail: '1.8 MB · Camera'),
      ShowcaseComposerAttachmentKind.photo =>
        const ShowcaseComposerAttachmentModel(
            kind: ShowcaseComposerAttachmentKind.photo,
            name: 'gallery-shot.png',
            detail: '2.4 MB · Photo'),
      ShowcaseComposerAttachmentKind.file =>
        const ShowcaseComposerAttachmentModel(
            kind: ShowcaseComposerAttachmentKind.file,
            name: 'handoff-spec.pdf',
            detail: '812 KB · File'),
      ShowcaseComposerAttachmentKind.location =>
        const ShowcaseComposerAttachmentModel(
            kind: ShowcaseComposerAttachmentKind.location,
            name: 'Current location',
            detail: 'Pinned · Location'),
    };

class ShowcaseComponentsInputBarWidget extends StatefulWidget {
  const ShowcaseComponentsInputBarWidget({required this.viewModel, super.key});

  /// Owns the thread and the recorder — drafts go up through sendDraft.
  final ShowcaseComponentsViewModel viewModel;

  @override
  State<ShowcaseComponentsInputBarWidget> createState() =>
      _ShowcaseComponentsInputBarWidgetState();
}

class _ShowcaseComponentsInputBarWidgetState
    extends State<ShowcaseComponentsInputBarWidget> {
  final _text = TextEditingController();

  final List<ShowcaseComposerAttachmentModel> _pending = [];

  bool get _hasDraft => _text.text.trim().isNotEmpty || _pending.isNotEmpty;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    // Modals push on the root navigator so they cover the tab bar (same
    // pattern as the overlays card).
    final context = StackedService.navigatorKey?.currentContext ?? this.context;
    final kind = await appBoxKitShowSheet<ShowcaseComposerAttachmentKind>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Attach',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              appBoxKitVerticalSpaceSmall,
              // Contrast-safe option rows, not native glass buttons: the
              // iOS tier's glass button label reads washed out on the
              // sheet's opaque bright base (measured 2026-08-16). The
              // messenger + menu idiom is icon + label rows anyway.
              for (final (optionKind, glyph, label) in [
                (
                  ShowcaseComposerAttachmentKind.camera,
                  AppBoxKitGlyphs.camera,
                  'Take photo'
                ),
                (
                  ShowcaseComposerAttachmentKind.photo,
                  AppBoxKitGlyphs.photo,
                  'Photo library'
                ),
                (
                  ShowcaseComposerAttachmentKind.file,
                  AppBoxKitGlyphs.folder,
                  'Choose file'
                ),
                (
                  ShowcaseComposerAttachmentKind.location,
                  AppBoxKitGlyphs.locationPin,
                  'Share location'
                ),
              ])
                _AttachOptionRow(
                  glyph: glyph,
                  label: label,
                  onTap: () => Navigator.of(sheetContext).pop(optionKind),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    setState(() => _pending.add(_fakeAttachment(kind)));
  }

  // ── Tap-to-toggle record (native trailing action, glyph = phase) ────────

  void _onMicTap() {
    // Recording replaces text input — dropping the keyboard here is the
    // intended messenger UX (unlike the add action, which keeps it). The
    // bare function, not a context extension: the kit barrel exports two
    // dismissKeyboard extensions and the member is ambiguous at call sites
    // importing both.
    appBoxKitDismissKeyboard();
    unawaited(widget.viewModel.startRecording().then((started) {
      // Permission denial is a warning, not an error (notes-shell idiom).
      if (!started && mounted) {
        appBoxKitLocator<AppBoxKitNotificationService>().show(
          'Microphone permission needed',
          kind: AppBoxKitNotificationKind.warning,
          context: context,
        );
      }
    }));
  }

  void _onStopTap() {
    unawaited(widget.viewModel.stopRecording().then((note) {
      if (note != null) {
        widget.viewModel.sendDraft(ShowcaseComposerDraftModel(
          voiceNoteSeconds: note.seconds,
          voiceNotePath: note.path,
        ));
      }
    }));
  }

  void _send() {
    widget.viewModel.sendDraft(ShowcaseComposerDraftModel(
      text: _text.text,
      attachments: List.of(_pending),
    ));
    _text.clear();
    setState(_pending.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_pending.isNotEmpty)
          // No panel behind the row — each CHIP is the opaque surface,
          // floating over the thread (the messenger attachment-preview
          // idiom). A strip base in the same tint token as the chips
          // would merge them into one blob.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (index, attachment) in _pending.indexed)
                    Padding(
                      padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
                      child: _PendingChip(
                        icon: switch (attachment.kind) {
                          ShowcaseComposerAttachmentKind.camera =>
                            AppBoxKitGlyphs.camera.icon,
                          ShowcaseComposerAttachmentKind.photo =>
                            AppBoxKitGlyphs.photo.icon,
                          ShowcaseComposerAttachmentKind.file =>
                            AppBoxKitGlyphs.folder.icon,
                          ShowcaseComposerAttachmentKind.location =>
                            AppBoxKitGlyphs.locationPin.icon,
                        },
                        label: attachment.name,
                        onRemove: () =>
                            setState(() => _pending.removeAt(index)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        // The whole bar rebuilds on a phase change so the trailing action
        // can swap glyphs — the button widget stays at the same tree
        // position, which is what lets the native tier animate the swap
        // (SF Symbol replace) instead of recreating the platform view.
        AppBoxKitStreamBuilder<ShowcaseComposerRecorderPhase>(
          stream: widget.viewModel.recorderPhase,
          builder: (context, phase) {
            final recording = phase == ShowcaseComposerRecorderPhase.recording;
            return Stack(
              children: [
                AppBoxKitNativeInputBar(
                  // Native composer (default tiers): the field is a real
                  // multiline Liquid Glass composer on iOS and a growing
                  // TextFieldM3E on Android. The bar's action taps join
                  // the input tap group, so the add action keeps the
                  // keyboard up mid-composition.
                  controller: _text,
                  hintText: 'Message',
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                  leading: [
                    AppBoxKitNativeIconButton(
                      glyph: AppBoxKitGlyphs.add,
                      onPressed: _pickAttachment,
                    ),
                  ],
                  trailing: [
                    // Exactly one trailing action, always at the same slot:
                    // stop while recording, else send for a live draft, else
                    // the idle mic. Same widget type + same key at the same
                    // position = the CN button updates in place and its
                    // glyph change animates natively.
                    AppBoxKitNativeIconButton(
                      key: const ValueKey('composer-record-button'),
                      glyph: recording
                          ? AppBoxKitGlyphs.stop
                          : _hasDraft
                              ? AppBoxKitGlyphs.send
                              : AppBoxKitGlyphs.mic,
                      // Disabled only while the OS permission prompt is up
                      // (phase == starting) — the prompt claims the screen,
                      // and a second tap mid-flight must be a no-op.
                      onPressed: recording
                          ? _onStopTap
                          : _hasDraft
                              ? _send
                              : phase == ShowcaseComposerRecorderPhase.starting
                                  ? null
                                  : _onMicTap,
                    ),
                  ],
                ),
                if (recording)
                  Positioned(
                    // Cover the field area, leave the trailing stop action
                    // uncovered — the stop tap is the send.
                    left: 12,
                    top: 0,
                    bottom: 0,
                    right: 60,
                    child: Center(
                      // Both live values bind OUTSIDE the strip and hand
                      // VALUES down — the strip stays a dumb value widget
                      // (no inner subscriptions to churn on the per-tick
                      // rebuild) and the bar itself never rebuilds per tick.
                      child: AppBoxKitStreamBuilder<Duration?>(
                        stream: widget.viewModel.recordingElapsed,
                        builder: (context, elapsed) =>
                            AppBoxKitStreamBuilder<double>(
                          stream: widget.viewModel.recordingLevel,
                          builder: (context, dbfs) => _RecordingStrip(
                            elapsed: elapsed,
                            level: dbfs,
                            onCancel: widget.viewModel.cancelRecording,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The recording strip: elapsed time from the recorder, a level dot
/// breathing with the live amplitude, and the two affordances the
/// tap-toggle model supports — Cancel here, send on the trailing stop
/// button. Pure-Flutter frosted surface (no platform view involved): it
/// overlays the field while the native button owns the record gestures.
class _RecordingStrip extends StatelessWidget {
  const _RecordingStrip({
    required this.elapsed,
    required this.level,
    required this.onCancel,
  });

  /// Current recording duration; null only before the recorder's first
  /// tick (rendered as 0:00 — the strip exists only while recording).
  final Duration? elapsed;

  /// Live input level in dBFS for the breathing dot.
  final double level;

  final VoidCallback onCancel;

  String get _elapsedLabel => elapsed == null
      ? '0:00'
      : '${elapsed!.inMinutes % 60}:${(elapsed!.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBoxKitGlassCard(
      wantNative: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // dBFS (-45 silence .. 0 full scale) → 0..1; the dot swells with
          // the input level — visible proof the audio is real.
          Builder(builder: (context) {
            final loudness = ((level + 45) / 45).clamp(0.0, 1.0);
            return Container(
              key: const ValueKey('composer-level-dot'),
              width: 8 + 10 * loudness,
              height: 8 + 10 * loudness,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
              ),
            );
          }),
          appBoxKitHorizontalSpaceSmall,
          Text(
            _elapsedLabel,
            style: TextStyle(color: scheme.onSurface, fontSize: 14),
          ),
          appBoxKitHorizontalSpaceXSmall,
          // The strip's one gesture: abort. The send lives on the trailing
          // stop button, so the label points at it.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Cancel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          appBoxKitHorizontalSpaceXSmall,
          Flexible(
            child: Text(
              '· tap stop to send',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One attach option: glyph + label + chevron, theme-ink text. The messenger
/// + menu idiom — a plain row, not a button chrome (see the build comment).
class _AttachOptionRow extends StatelessWidget {
  const _AttachOptionRow({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final AppBoxKitGlyph glyph;

  final String label;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(glyph.icon, size: 22, color: theme.colorScheme.primary),
            appBoxKitHorizontalSpaceSmall,
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
            Icon(AppBoxKitGlyphs.chevronRight.icon,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// One removable pending item above the field (content surfaces compose on
/// [AppBoxKitGlassCard]).
class _PendingChip extends StatelessWidget {
  const _PendingChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;

  final String label;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBoxKitGlassCard(
      // OPAQUE by tier: the frosted branch's opaqueGlass default is a
      // solid alpha-1.0 rounded fill. The native Liquid Glass tier is
      // pinned chrome — its "opaque" is a 0.45 tint that still reads
      // translucent, and content-layer glass is out of contract anyway
      // (ADR 0010; the recording strip does the same).
      wantNative: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          appBoxKitHorizontalSpaceXSmall,
          Text(label, style: TextStyle(color: scheme.onSurface, fontSize: 12)),
          // Plain (chromeless) — the glass circle reads as a button inside
          // the chip; the remove affordance is the bare glyph.
          AppBoxKitNativeIconButton(
            glyph: AppBoxKitGlyphs.close,
            size: 16,
            plain: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
