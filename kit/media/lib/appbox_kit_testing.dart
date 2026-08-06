/// Scriptable in-memory fakes for the appbox_kit_media ports — no plugins, no
/// OS, no MethodChannels. Drive streams and script outcomes from tests.
///
/// ```dart
/// final capture = FakeAppBoxKitMediaCaptureService(hasCamera: false);
/// capture.scriptedResult = const AppBoxKitMediaCapturePermissionDenied();
///
/// final rec = FakeAppBoxKitAudioRecorderService()..permission = false;
///
/// final player = FakeAppBoxKitAudioPlayerService();
/// player.drivePosition(const Duration(seconds: 3));
/// ```
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'appbox_kit_media.dart';

/// In-memory [AppBoxKitCapturedMedia]. [saveTo] writes [bytes] to disk so a caller that
/// moves the capture produces a real file the test can assert on.
class FakeAppBoxKitCapturedMedia implements AppBoxKitCapturedMedia {
  FakeAppBoxKitCapturedMedia(this.path, {this.name = 'fake.jpg', Uint8List? bytes})
      : _bytes = bytes ?? Uint8List(0);

  @override
  final String path;

  @override
  final String name;

  final Uint8List _bytes;

  /// Paths this handle was asked to save to.
  final List<String> savedTo = [];

  @override
  Future<void> saveTo(String destinationPath) async {
    savedTo.add(destinationPath);
    await File(destinationPath).writeAsBytes(_bytes);
  }

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

/// Scriptable [AppBoxKitMediaCaptureService]. Set [scriptedResult] to force any outcome;
/// otherwise a camera-on-no-camera returns unavailable and everything else
/// returns a [FakeAppBoxKitCapturedMedia].
class FakeAppBoxKitMediaCaptureService implements AppBoxKitMediaCaptureService {
  FakeAppBoxKitMediaCaptureService({this.hasCamera = true, this.scriptedResult});

  @override
  bool hasCamera;

  /// When non-null, [capturePhoto] returns this verbatim.
  AppBoxKitMediaCaptureResult? scriptedResult;

  /// Sources passed to [capturePhoto], in call order.
  final List<AppBoxKitMediaSource> requestedSources = [];

  @override
  Future<AppBoxKitMediaCaptureResult> capturePhoto({
    required AppBoxKitMediaSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    requestedSources.add(source);
    final scripted = scriptedResult;
    if (scripted != null) return scripted;
    if (source == AppBoxKitMediaSource.camera && !hasCamera) {
      return const AppBoxKitMediaCaptureUnavailable('fake: no camera');
    }
    return AppBoxKitMediaCaptured(FakeAppBoxKitCapturedMedia('/fake/photo.jpg'));
  }
}

/// Scriptable [AppBoxKitAudioRecorderService]. Drive [elapsed$]/[amplitude$] with
/// [driveElapsed]/[driveAmplitude]; script [hasPermission] via [permission] and
/// the [stop] return via [scriptedStopResult].
class FakeAppBoxKitAudioRecorderService implements AppBoxKitAudioRecorderService {
  FakeAppBoxKitAudioRecorderService({this.permission = true, this.scriptedStopResult});

  /// Value returned by [hasPermission].
  bool permission;

  /// When non-null, [stop] returns this; otherwise it returns the last started
  /// path (or a default) with the current [elapsed].
  AppBoxKitRecordingResult? scriptedStopResult;

  final StreamController<Duration?> _elapsed =
      StreamController<Duration?>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();

  bool _recording = false;
  Duration _elapsed$value = Duration.zero;

  /// Paths passed to [start], in call order (null = default temp path).
  final List<String?> startedPaths = [];

  @override
  Stream<Duration?> get elapsed$ => _elapsed.stream;

  @override
  Stream<double> get amplitude$ => _amplitude.stream;

  @override
  bool get isRecording => _recording;

  @override
  Duration get elapsed => _elapsed$value;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start({String? path}) async {
    startedPaths.add(path);
    _recording = true;
    _elapsed$value = Duration.zero;
    _elapsed.add(Duration.zero);
  }

