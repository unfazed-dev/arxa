import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:appbox_kit_data/appbox_kit_testing.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';

/// `AppBoxKitDataFacade.mutate` policy params: the key is derived
/// (owner + name.entity), and error/success messages become notification
/// config on the bus run — the common mutation is a one-liner. The
/// returned future is an observation handle: the mutation is already running.
void main() {
  setUp(() async {
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton<AppBoxKitNotificationService>(
          () => FakeAppBoxKitNotificationService());
    await appBoxKitLocator<AppBoxKitErrorService>().initialize();
  });

  tearDown(() => appBoxKitLocator.reset());

  test('kit.data.facades — mutate records name/entity and executes the operation', () async {
    final facade = FakeAppBoxKitDataFacade();

    // The handle is already running — awaiting it just observes the result.
    final result = await facade.mutate<String>(
      () async => 'stored',
      name: 'pin',
      entity: 'note-1',
      error: 'Could not pin',
    );

    expect(result, 'stored');
    expect(facade.mutateCalls, hasLength(1));
    expect(facade.mutateCalls.single.name, 'pin');
    expect(facade.mutateCalls.single.entity, 'note-1');
  });

  test('kit.data.facades — derived key is owner + name.entity — state binds while in flight',
      () async {
    final facade = FakeAppBoxKitDataFacade();
    final gate = Completer<void>();
    // Bind first, like a view does — subjects are created on read.
    final state = facade.actionState$('pin.note-1');

    final future = facade.mutate<String>(
      () async {
        await gate.future;
        return 'x';
      },
      name: 'pin',
      entity: 'note-1',
      error: 'nope',
    );

    // Hot dispatch: the run starts on the dispatcher's subscription, a microtask
    // after the call — pump before observing busy.
    await pumpEventQueue();
    expect(state.value.busy, isTrue);
    gate.complete();
    await future;
    expect(state.value.busy, isFalse);
  });

  test('kit.data.facades — error param surfaces as the recorded errorMessage', () async {
    final facade = FakeAppBoxKitDataFacade();
    final state = facade.actionState$('wipe');

    // No fallback: the error rethrows through the handle after the snackbar —
    // and the state stream carries the snackbar's message.
    await expectLater(
      facade.mutate<void>(
        () async => throw Exception('db gone'),
        name: 'wipe',
        error: 'Could not delete',
      ),
      throwsException,
    );

    expect(state.value.errorMessage, 'Could not delete');
  });
}
