/// Coarse player lifecycle, kit-owned so callers never import a plugin's own
/// state enum. Maps 1:1 onto `just_audio`'s `ProcessingState`.
enum ArxaKitMediaProcessingState {
  /// No source loaded.
  idle,

  /// A source is being loaded/opened.
  loading,

  /// Buffering more data mid-stream.
  buffering,

  /// Ready to play (or playing).
  ready,

  /// Reached the end of the current source.
  completed,
}

/// Position and length of the current track — the scrubber pair. Kit-owned:
/// every player surface derives this the same way.
typedef ArxaKitPlaybackProgress = ({Duration position, Duration? duration});

/// A snapshot of a player's state: whether it is [playing] and where it is in
/// its [processing] lifecycle. Kit-owned to keep `just_audio` out of callers.
class ArxaKitPlaybackState {
  const ArxaKitPlaybackState({required this.playing, required this.processing});

  /// A convenient idle default (nothing loaded, not playing).
  static const idle = ArxaKitPlaybackState(
    playing: false,
    processing: ArxaKitMediaProcessingState.idle,
  );

  final bool playing;
  final ArxaKitMediaProcessingState processing;

  /// True once playback has run to the end of the source.
  bool get isCompleted => processing == ArxaKitMediaProcessingState.completed;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitPlaybackState &&
      other.playing == playing &&
      other.processing == processing;

  @override
  int get hashCode => Object.hash(playing, processing);

  @override
  String toString() =>
      'ArxaKitPlaybackState(playing: $playing, processing: $processing)';
}
