import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart'
    show AppBoxKitErrorService;
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_viewmodel.dart';

import '../helpers/test_helpers.dart';

class MockAppBoxKitAuthService extends Mock implements AppBoxKitAuthService {}

const _session = AppBoxKitAuthSession(user: AppBoxKitAuthUser(id: 'user-1'));

void main() {
  // registerServices()'s bottom-sheet stub matches on custom types.
  registerFallbackValue(const Color(0x00000000));
  registerFallbackValue(Duration.zero);

  group('ShowcaseNotesAuthViewModel Tests -', () {
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

    ShowcaseNotesAuthViewModel createViewModel() {
      final vm = ShowcaseNotesAuthViewModel();
      addTearDown(vm.dispose);
      return vm;
    }

    test(
        'auth-and-accounts.sign-in.sign-in-with-email-and-otp — switching the credential mode emits the new mode and resets the requested OTP',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.requestOtp(email: any(named: 'email')))
          .thenAnswer((_) async {});
      final modes = expectLater(
        vm.mode$,
        emitsInOrder([
          NotesAuthMode.password,
          NotesAuthMode.otp,
          NotesAuthMode.password,
        ]),
      );
      // Seed, the reset setMode re-adds (BehaviorSubject re-emits equal
      // values), the request's flip, the switch-back's reset.
      final otpSteps = expectLater(
        vm.otpRequested$,
        emitsInOrder([isFalse, isFalse, isTrue, isFalse]),
      );
      // when
      vm.setMode(NotesAuthMode.otp);
      await vm.requestOtp('evan@seed.local');
      vm.setMode(NotesAuthMode.password);
      // then
      await modes.timeout(const Duration(milliseconds: 500));
      await otpSteps.timeout(const Duration(milliseconds: 500));
    });

    test(
        'auth-and-accounts.sign-in.sign-in-with-email-and-otp — a successful OTP request flips otpRequested\$ so the code field appears',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.requestOtp(email: any(named: 'email')))
          .thenAnswer((_) async {});
      final expectation = expectLater(
        vm.otpRequested$,
        emitsInOrder([isFalse, isTrue]),
      );
      // when
      await vm.requestOtp('evan@seed.local');
      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'auth-and-accounts.sign-in.sign-in-with-email-and-otp — a rejected sign-in surfaces the auth exception message inline',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signInWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(
          const AppBoxKitAuthException('Invalid email or password'));
      // Seed null, the guard's clear-to-null, then the surfaced message.
      final expectation = expectLater(
        vm.errorMessage$,
        emitsInOrder([isNull, isNull, 'Invalid email or password']),
      );
      // when
      await vm.signInEmail('evan@seed.local', 'wrong');
      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'auth-and-accounts.sign-in.sign-in-with-email-and-otp — busy\$ is true while sign-in runs and false once it completes',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signInWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _session);
      // shareValueSeeded emits its seed, then the combineLatest composition's
      // initial emission — two falses before the op's true.
      final expectation = expectLater(
        vm.busy$,
        emitsInOrder([isFalse, isFalse, isTrue, isFalse]),
      );
      // when
      await vm.signInEmail('evan@seed.local', 'x');
      // then
      await expectation.timeout(const Duration(milliseconds: 500));
    });

    test(
        'auth-and-accounts.sign-in.sign-in-with-google — delegates to the auth service Google sign-in',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => _session);
      // when
      await vm.google();
      // then
      verify(() => auth.signInWithGoogle()).called(1);
    });

    test(
        'auth-and-accounts.sign-in.sign-in-with-apple — delegates to the auth service Apple sign-in',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signInWithApple()).thenAnswer((_) async => _session);
      // when
      await vm.apple();
      // then
      verify(() => auth.signInWithApple()).called(1);
    });

    test(
        'auth-and-accounts.sign-in.continue-anonymously — delegates to the auth service anonymous sign-in',
        () async {
      // given
      final vm = createViewModel();
      when(() => auth.signInAnonymously()).thenAnswer((_) async => _session);
      // when
      await vm.anonymous();
      // then
      verify(() => auth.signInAnonymously()).called(1);
    });
  });
}
