import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../audio/playback_state.dart';

/// Single-source video playback.
///
/// One instance plays one source at a time; loading a new source replaces the
/// current one. Callers bind to [position$]/[duration$]/[state$] for
/// scrubbers and play/pause chrome, and render via [videoView].
///
/// Backed by `video_player` (AVPlayer / ExoPlayer); the kit-owned
/// [PlaybackState] keeps the plugin's value types out of callers.
abstract class VideoPlayerService {
  /// Current playback position.
  Stream<Duration> get position$;

  /// Duration of the loaded source; `null` until known.
  Stream<Duration?> get duration$;

  /// Player lifecycle + playing flag.
  Stream<PlaybackState> get state$;

  /// Aspect ratio (width / height) of the loaded video; `null` until known.
  double? get aspectRatio;

  /// The render surface for the loaded video. Sized to the video's aspect
  /// ratio; until a source is initialized this is an empty box.
  Widget videoView();

  /// Load a local file or network URL, replacing any current source.
  Future<void> load(String pathOrUrl);

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

/// [VideoPlayerService] backed by the native `video_player` plugin.
///
/// `video_player` exposes a `ValueNotifier` controller rather than streams,
/// so each [load] bridges controller notifications onto broadcast streams.
class PluginVideoPlayerService implements VideoPlayerService {
  VideoPlayerController? _controller;

  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _duration =
      StreamController<Duration?>.broadcast();
  final StreamController<PlaybackState> _state =
      StreamController<PlaybackState>.broadcast();

  void _forward() {
    final value = _controller?.value;
    if (value == null) return;
    _position.add(value.position);
    _duration.add(value.isInitialized ? value.duration : null);
    _state.add(toState(value));
  }

  /// Maps the plugin's value snapshot onto the kit-owned [PlaybackState].
  @visibleForTesting
  static PlaybackState toState(VideoPlayerValue value) {
    if (!value.isInitialized) {
      return const PlaybackState(
        playing: false,
        processing: MediaProcessingState.loading,
      );
    }
    if (value.isBuffering) {
      return PlaybackState(
        playing: value.isPlaying,
        processing: MediaProcessingState.buffering,
      );
    }
    final completed = value.isCompleted ||
        (value.duration > Duration.zero &&
            !value.isPlaying &&
            value.position >= value.duration);
    return PlaybackState(
      playing: value.isPlaying,
      processing: completed
          ? MediaProcessingState.completed
          : MediaProcessingState.ready,
    );
  }

  @override
  Stream<Duration> get position$ => _position.stream;

  @override
  Stream<Duration?> get duration$ => _duration.stream;

  @override
  Stream<PlaybackState> get state$ => _state.stream;

  @override
  double? get aspectRatio {
    final value = _controller?.value;
    return value != null && value.isInitialized ? value.aspectRatio : null;
  }

  @override
  Widget videoView() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  @override
  Future<void> load(String pathOrUrl) async {
    final old = _controller;
    if (old != null) {
      old.removeListener(_forward);
      await old.dispose();
    }
    final isNetwork =
        pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
    final controller = isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(pathOrUrl))
        : VideoPlayerController.file(File(pathOrUrl));
    _controller = controller;
    controller.addListener(_forward);
    await controller.initialize();
    _forward();
  }

  @override
  Future<void> play() => _controller?.play() ?? Future.value();

  @override
  Future<void> pause() => _controller?.pause() ?? Future.value();

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    await controller.seekTo(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) =>
      _controller?.seekTo(position) ?? Future.value();

  @override
  Future<void> dispose() async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      old.removeListener(_forward);
      await old.dispose();
    }
    unawaited(_position.close());
    unawaited(_duration.close());
    unawaited(_state.close());
  }
}

/// Placeholder [VideoPlayerService]. Every member throws — kept for callers
/// that want video to fail loudly rather than silently no-op.
class StubVideoPlayerService implements VideoPlayerService {
  static const _todo =
      'appbox_kit_media: StubVideoPlayerService throws by design — '
      'use PluginVideoPlayerService for real playback.';

  @override
  Stream<Duration> get position$ => throw UnimplementedError(_todo);

  @override
  Stream<Duration?> get duration$ => throw UnimplementedError(_todo);

  @override
  Stream<PlaybackState> get state$ => throw UnimplementedError(_todo);

  @override
  double? get aspectRatio => throw UnimplementedError(_todo);

  @override
  Widget videoView() => throw UnimplementedError(_todo);

  @override
  Future<void> load(String pathOrUrl) => throw UnimplementedError(_todo);

  @override
  Future<void> play() => throw UnimplementedError(_todo);

  @override
  Future<void> pause() => throw UnimplementedError(_todo);

  @override
  Future<void> stop() => throw UnimplementedError(_todo);

  @override
  Future<void> seek(Duration position) => throw UnimplementedError(_todo);

  @override
  Future<void> dispose() => throw UnimplementedError(_todo);
}
