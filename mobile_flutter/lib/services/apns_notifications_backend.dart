// Raw-APNs notifications backend (D68 phone leg). App-owned on purpose:
// ADR-0037 keeps every provider rail app-side, never in the kit — the kit
// sees only ArxaKitNotificationsService. Talks to the Runner-side ApnsBridge
// (ios/Runner/AppDelegate.swift) over the bidirectional method channel
// `arxa/apns`; no Firebase in the path (cairn-push's ApnsRail + the
// operator's .p8 deliver the doorbell).

import 'dart:async';

import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:flutter/services.dart';

class ApnsNotificationsBackend implements ArxaKitNotificationsService {
  ApnsNotificationsBackend() {
    _channel.setMethodCallHandler(_onNativeCall);
    // Cold-start drain: a tap that cold-launched the app was buffered
    // native-side (Dart had no handler yet → the live 'event' got a null
    // reply). Read-and-clear it once the handler above is live.
    unawaited(_drainPendingTap());
    // Same discipline for a silent doorbell wake that cold-launched us
    // (B2 phase-1b): drain, emit, and acknowledge to iOS.
    unawaited(_drainPendingSilentWake());
    // ponytail: token rotation is POLLED (5s, distinct), not event-pushed —
    // an APNs device token is stable for an installed build; a native event
    // channel is the upgrade if mid-session rotation ever matters.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _emitDistinct());
  }

  static const MethodChannel _channel = MethodChannel('arxa/apns');

  final _messages = StreamController<ArxaKitRemoteMessage>.broadcast();
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  final _tokens = StreamController<ArxaKitPushToken>.broadcast();
  final _silentWakes = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _poll;
  String? _lastEmitted;
  String? _lastTapId;

  /// Notification taps (native didReceive): route to the approvals shell.
  Stream<Map<String, dynamic>> get taps => _taps.stream;

  /// Silent (content-available) doorbell wakes (B2 phase-1b): the app was
  /// woken by APNs in the background — resume the tunnel and let sync + the
  /// doorbell do their work, then acknowledge via [completeSilentWake].
  Stream<Map<String, dynamic>> get silentWakes => _silentWakes.stream;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'event') return null;
    final args =
        (call.arguments as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (args['type'] == 'tap') {
      _emitTap(args);
      return null;
    }
    if (args['type'] == 'silentWake') {
      _silentWakes.add(args);
      return null;
    }
    // willPresent: the system presented a push while foregrounded — the
    // D68 buzz assert listens here.
    _messages.add(
      ArxaKitRemoteMessage(
        receivedAt: DateTime.now(),
        title: args['title'] as String?,
        body: args['body'] as String?,
        data: args,
      ),
    );
    return null;
  }

  @override
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } on PlatformException {
      // Older native half — the handler binding in the constructor is the
      // real initialization; never block boot on it.
    } on MissingPluginException {
      // Non-iOS host running this file directly (never registered there in
      // practice — AppNotificationsBackend switches on platform).
    }
  }

  @override
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request =
        const ArxaKitNotificationPermissionRequest(),
  ]) async {
    final status = await _invoke<String>('requestPermission', {
      'alert': request.alert,
      'badge': request.badge,
      'sound': request.sound,
    });
    unawaited(_emitDistinct());
    return ArxaKitNotificationPermissionResult(_auth(status));
  }

  @override
  Future<ArxaKitNotificationPermissionResult> permissionStatus() async {
    return ArxaKitNotificationPermissionResult(
      _auth(await _invoke<String>('permissionStatus')),
    );
  }

  @override
  Stream<ArxaKitPushToken> get tokenStream => _tokens.stream;

  @override
  Future<ArxaKitPushToken?> currentToken() async {
    // Registration completes asynchronously after the permission ask, and
    // ArxaKitCairnPushBridge.attach() reads currentToken exactly once — so
    // poll the native token for a bounded window before admitting null.
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (true) {
      final token = await _nativeToken();
      if (token != null) return token;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Stream<ArxaKitRemoteMessage> get foregroundMessages => _messages.stream;

  @override
  Future<void> showLocalNotification(
    ArxaKitLocalNotification notification,
  ) async {
    await _invoke<void>('showLocalNotification', {
      'id': notification.id,
      'title': notification.title,
      'body': notification.body,
      'payload': notification.payload,
      'badge': notification.badgeCount,
    });
  }

  /// Tell iOS the silent wake's work is done (frees the ~30s fetch budget).
  Future<void> completeSilentWake() => _invoke<void>('silentWakeDone');

  @override
  Future<void> cancel(int id) async => _invoke<void>('cancel', {'id': id});

  @override
  Future<void> cancelAll() async => _invoke<void>('cancelAll');

  @override
  Future<void> setBadgeCount(int count) async =>
      _invoke<void>('setBadgeCount', {'count': count});

  @override
  Future<void> clearBadge() async => _invoke<void>('clearBadge');

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    await _messages.close();
    await _taps.close();
    await _tokens.close();
    await _silentWakes.close();
  }

  static ArxaKitNotificationAuthorization _auth(String? raw) => switch (raw) {
    'authorized' => ArxaKitNotificationAuthorization.authorized,
    'provisional' => ArxaKitNotificationAuthorization.provisional,
    'denied' => ArxaKitNotificationAuthorization.denied,
    _ => ArxaKitNotificationAuthorization.notDetermined,
  };

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _drainPendingTap() async {
    final tap = await _invoke<Map<dynamic, dynamic>>('pendingTap');
    if (tap == null) return;
    _emitTap(tap.cast<String, dynamic>());
  }

  /// Drain a silent wake that cold-launched the app: emit for the listeners
  /// (main resumes the tunnel on it) and acknowledge the fetch to iOS.
  Future<void> _drainPendingSilentWake() async {
    final pending = await _invoke<bool>('pendingSilentWake');
    if (pending != true) return;
    _silentWakes.add(const {'type': 'silentWake'});
    await completeSilentWake();
  }

  /// Emits a tap, deduped by requestId: on cold start BOTH the live
  /// 'event' and the drain can carry the same buffered notification —
  /// the first emission wins, the repeat is dropped.
  void _emitTap(Map<String, dynamic> tap) {
    final id = tap['requestId'] as String?;
    if (id != null) {
      if (_lastTapId == id) return;
      _lastTapId = id;
    }
    _taps.add(tap);
  }

  Future<ArxaKitPushToken?> _nativeToken() async {
    final value = await _invoke<String>('getToken');
    if (value == null || value.isEmpty) return null;
    return ArxaKitPushToken(
      value: value,
      issuedAt: DateTime.now(),
      provider: ArxaKitPushProvider.apns,
    );
  }

  Future<void> _emitDistinct() async {
    final token = await _nativeToken();
    if (token == null) return;
    if (_lastEmitted == token.value) return;
    _lastEmitted = token.value;
    _tokens.add(token);
  }
}
