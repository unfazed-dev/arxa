/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for one section of the notes list — a labelled bucket
/// like "Pinned", "Today", or "Previous 7 Days" holding the notes that fall in it.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_notes_models/showcase_note_group_model.dart
library;

import 'showcase_note_model.dart';

class ShowcaseNoteGroup {
  /// The section heading shown in the list.
  final String label;

  /// The notes that belong to this section.
  final List<ShowcaseNoteModel> notes;

  const ShowcaseNoteGroup(this.label, this.notes);
}
