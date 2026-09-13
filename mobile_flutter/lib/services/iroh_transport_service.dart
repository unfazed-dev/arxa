import 'dart:async';

import 'package:arxa_kit_studio_transport/arxa_kit_studio_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transport_service.dart';

/// Signature of [StudioTransport.connect] — injectable so tests hand in
/// [MockStudioTransport.connect] and the FRB/native path is never touched
/// on the host. This file is the only app-side import of the transport kit.
typedef StudioConnect =
    Future<StudioSession> Function(String qrPayload, {String? deviceName});

/// Real [TransportService]: delegates to `arxa_kit_studio_transport`
/// (iroh-backed, owns the loopback proxy) behind the existing seam so
/// views/viewmodels are untouched.
///
/// Push-token contract: the transport re-sends the registered token to the
/// desktop after every reconnect *within* a session; this service stores the
/// last token and re-hands it to each *new* session (re-pair), so the desktop
/// always ends up with the current token.
class IrohTransportService implements TransportService {
  IrohTransportService({StudioConnect? connect, this._deviceName})
    : _connect = connect ?? StudioTransport.connect;

  final StudioConnect _connect;
  final String? _deviceName;

  final _controller = StreamController<ArxaConnectionStatus>.broadcast();
  ArxaConnectionStatus _current = const ArxaConnectionStatus(
    ArxaConnectionState.notPaired,
  );

  StudioSession? _session;
  StreamSubscription<StudioSessionStatus>? _statusSub;

  String? _pushPlatform;
  String? _pushToken;

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
    await _teardownSession();
    _emit(const ArxaConnectionStatus(ArxaConnectionState.pairing));
    final StudioSession session;
    try {
      session = await _connect(ticket, deviceName: _deviceName);
    } on FormatException catch (e) {
      _emit(
        ArxaConnectionStatus(
          ArxaConnectionState.notPaired,
          error: e.message.isEmpty ? 'Malformed pairing code' : e.message,
        ),
      );
      return;
    } on Object {
      // Dial failed (desktop unreachable, relay down). Without this emit the
      // status would sit on 'pairing' forever and listeners would never
      // leave the connecting/session screens.
      _emit(
        const ArxaConnectionStatus(
          ArxaConnectionState.notPaired,
          error: 'Could not reach the studio — scan a new QR code',
        ),
      );
      return;
    }
    _session = session;
    _statusSub = session.status.listen(_onSessionStatus);
    // Persist the payload for cold-start resume: the desktop accepts the
    // pairing token for reconnects (authorize step 2), so re-running this
    // payload after a process restart restores the link silently.
    unawaited(_persistPayload(ticket));
    // Re-hand the stored token to the fresh session (once per session — the
    // transport itself re-sends it on every reconnect from here on).
    final platform = _pushPlatform;
    final token = _pushToken;
    if (platform != null && token != null) {
      await session.registerPushToken(platform, token);
    }
  }

  void _onSessionStatus(StudioSessionStatus s) {
    switch (s) {
      case StudioSessionStatus.connecting:
      case StudioSessionStatus.reconnecting:
        _emit(const ArxaConnectionStatus(ArxaConnectionState.connecting));
      case StudioSessionStatus.connected:
        final port = _session?.proxyPort;
        _emit(
          ArxaConnectionStatus(
            ArxaConnectionState.connected,
            studioUrl: port == null
                ? null
                : Uri.parse('http://127.0.0.1:$port/'),
          ),
        );
      case StudioSessionStatus.revoked:
        // The desktop killed this token — a stored payload is now useless.
        unawaited(_wipePayload());
        _emit(
          const ArxaConnectionStatus(
            ArxaConnectionState.notPaired,
            error: 'Pairing revoked by the desktop — scan a new QR code',
          ),
        );
      case StudioSessionStatus.disconnected:
        _emit(
          const ArxaConnectionStatus(
            ArxaConnectionState.notPaired,
            error: 'Connection lost',
          ),
        );
    }
  }

  @override
  Future<void> setPushToken(String platform, String token) async {
    _pushPlatform = platform;
    _pushToken = token;
    // Hand to the live session (if any) exactly once; the transport re-sends
    // it per-connection. New sessions get it in [beginPairing].
    await _session?.registerPushToken(platform, token);
  }

  @override
  Future<void> resume() async {
    final session = _session;
    if (session != null) {
      await session.resume();
      return;
    }
    // Cold start: no live session in this process. Re-run the stored
    // pairing payload — the desktop's authorize step 2 accepts the pairing
    // token for reconnects, so this restores the link with no user action.
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(storedPayloadKey);
      if (payload != null && payload.isNotEmpty) {
        await beginPairing(payload);
      }
    } on Object {
      // Storage trouble at boot must never crash the app.
    }
  }

  @override
  Future<void> unpair() async {
    await _teardownSession();
    await _wipePayload();
    _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired));
  }

  /// The scanned `arxa-pair:` payload, kept so [resume] can restore the
  /// pairing after a full process restart. Public (with [hasStoredPairing])
  /// so main() can pick the startup route without a second copy of the key.
  static const storedPayloadKey = 'pairing.studio_payload_v1';

  /// Whether a pairing payload is stored. main() reads this before runApp
  /// to land paired users straight in the studio instead of flashing the
  /// QR scanner while the cold-start resume dials. (The instance member of
  /// the same contract is the TransportService seam — Dart forbids a static
  /// and an instance member sharing a name, so the static carries -Exists.)
  static Future<bool> storedPairingExists() => _readStoredPairing();

  @override
  Future<bool> hasStoredPairing() => _readStoredPairing();

  static Future<bool> _readStoredPairing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(storedPayloadKey);
      return payload != null && payload.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<void> _persistPayload(String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storedPayloadKey, payload);
    } on Object {
      // Storage failure must never break an in-flight pairing.
    }
  }

  Future<void> _wipePayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storedPayloadKey);
    } on Object {
      // Nothing to do — a leftover payload is harmless (desktop still
      // validates it against its peer table).
    }
  }

  Future<void> _teardownSession() async {
    // Cancelling the FRB-backed status stream (and closing a revoked session)
    // has been observed to never complete, which wedged every subsequent
    // beginPairing() behind this await. Bound both so teardown always ends.
    final sub = _statusSub;
    _statusSub = null;
    if (sub != null) {
      await sub.cancel().timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    final session = _session;
    _session = null;
    if (session != null) {
      await session.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _teardownSession();
    await _controller.close();
  }
}
