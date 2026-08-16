/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for one attachment picked in the components-gallery
/// composer demo — seeded/fake data (no real pickers): the name and detail are
/// the fake metadata the attach sheet produces per kind.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_composer_models/showcase_composer_attachment_model.dart
library;

/// What the user picked in the attach sheet.
enum ShowcaseComposerAttachmentKind { camera, photo, file, location }

class ShowcaseComposerAttachmentModel {
  /// Which attach option produced this.
  final ShowcaseComposerAttachmentKind kind;

  /// Fake display name, e.g. 'IMG_2231.jpg'.
  final String name;

  /// Fake metadata line, e.g. '2.4 MB · Photo'.
  final String detail;

  const ShowcaseComposerAttachmentModel({
    required this.kind,
    required this.name,
    required this.detail,
  });
}
