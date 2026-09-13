import 'package:arxa_kit_notifications/arxa_kit_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/ui/views/pairing_shell/pairing_push_permission/pairing_push_permission_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('PairingPushPermissionViewModel', () {
    late FakeArxaKitNotificationsService notifications;
    late MockRouterService router;

    setUp(() {
      final s = registerTestServices();
      notifications = s.notifications;
      router = s.router;
    });
    tearDown(unregisterTestServices);

    test(
      'allow requests the OS permission then hands off to the session',
      () async {
        final vm = PairingPushPermissionViewModel();
        await vm.allow();
        expect(notifications.permissionRequests, hasLength(1));
        verify(() => router.replaceWith(any())).called(1);
      },
    );

    test('skip hands off without asking the OS', () async {
      final vm = PairingPushPermissionViewModel();
      await vm.skip();
      expect(notifications.permissionRequests, isEmpty);
      verify(() => router.replaceWith(any())).called(1);
    });
  });
}
