import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_core/services/error/appbox_kit_error_service.dart';
import 'package:appbox_kit_ui_library/services/notifications/appbox_kit_notification_service.dart';
import 'package:appbox_kit_ui_library/utils/appbox_kit_view_model.dart';

/// Tests for owner-identity AppBoxKitAction: derived keys (no hand-written
/// widgetIds), parallel ops across owners, the awaitable builder, and
/// auto-dispose via `AppBoxKitViewModel.dispose` → `AppBoxKitAction.disposeOwner`.
class _FakeVm extends AppBoxKitViewModel {}

void main() {
  setUp(() async {
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => AppBoxKitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
    await appBoxKitLocator<AppBoxKitErrorService>().initialize();
  });

  tearDown(() => appBoxKitLocator.reset());

  group('owner-identity keys', () {
    test('action(name, operation) state is observable via actionState\$',
        () async {
      final vm = _FakeVm();
      final gate = Completer<void>();
      // Bind first, like a view does — subjects are created on read.
      final state = vm.actionState$('save');

      // Fire-and-forget handle (the builder itself is lazy until awaited).
      final future = vm.action<String>('save', () async {
        await gate.future;
        return 'done';
      }).execute();

      expect(state.value.busy, isTrue);
      gate.complete();
      expect(await future, 'done');
      expect(state.value.busy, isFalse);

      vm.dispose();
    });

    test('awaiting the same builder twice runs the operation once', () async {
      final vm = _FakeVm();
      var runs = 0;

      final future = vm.action<String>('save', () async {
        runs++;
        return 'x';
      });

      expect(await future, 'x');
      expect(await future, 'x');
      expect(runs, 1);

      vm.dispose();
    });

    test('same name on two owners runs in parallel (independent keys)',
        () async {
      final vmA = _FakeVm();
      final vmB = _FakeVm();
      final gate = Completer<void>();
      var runs = 0;

      Future<String> operation() async {
        runs++;
        await gate.future;
        return 'x';
      }

      final a = vmA.action<String>('save', operation).execute();
      final b = vmB.action<String>('save', operation).execute();

      // Neither was dropped by the re-entry guard — keys differ per owner.
      gate.complete();
      expect(await a, 'x');
      expect(await b, 'x');
      expect(runs, 2);

      vmA.dispose();
      vmB.dispose();
    });
  });

  group('auto-dispose', () {
    test('AppBoxKitViewModel.dispose cancels owner watches (no callback after)',
        () async {
      final vm = _FakeVm();
      final subject = BehaviorSubject<int>.seeded(0);
      addTearDown(subject.close);
      var calls = 0;

      vm.watch(
        'listener',
        streams: [subject.stream],
        callback: (_) => calls++,
      );
      subject.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(calls, greaterThan(0));

      vm.dispose();
      final callsAfterDispose = calls;
      subject.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(calls, callsAfterDispose);
    });

    test('disposeOwner closes the op state subject (fresh state after)',
        () async {
      final vm = _FakeVm();
      // Bind the state stream so a subject exists.
      expect(vm.actionState$('save').value.busy, isFalse);

      final gate = Completer<void>();
      final future = vm.action<String>('save', () async {
        await gate.future;
        return 'x';
      }).execute();
      expect(vm.actionState$('save').value.busy, isTrue);

      gate.complete();
      await future;
      vm.dispose();

      // Post-dispose lookup is a fresh idle subject — the old one is closed.
      expect(vm.actionState$('save').value.busy, isFalse);
    });
  });
}
