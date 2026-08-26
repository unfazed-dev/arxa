import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_showcase_app/app/app_data.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

/// The notes-shell cascade: session → overview/admin streams, composed with
/// rxdart switchMap and bound via ArxaKitStreamBuilder in the views. This is the
/// one non-trivial wiring the streams-only conversion introduced, so it gets
/// the check: overview appears with a session and nulls out on sign-out.
class _DiskAssetReader implements ArxaKitAssetReader {
  static const _prefix = 'packages/arxa_kit_showcase_app/';

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
    // Kit UI services (Talker / Dialog / Snackbar / BottomSheet) — the kit's
    // own setup; ArxaKitAction managers resolve these lazily on first
    // execute().
    setupArxaKitUiServices();
    arxaKitLocator
      ..registerLazySingleton(() => ArxaKitErrorService())
      ..registerLazySingleton<ArxaKitNotificationService>(
          () => FakeArxaKitNotificationService())
      ..registerLazySingleton<ShowcaseNotesRepositoryService>(
          () => ShowcaseNotesRepositoryService())
      ..registerLazySingleton<ShowcaseNotesFacadeService>(
          () => ShowcaseNotesFacadeService());

    await AppData.initialize(
      config: const ArxaKitDataConfig(
        backend: ArxaKitDataBackend.seed,
        auth: ArxaKitAuthConfig(fakeUsersAsset: AppData.fakeUsersAsset),
      ),
      assetReader: _DiskAssetReader(),
    );

    notes = arxaKitLocator<ShowcaseNotesFacadeService>();
  });

  tearDownAll(() async {
    ArxaKitData.resetForTesting();
    await arxaKitLocator.reset();
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
    ArxaKitAuthSession? session;
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
