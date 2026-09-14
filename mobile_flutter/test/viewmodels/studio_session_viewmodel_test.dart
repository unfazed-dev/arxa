import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:arxa_studio_mobile/ui/views/studio_shell/studio_session/studio_session_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('StudioSessionViewModel', () {
    late MockRouterService router;

    setUp(() {
      final s = registerTestServices();
      router = s.router;
    });
    tearDown(unregisterTestServices);

    test('stays controllerless when the transport is not connected', () {
      final vm = StudioSessionViewModel()..start();
      // Not connected: no studioUrl, so no webview controller is created
      // (creating one is also impossible on the host test platform — the
      // guard keeps the view on its "pair first" fallback).
      expect(vm.studioUrl, isNull);
      expect(vm.controller, isNull);
    });

    test('pins the shell user agent', () {
      expect(
        StudioSessionViewModel.userAgent,
        'Mozilla/5.0 (Mobile) ArxaShell/0.1',
      );
    });

    test('openSettings routes to settings', () async {
      final vm = StudioSessionViewModel();
      await vm.openSettings();
      verify(() => router.navigateTo(any())).called(1);
    });
  });
}
