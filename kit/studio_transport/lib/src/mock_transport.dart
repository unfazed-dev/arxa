import 'dart:async';

import 'studio_transport.dart';

/// In-memory [StudioSession] for app tests — no Rust, no network.
///
/// Drive it from the test body:
/// ```dart
/// final mock = MockStudioSession();
/// mock.emit(StudioSessionStatus.connected, proxyPort: 8080);
/// ```
class MockStudioSession implements StudioSession {
  MockStudioSession({StudioSessionStatus initial = StudioSessionStatus.connecting})
      : _current = initial;

  final _controller = StreamController<StudioSessionStatus>.broadcast();
  StudioSessionStatus _current;
  int? _proxyPort;

  /// Push tokens the app registered, in order — assert on these.
  final List<(String platform, String token)> registeredPushTokens = [];

  /// Number of [resume] calls — assert reconnect-on-foreground wiring.
  int resumeCount = 0;

  bool closed = false;

  /// Drive the session from a test.
  void emit(StudioSessionStatus status, {int? proxyPort}) {
    _current = status;
    _proxyPort = status == StudioSessionStatus.connected ? proxyPort : null;
    _controller.add(status);
  }

  @override
  int? get proxyPort => _proxyPort;

  @override
  Stream<StudioSessionStatus> get status async* {
    yield _current; // replay current state on listen, like the real one
    yield* _controller.stream;
  }

  @override
  Future<void> registerPushToken(String platform, String token) async {
    registeredPushTokens.add((platform, token));
  }

  @override
  Future<void> resume() async {
    resumeCount += 1;
    if (_current != StudioSessionStatus.revoked && !closed) {
      emit(StudioSessionStatus.reconnecting);
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    emit(StudioSessionStatus.disconnected);
    await _controller.close();
  }
}

/// Factory mirroring [StudioTransport.connect] for dependency-injected apps.
class MockStudioTransport {
  MockStudioTransport();

  /// Sessions handed out, in order.
  final List<MockStudioSession> sessions = [];

  /// QR payloads passed to [connect], in order.
  final List<String> connectedPayloads = [];

  Future<StudioSession> connect(String qrPayload, {String? deviceName}) async {
    connectedPayloads.add(qrPayload);
    final session = MockStudioSession();
    sessions.add(session);
    return session;
  }
}
