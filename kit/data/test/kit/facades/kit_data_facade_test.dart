import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:appbox_kit_data/testing.dart';
import 'package:ui_library/testing.dart';
import 'package:ui_library/utils/kit_action/kit_action.dart';

/// `KitDataFacade.mutate` policy params: the key is derived
/// (owner + op.entity), and error/success messages become snackbar config on
/// the returned builder — the common mutation is a one-liner.
void main() {
  setUp(() async {
    locator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => KitErrorService())
      ..registerLazySingleton<KitNotificationService>(
          () => FakeKitNotificationService());
    await locator<KitErrorService>().initialize();
  });

  tearDown(() => locator.reset());

  test('mutate records op/entity and executes the operation', () async {
    final facade = FakeKitDataFacade();

    final result = await facade.mutate<String>(
      operation: () async => 'stored',
      op: 'pin',
      entity: 'note-1',
      error: 'Could not pin',
    ).execute();

    expect(result, 'stored');
    expect(facade.mutateCalls, hasLength(1));
    expect(facade.mutateCalls.single.op, 'pin');
    expect(facade.mutateCalls.single.entity, 'note-1');
  });

  test('derived key is owner + op.entity — state binds while in flight',
      () async {
    final facade = FakeKitDataFacade();
    final gate = Completer<void>();
    // Bind first, like a view does — subjects are created on read.
    final state =
        KitAction.state$(owner: facade, op: 'pin.note-1');

    final future = facade.mutate<String>(
      operation: () async {
        await gate.future;
        return 'x';
      },
      op: 'pin',
      entity: 'note-1',
      error: 'nope',
    ).execute();

    expect(state.value.busy, isTrue);
    gate.complete();
    await future;
    expect(state.value.busy, isFalse);
  });

  test('error param surfaces as the recorded errorMessage', () async {
    final facade = FakeKitDataFacade();
    final state = KitAction.state$(owner: facade, op: 'wipe');

    // No fallback: the error rethrows after the snackbar — and the state
    // stream carries the snackbar's message.
    await expectLater(
      facade.mutate<void>(
        operation: () async => throw Exception('db gone'),
        op: 'wipe',
        error: 'Could not delete',
      ).execute(),
      throwsException,
    );

    expect(state.value.errorMessage, 'Could not delete');
  });
}
