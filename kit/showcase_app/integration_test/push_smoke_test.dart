// Phase 5d — the REAL-rail FCM push smoke, device leg. Driven by
// kit/cairn/tool/push_smoke.sh (the script owns the server, the trigger row,
// and both assertions); this binary is the device half:
//
//   Firebase init → permission → FCM token → the kit's notifications seam →
//   ArxaKitCairnBackend (sync mode, push: true) attaches the push bridge →
//   token lands in the server's registry → first sync → pauseSync (doorbells
//   target OFFLINE accounts) → PUSH_SMOKE_READY → the script inserts a row
//   → cairn-server doorbell → FCM data message → PUSH_SMOKE_RECEIVED.
//
// What it proves that 4g's fake-seam tests cannot: a REAL FCM token round-
// tripping through the kit's bridge into a REAL cairn-server push registry,
// and the doorbell coming back down the REAL FCM rail.
//
// Marker protocol (the script greps this process's log):
//   PUSH_SMOKE_READY             — token registered, first sync done, offline
//   PUSH_SMOKE_RECEIVED=<data>   — the doorbell arrived in the foreground
//   PUSH_SMOKE_TIMEOUT           — bounded wait elapsed (script fails itself)
//
// Never runs without the script: the dart-defines it needs come from
// tool/push_smoke.sh. Android emulator automated; physical iPhone manual
// (the iOS simulator cannot receive real FCM — see the script header).

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';

const _syncUrl = String.fromEnvironment('CAIRN_SYNC_URL');
const _smokeToken = String.fromEnvironment('CAIRN_SMOKE_TOKEN');
const _table =
    String.fromEnvironment('PUSH_SMOKE_TABLE', defaultValue: 'push_smoke_pings');

/// The smoke's trigger row — script-owned table, device only subscribes.
class _Ping {
  const _Ping({required this.id, this.note});
  final String id;
  final String? note;

  factory _Ping.fromJson(Map<String, dynamic> json) => _Ping(
        id: (json['_pk'] ?? json['id'] ?? '') as String,
        note: json['note'] as String?,
      );
  static Map<String, dynamic> toRow(_Ping p) => {'id': p.id, 'note': p.note};
}

const _pingSchema = ArxaKitTableSchema(
  table: _table,
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('user_id', ArxaKitColumnType.text, nullable: true),
    ArxaKitColumn('note', ArxaKitColumnType.text, nullable: true),
  ],
);

/// The app-side rail the kit deliberately does not own: firebase_messaging
/// behind the kit/notifications seam. Smoke-scoped — the token/permission/
/// foreground-message members are real; local-notification members are out
/// of scope for the doorbell rail and throw.
class _FcmNotificationsService implements ArxaKitNotificationsService {
  final _messaging = FirebaseMessaging.instance;
  final _tokens = StreamController<ArxaKitPushToken>.broadcast();

  @override
  Future<void> initialize() async {
    FirebaseMessaging.instance.onTokenRefresh
        .listen((value) => _tokens.add(_token(value)));
  }

  ArxaKitPushToken _token(String value) => ArxaKitPushToken(
        value: value,
        issuedAt: DateTime.now(),
        provider: ArxaKitPushProvider.fcm,
      );

  @override
  Future<ArxaKitNotificationPermissionResult> requestPermission([
    ArxaKitNotificationPermissionRequest request =
        const ArxaKitNotificationPermissionRequest(),
  ]) async {
    final res = await _messaging.requestPermission();
    final status = switch (res.authorizationStatus) {
      AuthorizationStatus.authorized => ArxaKitNotificationAuthorization.authorized,
      AuthorizationStatus.provisional => ArxaKitNotificationAuthorization.provisional,
      AuthorizationStatus.notDetermined => ArxaKitNotificationAuthorization.notDetermined,
      _ => ArxaKitNotificationAuthorization.denied,
    };
    return ArxaKitNotificationPermissionResult(status);
  }

  @override
  Future<ArxaKitPushToken?> currentToken() async {
    final value = await _messaging.getToken();
    return value == null ? null : _token(value);
  }

  @override
  Stream<ArxaKitPushToken> get tokenStream => _tokens.stream;

  @override
  Stream<ArxaKitRemoteMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage.map((m) => ArxaKitRemoteMessage(
            receivedAt: DateTime.now(),
            data: m.data,
          ));

  // Out of smoke scope — the doorbell rail never touches local notifications.
  @override
  Future<ArxaKitNotificationPermissionResult> permissionStatus() =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> showLocalNotification(ArxaKitLocalNotification notification) =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> cancel(int id) =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> cancelAll() =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> setBadgeCount(int count) =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> clearBadge() =>
      throw UnimplementedError('smoke-scoped: doorbell rail only');
  @override
  Future<void> dispose() => _tokens.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('kit.cairn.push-smoke — real FCM doorbell reaches the device',
      (tester) async {
    expect(_syncUrl, isNotEmpty,
        reason: 'driven by kit/cairn/tool/push_smoke.sh (--dart-define)');
    expect(_smokeToken, isNotEmpty, reason: 'minted by the script');

    // The provider rail (app-side by design): Firebase init reads the
    // operator-dropped native config (google-services.json /
    // GoogleService-Info.plist — conditionally applied, see build.gradle.kts).
    await Firebase.initializeApp();
    final notifications = _FcmNotificationsService();
    await notifications.initialize();
    final permission = await notifications.requestPermission();
    expect(permission.status, ArxaKitNotificationAuthorization.authorized,
        reason: 'the emulator grants; first-ever run may need one Allow tap');

    // The kit under test: backend + push bridge over the REAL engine.
    final backend = ArxaKitCairnBackend(
      config: const ArxaKitCairnConfig(
        mode: ArxaKitCairnMode.sync,
        syncUrl: _syncUrl,
        push: true,
      ),
      tokenProvider: () async => _smokeToken,
      notifications: notifications,
    );
    await backend.initialize(
      const ArxaKitDataConfig(),
      [
        const ArxaKitEntityRegistration<_Ping>(
          schema: _pingSchema,
          fromJson: _Ping.fromJson,
          toJson: _Ping.toRow,
        ),
      ],
      ArxaKitIdService(),
      ArxaKitSchemaRegistry(),
    );

    // The doorbell targets OFFLINE accounts only — first sync, then pause.
    await backend.database.waitForFirstSync().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        fail('first sync never completed against $_syncUrl');
      },
    );
    await backend.database.pauseSync();

    // Received-marker wiring BEFORE going quiet: foreground data messages.
    final received = Completer<String>();
    final sub = FirebaseMessaging.onMessage.listen((message) {
      if (!received.isCompleted) received.complete('${message.data}');
    });

    // ignore: avoid_print — the marker protocol IS stdout; the script greps it.
    print('PUSH_SMOKE_READY');

    // Bounded wait — on a dead rail the script's own server-side assertion
    // fires first; this bounds the device side regardless.
    final payload = await received.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        // ignore: avoid_print
        print('PUSH_SMOKE_TIMEOUT');
        return '';
      },
    );
    await sub.cancel();

    expect(payload, isNotEmpty, reason: 'doorbell never arrived (TIMEOUT)');
    // ignore: avoid_print
    print('PUSH_SMOKE_RECEIVED=$payload');
    expect(payload, contains(_table),
        reason: 'the doorbell carries {table, lsn} — table must be ours');

    await backend.database.close();
  });
}
