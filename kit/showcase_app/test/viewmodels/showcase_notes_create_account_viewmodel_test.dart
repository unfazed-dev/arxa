import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_viewmodel.dart';

import '../helpers/test_helpers.dart';

class MockAppBoxKitAuthService extends Mock implements AppBoxKitAuthService {}

const _session = AppBoxKitAuthSession(user: AppBoxKitAuthUser(id: 'user-1'));

void main() {
  // registerServices()'s bottom-sheet stub matches on custom types.
  registerFallbackValue(const Color(0x00000000));
  registerFallbackValue(Duration.zero);

  group('ShowcaseNotesCreateAccountViewModel Tests -', () {
    late MockShowcaseNotesFacadeService facade;
    late MockAppBoxKitAuthService auth;

    setUp(() async {
      registerServices();
      registerAppBoxKitActionServices();
      // The real AppBoxKitAction error path logs through the error service's
      // late Talker — initialize it before any op can fail (ui_library
      // playbook).
      await locator<AppBoxKitErrorService>().initialize();
      facade =
          locator<ShowcaseNotesFacadeService>() as MockShowcaseNotesFacadeService;
      auth = MockAppBoxKitAuthService();
      when(() => facade.auth).thenReturn(auth);
    });
    tearDown(() => locator.reset());

    ShowcaseNotesCreateAccountViewModel createViewModel() {
      final vm = ShowcaseNotesCreateAccountViewModel();
      addTearDown(vm.dispose);
      return vm;
    }

    test(
        'auth-and-accounts.create-account.create-account-with-email-and-otp — signUpState\$ is busy while the account is created and idle once it completes',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signUpWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _session);
      final expectation = expectLater(
        vm.signUpState$.map((state) => state.busy),
        emitsInOrder([isFalse, isTrue, isFalse]),
      );
      // when
      await vm.createAccount('new@seed.local', 'secret');
      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'auth-and-accounts.create-account.create-account-with-email-and-otp — a rejected sign-up surfaces the auth exception message inline',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signUpWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(
          const AppBoxKitAuthException('That email is already registered'));
      // Seed null, the guard's clear-to-null, then the surfaced message.
      final expectation = expectLater(
        vm.errorMessage$,
        emitsInOrder([isNull, isNull, 'That email is already registered']),
      );
      // when
      await vm.createAccount('evan@seed.local', 'secret');
      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });
  });
}
