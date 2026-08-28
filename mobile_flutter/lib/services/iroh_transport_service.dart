import 'dart:async';

import 'package:arxa_kit_studio_transport/arxa_kit_studio_transport.dart';

import 'transport_service.dart';

/// Signature of [StudioTransport.connect] — injectable so tests hand in
/// [MockStudioTransport.connect] and the FRB/native path is never touched
/// on the host. This file is the only app-side import of the transport kit.
typedef StudioConnect = Future<StudioSession> Function(String qrPayload,
    {String? deviceName});

/// Real [TransportService]: delegates to `arxa_kit_studio_transport`
/// (iroh-backed, owns the loopback proxy) behind the existing seam so
/// views/viewmodels are untouched.
///
/// Push-token contract: the transport re-sends the registered token to the
/// desktop after every reconnect *within* a session; this service stores the
/// last token and re-hands it to each *new* session (re-pair), so the desktop
/// always ends up with the current token.
class IrohTransportService implements TransportService {
  IrohTransportService({StudioConnect? connect, String? deviceName})
      : _connect = connect ?? StudioTransport.connect,
        _deviceName = deviceName;

  final StudioConnect _connect;
  final String? _deviceName;

  final _controller = StreamController<ArxaConnectionStatus>.broadcast();
  ArxaConnectionStatus _current =
      const ArxaConnectionStatus(ArxaConnectionState.notPaired);

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
      _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired,
          error: 'Empty pairing ticket'));
      return;
    }
    await _teardownSession();
    _emit(const ArxaConnectionStatus(ArxaConnectionState.pairing));
    final StudioSession session;
    try {
      session = await _connect(ticket, deviceName: _deviceName);
    } on FormatException catch (e) {
      _emit(ArxaConnectionStatus(ArxaConnectionState.notPaired,
          error: e.message.isEmpty ? 'Malformed pairing code' : e.message));
      return;
    }
    _session = session;
    _statusSub = session.status.listen(_onSessionStatus);
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
        _emit(ArxaConnectionStatus(ArxaConnectionState.connected,
            studioUrl:
                port == null ? null : Uri.parse('http://127.0.0.1:$port/')));
      case StudioSessionStatus.revoked:
        _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired,
            error: 'Pairing revoked by the desktop — scan a new QR code'));
      case StudioSessionStatus.disconnected:
        _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired,
            error: 'Connection lost'));
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
  Future<void> resume() async => _session?.resume();

  @override
  Future<void> unpair() async {
    await _teardownSession();
    _emit(const ArxaConnectionStatus(ArxaConnectionState.notPaired));
  }

  Future<void> _teardownSession() async {
    // Cancelling the FRB-backed status stream (and closing a revoked session)
    // has been observed to never complete, which wedged every subsequent
    // beginPairing() behind this await. Bound both so teardown always ends.
    final sub = _statusSub;
    _statusSub = null;
    if (sub != null) {
      await sub
          .cancel()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    final session = _session;
    _session = null;
    if (session != null) {
      await session
          .close()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }
  }

  @override
  Future<void> dispose() async {
    await _teardownSession();
    await _controller.close();
  }
}
