import 'dart:async';

/// Connection lifecycle — mirrors the Tauri scaffold's `ConnectionStatus`
/// states (mobile/src/main.js): not-paired -> scanning -> pairing ->
/// connecting -> connected.
enum ArxaConnectionState { notPaired, scanning, pairing, connecting, connected }

class ArxaConnectionStatus {
  const ArxaConnectionStatus(this.state, {this.studioUrl, this.error});
  final ArxaConnectionState state;

  /// Loopback URL of the local proxy once connected —
  /// `http://127.0.0.1:<port>/`. Port is owned by the transport.
  final Uri? studioUrl;
  final String? error;
}

/// The transport seam. Port of the Tauri invoke surface
/// (`connection_status()`, `begin_pairing(ticket)`,
/// `set_push_token(platform, token)` — lib.rs:7-10). The real implementation
/// (iroh-backed, owns the loopback proxy) arrives from another workstream;
/// everything app-side depends only on this interface.
abstract class TransportService {
  ArxaConnectionStatus get current;
  Stream<ArxaConnectionStatus> get status;
  Future<void> beginPairing(String ticket);
  Future<void> setPushToken(String platform, String token);

  /// Unpair: drop stored NodeId + session token; callers also trigger the
  /// kit sign-out hook (auto-deregisters the push token).
  Future<void> unpair();

  /// Redial after the app returns to the foreground (iOS suspends QUIC in
  /// the background). No-op when there is no live session.
  Future<void> resume();

  /// Whether a pairing payload is stored — the retry seam's way to tell
  /// "dial again" from "nothing stored, scan a fresh QR".
  Future<bool> hasStoredPairing();
  Future<void> dispose();
}

/// In-memory fake: accepts any non-empty ticket, walks
/// pairing -> connecting -> connected on a short timer and serves a fixed
/// loopback port. Replaced by the iroh transport behind the same interface.
class FakeTransportService implements TransportService {
  FakeTransportService({this.port = 45890});

  final int port;
  final _controller = StreamController<ArxaConnectionStatus>.broadcast();
  ArxaConnectionStatus _current = const ArxaConnectionStatus(
    ArxaConnectionState.notPaired,
  );
  String? _pushPlatform;
  String? _pushToken;

  Uri get _studioUrl => Uri.parse('http://127.0.0.1:$port/');

  @override
  ArxaConnectionStatus get current => _current;

  @override
  Stream<ArxaConnectionStatus> get status => _controller.stream;

  void _emit(ArxaConnectionStatus s) {
    _current = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  @override
  Future<void> beginPairing(String ticket) async {
    if (ticket.trim().isEmpty) {
      _emit(
        const ArxaConnectionStatus(
          ArxaConnectionState.notPaired,
          error: 'Empty pairing ticket',
        ),
      );
      return;
    }
    _emit(const ArxaConnectionStatus(ArxaConnectionState.pairing));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _emit(const ArxaConnectionStatus(ArxaConnectionState.connecting));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _emit(
      ArxaConnectionStatus(
        ArxaConnectionState.connected,
        studioUrl: _studioUrl,
      ),
    );
  }

  @override
  Future<void> setPushToken(String platform, String token) async {
    _pushPlatform = platform;
    _pushToken = token;
  }

  /// Test hook — what the fake last received.
  (String, String)? get lastPushToken =>
      _pushPlatform == null ? null : (_pushPlatform!, _pushToken!);

  @override
  Future<void> unpair() async {
    _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired));
  }

  /// [resume] calls, for foreground-redial wiring tests.
  int resumeCount = 0;

  /// Whether a stored pairing exists — models the persisted payload;
  /// [resume] walks connecting -> connected only when set.
  bool storedPairing = false;

  @override
  Future<bool> hasStoredPairing() async => storedPairing;

  @override
  Future<void> resume() async {
    resumeCount += 1;
    // Model the redial: a resume of a connected fake re-announces connected
    // (the real transport walks reconnecting -> connected on a fresh epoch),
    // so heal logic waiting for re-establishment completes here.
    if (_current.state == ArxaConnectionState.connected) {
      _emit(_current);
      return;
    }
    // Model the cold-start dial (the retry path): a stored payload walks
    // connecting -> connected; without one, resume stays a no-op.
    if (!storedPairing) return;
    _emit(const ArxaConnectionStatus(ArxaConnectionState.connecting));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _emit(
      ArxaConnectionStatus(
        ArxaConnectionState.connected,
        studioUrl: _studioUrl,
      ),
    );
  }

  @override
  Future<void> dispose() async => _controller.close();
}
