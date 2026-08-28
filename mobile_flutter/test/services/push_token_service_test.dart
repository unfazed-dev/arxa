import 'package:arxa_kit_notifications/arxa_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/services/push_token_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

void main() {
  group('PushTokenService', () {
    test(
        'requestPermission asks the OS and attaches the cairn bridge; '
        'token issues forward to the transport', () async {
      final notifications = FakeArxaKitNotificationsService();
      final transport = FakeTransportService();
      final service = PushTokenService(
        notifications: notifications,
        transport: transport,
      );

      final result = await service.requestPermission();
      expect(result.status, ArxaKitNotificationAuthorization.authorized);
      expect(notifications.permissionRequests, hasLength(1));

      notifications.emitToken(
        ArxaKitPushToken(
          value: 'tok-42',
          issuedAt: DateTime.now(),
          // unknown-provider tokens are deliberately skipped by the bridge
          provider: ArxaKitPushProvider.fcm,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.lastPushToken?.$2, 'tok-42');

      await service.detach();
      await transport.dispose();
    });
  });
}
