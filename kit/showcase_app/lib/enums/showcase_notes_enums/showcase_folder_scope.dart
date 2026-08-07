/// Which slice of a user's notes the folder screen lists — parsed once from
/// the route's `:id` path param ([parse]); [key] round-trips back to the
/// route path value, so the wire format ('all'/'trash'/folder uuid in
/// paths) never changes.
sealed class ShowcaseFolderScope {
  const ShowcaseFolderScope();

  /// The route path value — 'all', 'trash', or a folder uuid.
  String get key;

  static ShowcaseFolderScope parse(String key) => switch (key) {
        'all' => const ShowcaseFolderScopeAll(),
        'trash' => const ShowcaseFolderScopeTrash(),
        _ => ShowcaseFolderScopeFolder(key),
      };
}

/// Every live note, unscoped.
final class ShowcaseFolderScopeAll extends ShowcaseFolderScope {
  const ShowcaseFolderScopeAll();

  @override
  String get key => 'all';
}

/// Recently Deleted.
final class ShowcaseFolderScopeTrash extends ShowcaseFolderScope {
  const ShowcaseFolderScopeTrash();

  @override
  String get key => 'trash';
}

/// One user folder.
final class ShowcaseFolderScopeFolder extends ShowcaseFolderScope {
  const ShowcaseFolderScopeFolder(this.folderId);

  final String folderId;

  @override
  String get key => folderId;
}
