/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the composer demo's live thread — the
/// message list the input bar appends to, plus the contact's typing
/// indicator. Bubbles compose on [ArxaKitGlassCard] (content-surface
/// rule); the voice bubble plays back its fake recording with a
/// timer-driven [ArxaKitNativeProgress].
///
/// Requirements:
/// 1. [Input bar] — browse-the-components-gallery
/// Renders the conversation stream; send/attach/voice land here, and the
/// typing indicator shows while the fake contact composes a reply.
///
/// Relationships: takes the viewmodel's `messages` and `typing` streams —
/// no service or viewmodel import; the view wires them together.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_conversation_widget.dart
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_composer_models/models.dart';

class ShowcaseComponentsConversationWidget extends StatelessWidget {
  const ShowcaseComponentsConversationWidget({
    required this.messages,
    required this.typing,
    super.key,
  });

  final Stream<List<ShowcaseComposerMessageModel>> messages;

  /// True while the fake contact is composing a reply — rendered as a
  /// trailing indicator bubble.
  final Stream<bool> typing;

  String _timeOf(DateTime sentAt) =>
      '${sentAt.hour}:${sentAt.minute.toString().padLeft(2, '0')}';

  IconData _iconFor(ShowcaseComposerAttachmentKind kind) => switch (kind) {
        ShowcaseComposerAttachmentKind.camera => ArxaKitGlyphs.camera.icon,
        ShowcaseComposerAttachmentKind.photo => ArxaKitGlyphs.photo.icon,
        ShowcaseComposerAttachmentKind.file => ArxaKitGlyphs.folder.icon,
        ShowcaseComposerAttachmentKind.location =>
          ArxaKitGlyphs.locationPin.icon,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ArxaKitStreamBuilder<List<ShowcaseComposerMessageModel>>(
      stream: messages,
      builder: (_, list) => ArxaKitStreamBuilder<bool>(
        stream: typing,
        builder: (_, isTyping) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, message) in list.indexed)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : abxSize8),
                child: Align(
                  alignment: message.fromUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: ArxaKitGlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          switch (message) {
                            ShowcaseComposerTextMessageModel(:final text) =>
                              Text(
                                text,
                                style: TextStyle(color: scheme.onSurface),
                              ),
                            ShowcaseComposerAttachmentMessageModel(
                              :final attachment
                            ) =>
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_iconFor(attachment.kind),
                                      size: 20, color: scheme.primary),
                                  arxaKitHorizontalSpaceSmall,
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(attachment.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: scheme.onSurface,
                                                fontWeight: FontWeight.w600)),
                                        Text(attachment.detail,
                                            style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ShowcaseComposerVoiceMessageModel(
                              :final durationSeconds
                            ) =>
                              _VoiceBubbleBody(
                                  durationSeconds: durationSeconds),
                          },
                          arxaKitVerticalSpaceTiny,
                          Text(_timeOf(message.sentAt),
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (isTyping)
              Padding(
                padding: const EdgeInsets.only(top: abxSize8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TypingIndicatorBubble(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The contact's typing indicator — a small glass bubble with three dots
/// pulsing on staggered intervals while the reply composes.
class _TypingIndicatorBubble extends StatefulWidget {
  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ArxaKitGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // The dots pulse every frame for as long as the bubble is mounted:
      // confine the raster invalidation to the bubble so the conversation
      // list around it never repaints, and hoist the static label out of
      // the per-frame rebuild.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              arxaKitHorizontalSpaceXSmall,
              Text('typing…',
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          builder: (_, label) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final dot in const [0, 1, 2])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Opacity(
                    // Each dot peaks 200ms after the previous one.
                    opacity: (_controller.value * 3 - dot)
                                .clamp(0.0, 1.0)
                                .abs() <
                            0.5
                        ? 1.0
                        : 0.35,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              label!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Fake playback: play/pause drives a timer over the note's fixed duration.
class _VoiceBubbleBody extends StatefulWidget {
  const _VoiceBubbleBody({required this.durationSeconds});

  final int durationSeconds;

  @override
  State<_VoiceBubbleBody> createState() => _VoiceBubbleBodyState();
}

class _VoiceBubbleBodyState extends State<_VoiceBubbleBody> {
  static const _tick = Duration(seconds: 1);

  Timer? _timer;
  int _elapsed = 0;

  bool get _playing => _timer != null;
  bool get _finished => _elapsed >= widget.durationSeconds;

  void _toggle() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
    } else {
      if (_finished) setState(() => _elapsed = 0);
      _timer = Timer.periodic(_tick, (_) {
        if (_elapsed >= widget.durationSeconds) {
          _timer?.cancel();
          _timer = null;
        }
        setState(
            () => _elapsed = (_elapsed + 1).clamp(0, widget.durationSeconds));
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final remaining = widget.durationSeconds - _elapsed;
    final shown = _playing || _finished ? _elapsed : remaining;
    final minutes = shown ~/ 60;
    final seconds = shown % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArxaKitNativeIconButton(
          glyph: _playing ? ArxaKitGlyphs.pause : ArxaKitGlyphs.play,
          onPressed: _toggle,
        ),
        arxaKitHorizontalSpaceSmall,
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArxaKitNativeProgress.linear(
                value: widget.durationSeconds == 0
                    ? 0
                    : _elapsed / widget.durationSeconds,
              ),
              arxaKitVerticalSpaceTiny,
              Text(
                '$_label · voice note',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
