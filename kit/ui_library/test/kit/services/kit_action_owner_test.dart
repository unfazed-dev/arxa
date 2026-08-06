import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_core/services/error/kit_error_service.dart';
import 'package:ui_library/services/notifications/kit_notification_service.dart';
import 'package:ui_library/utils/kit_action/kit_action.dart';
import 'package:ui_library/utils/kit_view_model.dart';

/// Tests for owner-identity KitAction: derived keys (no hand-written
/// widgetIds), parallel ops across owners, and auto-dispose via
/// `KitViewModel.dispose` → `KitAction.disposeOwner`.
class _FakeVm extends KitViewModel {}

void main() {
  setUp(() async {
    locator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => KitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => KitNotificationService())
      ..registerLazySingleton(() => SnackbarService());
    await locator<KitErrorService>().initialize();
  });

  tearDown(() => locator.reset());

  group('owner-identity keys', () {
    test('run(owner:, op:) state is observable via state\$ of the same pair',
        () async {
      final vm = _FakeVm();
      final gate = Completer<void>();
      // Bind first, like a view does — subjects are created on read.
      final state = vm.actionState$('save');

      final future = KitAction.run<String>(
        operation: () async {
          await gate.future;
          return 'done';
        },
        owner: vm,
        op: 'save',
      ).execute();

      expect(state.value.busy, isTrue);
      gate.complete();
      expect(await future, 'done');
      expect(state.value.busy, isFalse);

      vm.dispose();
    });

    test('same op label on two owners runs in parallel (independent keys)',
        () async {
      final vmA = _FakeVm();
      final vmB = _FakeVm();
      final gate = Completer<void>();
      var runs = 0;

      Future<String> op() async {
        runs++;
        await gate.future;
        return 'x';
      }

      final a = KitAction.run<String>(operation: op, owner: vmA, op: 'save')
          .execute();
      final b = KitAction.run<String>(operation: op, owner: vmB, op: 'save')
          .execute();

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
    test('KitViewModel.dispose cancels owner watches (no callback after)',
        () async {
      final vm = _FakeVm();
      final subject = BehaviorSubject<int>.seeded(0);
      addTearDown(subject.close);
      var calls = 0;

      KitAction.watch(
        owner: vm,
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
      final future = KitAction.run<String>(
        operation: () async {
          await gate.future;
          return 'x';
        },
        owner: vm,
        op: 'save',
      ).execute();
      expect(vm.actionState$('save').value.busy, isTrue);

      gate.complete();
      await future;
      vm.dispose();

      // Post-dispose lookup is a fresh idle subject — the old one is closed.
      expect(KitAction.state$(owner: vm, op: 'save').value.busy, isFalse);
    });
  });
}
