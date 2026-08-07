/// A model is a pure data class representing a domain entity — fields and
/// serialization only, no behavior, no Flutter, no services.
///
/// This is the data shape for the folders screen — the folder list plus live
/// note counts, all derived from repository streams (counts are facade work,
/// never query work). The file also holds the admin overview: every owner's
/// folders and live counts, unfiltered — showcase-only, since the seed backend
/// is fake and entirely client-side, so it demonstrates role-gated *visibility*,
/// not a security boundary.
///
/// History: git log --follow -- kit/showcase_app/lib/data/models/showcase_notes_models/showcase_notes_overview_model.dart
library;

import 'showcase_note_folder_model.dart';

class ShowcaseNotesOverview {
  /// The user's folders.
  final List<ShowcaseNoteFolderModel> folders;

  /// Live (non-deleted) note count per folder id.
  final Map<String, int> liveCountByFolder;

  /// Total live notes across all folders.
  final int allCount;

  /// How many notes are in Recently Deleted.
  final int trashCount;

  const ShowcaseNotesOverview({
    required this.folders,
    required this.liveCountByFolder,
    required this.allCount,
    required this.trashCount,
  });
}

class ShowcaseNotesAdminOverview {
  /// Every owner's folders, unfiltered.
  final List<ShowcaseNoteFolderModel> folders;

  /// Live note count per folder id, across all owners.
  final Map<String, int> liveCountByFolder;

  const ShowcaseNotesAdminOverview({
    required this.folders,
    required this.liveCountByFolder,
  });
}
