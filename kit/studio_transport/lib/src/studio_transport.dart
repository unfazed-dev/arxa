import 'dart:async';

import 'rust/api.dart' as rust;
import 'rust/frb_generated.dart';

/// Session lifecycle, as the app sees it.
///
/// [revoked] is terminal — the desktop refused (or revoked) the pairing
/// token and the user must scan a fresh QR code. [disconnected] means the
/// dial budget was exhausted or [StudioSession.close] was called;
/// [StudioSession.resume] can redial.
enum StudioSessionStatus { connecting, connected, reconnecting, revoked, disconnected }

/// One paired link phone <-> desktop.
abstract interface class StudioSession {
  /// Loopback HTTP proxy port while connected (`http://127.0.0.1:<port>/`),
  /// null otherwise. May change across reconnects — re-read it on every
  /// transition to [StudioSessionStatus.connected].
  int? get proxyPort;

  /// Lifecycle updates. Emits the current status immediately on listen,
  /// then every transition.
  Stream<StudioSessionStatus> get status;

  /// Register the OS push token (`platform`: `apns` | `fcm`). Re-sent to the
  /// desktop after every reconnect.
  Future<void> registerPushToken(String platform, String token);

  /// Redial after the app returns to the foreground (iOS suspends QUIC in
  /// the background, so the old connection is usually dead on resume).
  Future<void> resume();

  /// Tear the session down (connection, loopback proxy, endpoint).
  Future<void> close();
}

/// Entry point: turn a scanned QR payload into a live [StudioSession].
class StudioTransport {
  StudioTransport._();

  static bool _initialized = false;

  /// Loads the Rust library. Called implicitly by [connect]; call it early
  /// (e.g. in `main()`) to front-load the cost.
  static Future<void> init() async {
    if (_initialized) return;
    await RustLib.init();
    _initialized = true;
  }

  /// Parse `arxa-pair:<base32(json)>` and start dialing. Returns immediately;
  /// watch [StudioSession.status] for progress. Throws [FormatException] on a
  /// malformed pairing code.
  static Future<StudioSession> connect(String qrPayload, {String? deviceName}) async {
    await init();
    final rust.TransportSession inner;
    try {
      inner = rust.connect(qrPayload: qrPayload, deviceName: deviceName);
    } on String catch (e) {
      throw FormatException(e);
    } catch (e) {
      throw FormatException(e.toString());
    }
    return RustStudioSession._(inner);
  }
}

/// The real (FFI-backed) session. Exposed for type checks; construct only
/// via [StudioTransport.connect].
class RustStudioSession implements StudioSession {
  RustStudioSession._(this._inner);

  final rust.TransportSession _inner;

  @override
  int? get proxyPort => _inner.proxyPort;

  @override
  Stream<StudioSessionStatus> get status =>
      _inner.statusStream().map(_mapState);

  @override
  Future<void> registerPushToken(String platform, String token) async {
    _inner.registerPushToken(platform: platform, token: token);
  }

  @override
  Future<void> resume() async {
    _inner.resume();
  }

  @override
  Future<void> close() async {
    _inner.close();
  }

  static StudioSessionStatus _mapState(rust.TransportState s) => switch (s) {
        rust.TransportState.connecting => StudioSessionStatus.connecting,
        rust.TransportState.connected => StudioSessionStatus.connected,
        rust.TransportState.reconnecting => StudioSessionStatus.reconnecting,
        rust.TransportState.revoked => StudioSessionStatus.revoked,
        rust.TransportState.disconnected => StudioSessionStatus.disconnected,
      };
}
