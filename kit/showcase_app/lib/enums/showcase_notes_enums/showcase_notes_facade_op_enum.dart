/// The Notes facade's mutation ops — `.name` is the AppBoxKitAction hub key
/// (visible to other layers; the wire format must not change), [error] and
/// [success] are the snackbar copy shown by the action chain (destructive
/// ops also confirm with a success snackbar; the rest get `success: null`).
enum ShowcaseNotesFacadeOp {
  create('Could not create note'),
  save('Could not save note'),
  pin('Could not update note'),
  attach('Could not add attachment'),
  detach('Could not remove attachment'),
  trash('Could not move note to Recently Deleted',
      success: 'Moved to Recently Deleted'),
  restore('Could not restore note'),
  move('Could not move note'),
  purge('Could not delete note', success: 'Note deleted'),
  emptyTrash('Could not empty Recently Deleted',
      success: 'Recently Deleted emptied'),
  folderCreate('Could not create folder'),
  folderRename('Could not rename folder'),
  folderDelete('Could not delete folder', success: 'Folder deleted'),
  signOut('Could not sign out');

  const ShowcaseNotesFacadeOp(this.error, {this.success});

  /// Error snackbar copy.
  final String error;

  /// Success snackbar copy for destructive ops; null otherwise.
  final String? success;
}
