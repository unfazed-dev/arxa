import 'package:arxa_kit_notifications/arxa_kit_testing.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show RouterService;
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/services/push_token_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

class MockRouterService extends Mock implements RouterService {}

/// Registers the seams under test with fakes; call from `setUp`.
({
  FakeTransportService transport,
  FakeArxaKitNotificationsService notifications,
  MockRouterService router,
})
registerTestServices() {
  registerFallbackValue(PairingScanViewRoute());
  final transport = FakeTransportService();
  final notifications = FakeArxaKitNotificationsService();
  final router = MockRouterService();
  when(() => router.navigateTo(any())).thenAnswer((_) async => null);
  when(() => router.replaceWith(any())).thenAnswer((_) async => null);
  when(() => router.clearStackAndShow(any())).thenAnswer((_) async {});
  locator
    ..registerSingleton<TransportService>(transport)
    ..registerSingleton<ArxaKitNotificationsService>(notifications)
    ..registerSingleton<RouterService>(router)
    ..registerLazySingleton<PushTokenService>(PushTokenService.new);
  return (transport: transport, notifications: notifications, router: router);
}

Future<void> unregisterTestServices() => locator.reset();
