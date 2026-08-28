// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedLocatorGenerator
// **************************************************************************

// ignore_for_file: public_member_api_docs, implementation_imports, depend_on_referenced_packages

import 'package:arxa_kit_notifications/src/arxa_kit_notifications_service.dart';
import 'package:arxa_kit_notifications/src/backends/arxa_kit_fcm_push_backend.dart';
import 'package:stacked_services/src/navigation/router_service.dart';
import 'package:stacked_shared/stacked_shared.dart';

import '../services/push_token_service.dart';
import '../services/transport_service.dart';
import 'app.router.dart';

final locator = StackedLocator.instance;

Future<void> setupLocator(
    {String? environment,
    EnvironmentFilter? environmentFilter,
    StackedRouterWeb? stackedRouter}) async {
// Register environments
  locator.registerEnvironment(
      environment: environment, environmentFilter: environmentFilter);

// Register dependencies
  locator.registerLazySingleton(() => RouterService());
  locator.registerLazySingleton<TransportService>(() => FakeTransportService());
  locator.registerLazySingleton<ArxaKitNotificationsService>(
      () => ArxaKitFcmPushBackend());
  locator.registerLazySingleton(() => PushTokenService());
  if (stackedRouter == null) {
    throw Exception(
        'Stacked is building to use the Router (Navigator 2.0) navigation but no stackedRouter is supplied. Pass the stackedRouter to the setupLocator function in main.dart');
  }

  locator<RouterService>().setRouter(stackedRouter);
}