  @override
  Future<AppBoxKitRecordingResult?> stop() async {
    _recording = false;
    _elapsed.add(null);
    if (scriptedStopResult != null) return scriptedStopResult;
    final path = startedPaths.isNotEmpty && startedPaths.last != null
        ? startedPaths.last!
        : '/fake/rec.m4a';
    return AppBoxKitRecordingResult(path: path, duration: _elapsed$value);
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    _elapsed.add(null);
  }

  /// Emit an elapsed tick (also updates the synchronous [elapsed]).
  void driveElapsed(Duration value) {
    _elapsed$value = value;
    _elapsed.add(value);
  }

  /// Emit an amplitude sample (dBFS).
  void driveAmplitude(double dbfs) => _amplitude.add(dbfs);

  @override
  Future<void> dispose() async {
    await _elapsed.close();
    await _amplitude.close();
  }
}

/// Scriptable [AppBoxKitAudioPlayerService]. Drive [position$]/[duration$]/[state$] with
/// [drivePosition]/[driveDuration]/[driveState]; [play]/[pause]/[stop] flip
/// [isPlaying] and emit a ready [AppBoxKitPlaybackState].
class FakeAppBoxKitAudioPlayerService implements AppBoxKitAudioPlayerService {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _duration =
      StreamController<Duration?>.broadcast();
  final StreamController<AppBoxKitPlaybackState> _state =
      StreamController<AppBoxKitPlaybackState>.broadcast();

  bool _playing = false;

  /// Paths passed to [setFilePath], in call order.
  final List<String> loadedPaths = [];

  @override
  Stream<Duration> get position$ => _position.stream;

  @override
  Stream<Duration?> get duration$ => _duration.stream;

  @override
  Stream<AppBoxKitPlaybackState> get state$ => _state.stream;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> setFilePath(String path) async {
    loadedPaths.add(path);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _emitState();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _emitState();
  }

  @override
  Future<void> seek(Duration position) async => _position.add(position);

  /// Emit a position update.
  void drivePosition(Duration value) => _position.add(value);

  /// Emit a duration update.
  void driveDuration(Duration? value) => _duration.add(value);

  /// Emit an explicit [AppBoxKitPlaybackState] (e.g. a completed state).
  void driveState(AppBoxKitPlaybackState value) => _state.add(value);

  void _emitState() => _state.add(
        AppBoxKitPlaybackState(
          playing: _playing,
          processing: AppBoxKitMediaProcessingState.ready,
        ),
      );

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _state.close();
  }
}

/// In-memory [AppBoxKitVideoPlayerService] — scriptable streams, recorded [load]s, no
/// render surface ([videoView] is an empty box).
class FakeAppBoxKitVideoPlayerService implements AppBoxKitVideoPlayerService {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _duration =
      StreamController<Duration?>.broadcast();
  final StreamController<AppBoxKitPlaybackState> _state =
      StreamController<AppBoxKitPlaybackState>.broadcast();

  bool _playing = false;

  /// Sources passed to [load], in call order.
  final List<String> loadedSources = [];

  /// Value returned by [aspectRatio]; `null` until set.
  double? scriptedAspectRatio;

  @override
  Stream<Duration> get position$ => _position.stream;

  @override
  Stream<Duration?> get duration$ => _duration.stream;

  @override
  Stream<AppBoxKitPlaybackState> get state$ => _state.stream;

  @override
  double? get aspectRatio => scriptedAspectRatio;

  @override
  Widget videoView() => const SizedBox.shrink();

  @override
  Future<void> load(String pathOrUrl) async {
    loadedSources.add(pathOrUrl);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _emitState();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _position.add(Duration.zero);
    _emitState();
  }

  @override
  Future<void> seek(Duration position) async => _position.add(position);

  /// Emit a position update.
  void drivePosition(Duration value) => _position.add(value);

  /// Emit a duration update.
  void driveDuration(Duration? value) => _duration.add(value);

  /// Emit an explicit [AppBoxKitPlaybackState] (e.g. a completed state).
  void driveState(AppBoxKitPlaybackState value) => _state.add(value);

  void _emitState() => _state.add(
        AppBoxKitPlaybackState(
          playing: _playing,
          processing: AppBoxKitMediaProcessingState.ready,
        ),
      );

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _state.close();
  }
}
