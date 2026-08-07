import 'showcase_note_folder_model.dart';

/// Everything the folders screen needs, derived from two repository streams.
/// Counts are facade work — never query work (swap rule 2).
class ShowcaseNotesOverview {
  final List<ShowcaseNoteFolderModel> folders;
  final Map<String, int> liveCountByFolder;
  final int allCount;
  final int trashCount;

  const ShowcaseNotesOverview({
    required this.folders,
    required this.liveCountByFolder,
    required this.allCount,
    required this.trashCount,
  });
}

/// Everything the admin section needs: every owner's folders plus live note
/// counts, unfiltered. Showcase-only — the seed backend is fake and entirely
/// client-side, so this demonstrates role-gated *visibility*, not a security
/// boundary.
class ShowcaseNotesAdminOverview {
  final List<ShowcaseNoteFolderModel> folders;
  final Map<String, int> liveCountByFolder;

  const ShowcaseNotesAdminOverview({
    required this.folders,
    required this.liveCountByFolder,
  });
}
