/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for the components-gallery composer demo's thread:
/// one sealed message (text / attachment / voice note) plus the draft the
/// input bar hands its host on send. Seeded entries are fake data.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_composer_models/showcase_composer_message_model.dart
library;

import 'showcase_composer_attachment_model.dart';

/// One message in the seeded composer thread.
sealed class ShowcaseComposerMessageModel {
  const ShowcaseComposerMessageModel({
    required this.fromUser,
    required this.sentAt,
  });

  /// True when the bubble renders on the user's side.
  final bool fromUser;

  /// Timestamp label source.
  final DateTime sentAt;
}

/// A plain text message.
final class ShowcaseComposerTextMessageModel
    extends ShowcaseComposerMessageModel {
  const ShowcaseComposerTextMessageModel({
    required this.text,
    required super.fromUser,
    required super.sentAt,
  });

  final String text;
}

/// An attachment picked from the (fake) attach sheet.
final class ShowcaseComposerAttachmentMessageModel
    extends ShowcaseComposerMessageModel {
  const ShowcaseComposerAttachmentMessageModel({
    required this.attachment,
    required super.fromUser,
    required super.sentAt,
  });

  final ShowcaseComposerAttachmentModel attachment;
}

/// A voice note captured by the kit recorder (hold-to-record).
final class ShowcaseComposerVoiceMessageModel
    extends ShowcaseComposerMessageModel {
  const ShowcaseComposerVoiceMessageModel({
    required this.durationSeconds,
    this.path,
    required super.fromUser,
    required super.sentAt,
  });

  final int durationSeconds;

  /// The recorded file (AAC-LC `.m4a` from the kit audio service), when the
  /// note came from a real recording.
  final String? path;
}

/// What the input bar hands its host when the user sends: the draft text, any
/// attachments picked from the attach sheet, and at most one voice note.
class ShowcaseComposerDraftModel {
  const ShowcaseComposerDraftModel({
    this.text = '',
    this.attachments = const [],
    this.voiceNoteSeconds,
    this.voiceNotePath,
  });

  final String text;
  final List<ShowcaseComposerAttachmentModel> attachments;
  final int? voiceNoteSeconds;

  /// The recording file behind [voiceNoteSeconds], when there is one.
  final String? voiceNotePath;

  bool get isEmpty =>
      text.trim().isEmpty && attachments.isEmpty && voiceNoteSeconds == null;
}
