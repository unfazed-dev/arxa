import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A completed recording: the file [path] and its measured [duration].
class RecordingResult {
  const RecordingResult({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

/// Single-track audio recording with an elapsed-time stream and a live
/// amplitude stream (for a level meter / waveform).
///
/// The service owns the elapsed clock — [elapsed$] emits `Duration.zero` on
/// [start], ticks while recording, and emits `null` when idle — so UIs can bind
/// to it directly instead of running their own timer.
abstract class AudioRecorderService {
  /// Elapsed recording time; `null` when not recording.
  Stream<Duration?> get elapsed$;

  /// Current input amplitude in dBFS (negative; 0 is full scale) while
  /// recording. Suitable for a level meter.
  Stream<double> get amplitude$;

  /// Whether a recording is in progress.
  bool get isRecording;

  /// Latest elapsed time (synchronous read of [elapsed$]).
  Duration get elapsed;

  /// Whether the app currently holds microphone permission (prompts if needed,
  /// following the plugin's behaviour).
  Future<bool> hasPermission();

  /// Begin recording. When [path] is null a temp `.m4a` file is used. The
  /// encoder is chosen by the implementation (native AAC-LC → `.m4a`); callers
  /// do not configure the codec.
  Future<void> start({String? path});

  /// Stop and finalize. Returns the recording, or `null` if nothing was
  /// captured.
  Future<RecordingResult?> stop();

  /// Abort and delete the in-progress file.
  Future<void> cancel();

  /// Release the recorder and close streams.
  Future<void> dispose();
}

/// [AudioRecorderService] backed by the native `record` plugin.
class RecordAudioRecorderService implements AudioRecorderService {
  RecordAudioRecorderService([AudioRecorder? recorder])
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Stopwatch _clock = Stopwatch();
  final StreamController<Duration?> _elapsed =
      StreamController<Duration?>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();

  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSub;

  @override
  Stream<Duration?> get elapsed$ => _elapsed.stream;

  @override
  Stream<double> get amplitude$ => _amplitude.stream;

  @override
  bool get isRecording => _clock.isRunning;

  @override
  Duration get elapsed => _clock.elapsed;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start({String? path}) async {
    final target = path ?? await _defaultPath();
    // Default RecordConfig encoder is aacLc → .m4a, matching iOS voice memos.
    // Kept internal so callers never import `record`'s RecordConfig.
    await _recorder.start(const RecordConfig(), path: target);
    _clock
      ..reset()
      ..start();
    _elapsed.add(Duration.zero);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _elapsed.add(_clock.elapsed),
    );
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 250))
        .listen((a) => _amplitude.add(a.current));
  }

  @override
  Future<RecordingResult?> stop() async {
    final path = await _recorder.stop();
    final elapsed = _stopClock();
    if (path == null) return null;
    return RecordingResult(path: path, duration: elapsed);
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel(); // deletes the in-progress file
    _stopClock();
  }

  Duration _stopClock() {
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final elapsed = _clock.elapsed;
    _elapsed.add(null);
    return elapsed;
  }

  Future<String> _defaultPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/rec_${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    await _amplitudeSub?.cancel();
    await _recorder.dispose();
    await _elapsed.close();
    await _amplitude.close();
  }
}
