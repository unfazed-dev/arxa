import 'showcase_note_model.dart';

/// One section of the notes list ("Pinned", "Today", "Previous 7 Days", …).
class ShowcaseNoteGroup {
  final String label;
  final List<ShowcaseNoteModel> notes;

  const ShowcaseNoteGroup(this.label, this.notes);
}
