import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_ui_library/appbox_kit_testing.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';
import 'package:appbox_kit_showcase_app/app/app_data.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:appbox_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// The notes-shell cascade: session → overview/admin streams, composed with
/// rxdart switchMap and bound via AppBoxKitStreamBuilder in the views. This is the
/// one non-trivial wiring the streams-only conversion introduced, so it gets
/// the check: overview appears with a session and nulls out on sign-out.
class _DiskAssetReader implements AppBoxKitAssetReader {
  static const _prefix = 'packages/appbox_kit_showcase_app/';

  @override
  Future<String> readString(String path) async {
    final stripped =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return File(stripped).readAsString();
  }
}

void main() {
  late ShowcaseNotesFacadeService notes;

  setUpAll(() async {
    appBoxKitLocator
      ..registerLazySingleton(() => Talker())
      ..registerLazySingleton(() => AppBoxKitErrorService())
      ..registerLazySingleton(() => DialogService())
      ..registerLazySingleton(() => BottomSheetService())
      ..registerLazySingleton(() => SnackbarService())
      ..registerLazySingleton<AppBoxKitNotificationService>(
          () => FakeAppBoxKitNotificationService())
      ..registerLazySingleton<ShowcaseNotesRepositoryService>(
          () => ShowcaseNotesRepositoryService())
      ..registerLazySingleton<ShowcaseNotesFacadeService>(
          () => ShowcaseNotesFacadeService());

    await AppData.initialize(
      config: const AppBoxKitDataConfig(
        backend: AppBoxKitDataBackend.seed,
        auth: AppBoxKitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
      ),
      assetReader: _DiskAssetReader(),
    );

    notes = appBoxKitLocator<ShowcaseNotesFacadeService>();
  });

  tearDownAll(() async {
    AppBoxKitData.resetForTesting();
    await appBoxKitLocator.reset();
  });

  Future<void> until(bool Function() cond) async {
    for (var i = 0; i < 100 && !cond(); i++) {
      await pumpEventQueue();
    }
  }

  test(
      'notes.folders.browse-the-notes-in-a-folder — overview follows the session through the switchMap cascade',
      () async {
    await notes.auth
        .signInWithEmailPassword(email: 'evan@seed.local', password: 'x');

    final vm = ShowcaseNotesViewModel();
    addTearDown(vm.dispose);

    // Streams-only VM: capture the latest emission of each stream getter.
    AppBoxKitAuthSession? session;
    ShowcaseNotesOverview? overview;
    final subscriptions = [
      vm.session$.listen((s) => session = s),
      vm.overview$.listen((o) => overview = o),
    ];
    addTearDown(() async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    });

    await until(() => overview != null);
    expect(session, isNotNull);
    expect(overview, isNotNull,
        reason: 'switchMap resubscribes overview\$ for the live session');

    await notes.signOut();
    await until(() => session == null && overview == null);
    expect(session, isNull);
    expect(overview, isNull,
        reason: 'sign-out switches the inner stream to null');
  });
}
