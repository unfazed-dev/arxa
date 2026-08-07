/// The media adapter's hardware/IO ops — `.name` is the AppBoxKitAction hub
/// key (per-entity ops build dynamic keys from it: `playback.<id>`), [error]
/// is the error-snackbar copy for the op's AppBoxKitAction fallback.
enum ShowcaseNotesMediaOp {
  pickPhoto('Could not add photo'),
  startRecording('Could not start recording'),
  stopRecording('Could not save voice memo'),
  cancelRecording('Could not cancel recording'),
  playback('Could not play voice memo'),
  deleteFile('Could not delete attachment');

  const ShowcaseNotesMediaOp(this.error);

  /// Error snackbar copy; null where the op has no fallback copy.
  final String? error;
}
