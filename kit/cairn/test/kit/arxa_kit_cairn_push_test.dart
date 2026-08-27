import 'package:flutter_test/flutter_test.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_testing.dart';

import '../support/fake_cairn_engine.dart';
import '../support/post_harness.dart';

/// Push (phase 4g): cairn push sits BEHIND the kit/notifications seam — the
/// bridge consumes `ArxaKitNotificationsService.tokenStream` and hands each
/// token to `CairnDatabase.registerPushToken`. No Firebase types cross into
/// the kit; the provider rail (FCM/APNs config, background isolate, VAPID web
/// leg) is app-side (see the README's push section).
///
/// Branches under test (mirroring the atlet pilot checklist):
/// - attach registers the CURRENT token at once, then every refresh.
/// - unknown providers are skipped with a log, never a crash.
/// - CairnPushTokenException is non-fatal: logged, and the next token still
///   registers (retry semantics live on the next attach/refresh).
/// - detach stops forwarding; DEREGISTRATION is not the bridge's job (the
///   SDK's sign-out hook owns it, ADR-0037 §3).
/// - the backend gates push loudly: localOnly has no server; push without a
///   notifications service has no token source.
/// - the facade surfaces registerPushToken / currentAccessToken.
void main() {
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  group('kit.cairn.push', () {
    test(
      'kit.cairn.push — attach registers the current token, then every refresh',
      () async {
        // Given a bridge over a scripted notifications seam
        final notifications = FakeArxaKitNotificationsService();
        final registered = <(String, String)>[];
        final bridge = ArxaKitCairnPushBridge(
          notifications: notifications,
          register: (platform, token) async => registered.add((platform, token)),
        );

        // When attach runs with a token already issued
        notifications.emitToken(ArxaKitPushToken(
          value: 'fcm-token-1',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await bridge.attach();

        // Then the current token registered immediately, mapped to cairn's
        // platform string
        expect(registered, [('fcm', 'fcm-token-1')]);

        // And a refresh re-registers (the SDK deregisters session tokens on
        // sign-out, so every rotation must re-register)
        notifications.emitToken(ArxaKitPushToken(
          value: 'apns-token-2',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.apns,
        ));
        await Future<void>.delayed(Duration.zero);
        expect(registered, [('fcm', 'fcm-token-1'), ('apns', 'apns-token-2')]);
      },
    );

    test(
      'kit.cairn.push — an unknown provider is skipped with a log, never a crash',
      () async {
        // Given a bridge whose seam emits a provider-less token
        final notifications = FakeArxaKitNotificationsService();
        final registered = <(String, String)>[];
        final logs = <String>[];
        final bridge = ArxaKitCairnPushBridge(
          notifications: notifications,
          register: (platform, token) async => registered.add((platform, token)),
          log: logs.add,
        );
        await bridge.attach();

        // When an unknown-provider token arrives
        notifications.emitToken(ArxaKitPushToken(
          value: 'mystery',
          issuedAt: DateTime(2026, 8, 28),
        ));
        await Future<void>.delayed(Duration.zero);

        // Then nothing registered and the skip was logged
        expect(registered, isEmpty);
        expect(logs.single, contains('unknown'));
      },
    );

    test(
      'kit.cairn.push — a rejected registration is non-fatal and the next token still lands',
      () async {
        // Given a register fn that rejects the first token (server 500)
        final notifications = FakeArxaKitNotificationsService();
        final registered = <String>[];
        final logs = <String>[];
        var calls = 0;
        final bridge = ArxaKitCairnPushBridge(
          notifications: notifications,
          register: (platform, token) async {
            calls++;
            if (calls == 1) {
              throw const CairnPushTokenException(
                operation: 'register',
                statusCode: 500,
                body: 'boom',
              );
            }
            registered.add(token);
          },
          log: logs.add,
        );

        // When two tokens arrive (first rejected, second fine)
        notifications.emitToken(ArxaKitPushToken(
          value: 'token-a',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await bridge.attach();
        notifications.emitToken(ArxaKitPushToken(
          value: 'token-b',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await Future<void>.delayed(Duration.zero);

        // Then the rejection was logged, not thrown, and registration recovered
        expect(registered, ['token-b']);
        expect(logs.single, contains('registerPushToken'));
      },
    );

    test(
      'kit.cairn.push — detach stops forwarding and never deregisters',
      () async {
        // Given an attached bridge
        final notifications = FakeArxaKitNotificationsService();
        final registered = <String>[];
        final bridge = ArxaKitCairnPushBridge(
          notifications: notifications,
          register: (platform, token) async => registered.add(token),
        );
        await bridge.attach();

        // When detach runs and a token arrives afterwards
        await bridge.detach();
        notifications.emitToken(ArxaKitPushToken(
          value: 'post-detach',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await Future<void>.delayed(Duration.zero);

        // Then nothing was forwarded — and no deregister call happened either
        // (the SDK's sign-out hook owns deregistration; ADR-0037 §3)
        expect(registered, isEmpty);
      },
    );

    test(
      'kit.cairn.push — push with localOnly fails at boot naming ARXA_CAIRN_PUSH',
      () async {
        // Given a localOnly backend with push opted in (no server exists)
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(push: true),
          notifications: FakeArxaKitNotificationsService(),
          openDatabase: _unusedOpen,
        );

        // Then initialize refuses, naming the define
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [plainPostRegistration],
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('ARXA_CAIRN_PUSH'),
          )),
        );
      },
    );

    test(
      'kit.cairn.push — push without a notifications service fails naming the param',
      () async {
        // Given a sync-mode backend with push but no seam to draw tokens from
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            mode: ArxaKitCairnMode.sync,
            syncUrl: 'wss://sync.example.com/sync',
            push: true,
          ),
          tokenProvider: () async => 'host-jwt',
          openDatabase: _unusedOpen,
        );

        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [plainPostRegistration],
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('notifications'),
          )),
        );
      },
    );

    test(
      'kit.cairn.push — the backend attaches after open and the facade surfaces token + access token',
      () async {
        // Given a sync-mode backend with push and a scripted seam
        final notifications = FakeArxaKitNotificationsService();
        final registered = <(String, String)>[];
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            mode: ArxaKitCairnMode.sync,
            syncUrl: 'wss://sync.example.com/sync',
            push: true,
          ),
          tokenProvider: () async => 'host-jwt-9',
          notifications: notifications,
          pushRegister: (platform, token) async =>
              registered.add((platform, token)),
          openDatabase: (config, schema, token) async {
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(FakeCairnEngine());
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );

        // When kit/data initializes
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [plainPostRegistration],
        );

        // Then a token from the seam registers through the backend's wiring
        notifications.emitToken(ArxaKitPushToken(
          value: 'fcm-after-boot',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await Future<void>.delayed(Duration.zero);
        expect(registered, [('fcm', 'fcm-after-boot')]);

        // And the facade surfaces the session's access token (the background
        // isolate's persisted-creds file is built from it)
        expect(backend.currentAccessToken, 'host-jwt-9');

        // And dispose detaches the bridge
        await backend.dispose();
        notifications.emitToken(ArxaKitPushToken(
          value: 'post-dispose',
          issuedAt: DateTime(2026, 8, 28),
          provider: ArxaKitPushProvider.fcm,
        ));
        await Future<void>.delayed(Duration.zero);
        expect(registered, hasLength(1));
      },
    );
  });
}

Future<CairnDatabase> _unusedOpen(
  ArxaKitCairnConfig config,
  CairnSchema schema,
  String? token,
) =>
    throw StateError('the opener must not run in this test');
