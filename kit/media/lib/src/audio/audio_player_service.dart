import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'playback_state.dart';

/// Single-track audio playback with position/duration/state streams.
///
/// One instance plays one source at a time; loading a new file replaces the
/// current one. Callers bind to [position$]/[duration$]/[state$] for scrubbers
/// and play/pause chrome.
abstract class AudioPlayerService {
  /// Current playback position, updated as playback advances.
  Stream<Duration> get position$;

  /// Duration of the loaded source; `null` until known.
  Stream<Duration?> get duration$;

  /// Player lifecycle + playing flag.
  Stream<PlaybackState> get state$;

  /// Synchronous read of whether audio is currently playing.
  bool get isPlaying;

  /// Load a local file, replacing any current source.
  Future<void> setFilePath(String path);

  /// Start (or resume) playback.
  Future<void> play();

  /// Pause, keeping the position.
  Future<void> pause();

  /// Stop and reset to the start.
  Future<void> stop();

  /// Seek within the loaded source.
  Future<void> seek(Duration position);

  /// Release the player and close streams.
  Future<void> dispose();
}

/// [AudioPlayerService] backed by the native `just_audio` plugin.
class JustAudioPlayerService implements AudioPlayerService {
  JustAudioPlayerService([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get position$ => _player.positionStream;

  @override
  Stream<Duration?> get duration$ => _player.durationStream;

  @override
  Stream<PlaybackState> get state$ => _player.playerStateStream.map(_toState);

  @override
  bool get isPlaying => _player.playing;

  @override
  Future<void> setFilePath(String path) async {
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() async {
    // just_audio's play() future completes only when playback *finishes*;
    // callers expect play() to return once playback has *started*, so the
    // returned future is intentionally not awaited.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();

  static PlaybackState _toState(PlayerState s) => PlaybackState(
        playing: s.playing,
        processing: switch (s.processingState) {
          ProcessingState.idle => MediaProcessingState.idle,
          ProcessingState.loading => MediaProcessingState.loading,
          ProcessingState.buffering => MediaProcessingState.buffering,
          ProcessingState.ready => MediaProcessingState.ready,
          ProcessingState.completed => MediaProcessingState.completed,
        },
      );
}
