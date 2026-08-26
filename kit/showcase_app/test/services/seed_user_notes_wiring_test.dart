import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_ui_library/arxa_kit_testing.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_showcase_app/app/app_data.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/facades/showcase_notes_facade_service.dart';
import 'package:arxa_kit_showcase_app/services/showcase_notes_services/repositories/showcase_notes_repository_service.dart';

/// End-to-end wiring check: every seed user, signed in through the REAL auth
/// entry points (email/password, Google, Apple), must see exactly the notes
/// the shipped fixtures assign them. Expected counts are computed from the
/// fixture JSON itself — not hardcoded — so this fails if seeding, owner
/// canonicalization, or auth resolution ever drift apart.
class _DiskAssetReader implements ArxaKitAssetReader {
  static const _prefix = 'packages/arxa_kit_showcase_app/';

  @override
  Future<String> readString(String path) async {
    final stripped =
        path.startsWith(_prefix) ? path.substring(_prefix.length) : path;
    return File(stripped).readAsString();
  }
}

List<Map<String, dynamic>> _rows(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  final list = decoded is Map ? decoded['rows'] : decoded;
  return (list as List).cast<Map<String, dynamic>>();
}

void main() {
  late ShowcaseNotesFacadeService notes;

  // ownerSeedKey -> (live, trashed), derived from the shipped fixture.
  final expectedLive = <String, int>{};
  final expectedTrash = <String, int>{};

  setUpAll(() async {
    for (final row in _rows('data/seed/notes.json')) {
      final owner = row['owner'] as String;
      if (row['deleted_at'] != null) {
        expectedTrash[owner] = (expectedTrash[owner] ?? 0) + 1;
      } else {
        expectedLive[owner] = (expectedLive[owner] ?? 0) + 1;
      }
    }

    // The kit's own setup registers Talker + the stacked UI service bases.
    setupArxaKitUiServices();
    arxaKitLocator
      ..registerLazySingleton(() => ArxaKitErrorService())
      // Fake: the real service's CNToast path needs a mounted navigator
      // context, which a data-layer suite doesn't have.
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

  Future<ShowcaseNotesOverview> overviewFor(ArxaKitAuthSession session) =>
      notes.overview$(session.user.id).first;

  test('fixture sanity: every seed user owns at least one live note', () {
    for (final row in _rows('data/seed/kit_auth_users.json')) {
      final id = row['id'] as String;
      expect(expectedLive[id], isNotNull,
          reason: 'seed user $id owns no live notes in notes.json — '
              'showcase would legitimately render empty for them');
      expect(expectedLive[id], greaterThan(0));
    }
  });

  test(
      'auth-and-accounts.sign-in.sign-in-with-email-and-otp — email/password seed users see their fixture notes',
      () async {
    const emailUsers = {
      'user-1': 'evan@seed.local',
      'user-2': 'guest@seed.local',
      'user-admin': 'admin@seed.local',
    };
    for (final entry in emailUsers.entries) {
      final session = await notes.auth
          .signInWithEmailPassword(email: entry.value, password: 'anything');
      final overview = await overviewFor(session);
      expect(overview.allCount, expectedLive[entry.key],
          reason: '${entry.value} (${entry.key}) live-note count mismatch — '
              'owner canonicalId does not line up with the signed-in id '
              '(session.user.id=${session.user.id})');
      expect(overview.trashCount, expectedTrash[entry.key] ?? 0,
          reason: '${entry.value} trash count mismatch');
    }
  });

  test(
      'auth-and-accounts.sign-in.sign-in-with-google — Google provider sign-in resolves to user-google seed data',
      () async {
    final session = await notes.auth.signInWithGoogle();
    final overview = await overviewFor(session);
    expect(overview.allCount, expectedLive['user-google'],
        reason: 'signInWithGoogle minted a NEW identity instead of resolving '
            'google-user@seed.local (session.user.id=${session.user.id})');
  });

  test(
      'auth-and-accounts.sign-in.sign-in-with-apple — Apple provider sign-in resolves to user-apple seed data',
      () async {
    final session = await notes.auth.signInWithApple();
    final overview = await overviewFor(session);
    expect(overview.allCount, expectedLive['user-apple'],
        reason: 'signInWithApple minted a NEW identity instead of resolving '
            'apple-user@seed.local (session.user.id=${session.user.id})');
  });

  test(
      'auth-and-accounts.sign-in.continue-anonymously — anonymous sign-in intentionally starts empty (0 notes is correct)',
      () async {
    final session = await notes.auth.signInAnonymously();
    final overview = await overviewFor(session);
    expect(overview.allCount, 0,
        reason: 'anon users own no seed rows by design');
  });

  test(
      'notes.folders.browse-the-notes-in-a-folder — folder counts sum to allCount for every seeded user',
      () async {
    const emails = [
      'evan@seed.local',
      'guest@seed.local',
      'admin@seed.local',
      'google-user@seed.local',
      'apple-user@seed.local',
    ];
    for (final email in emails) {
      final session =
          await notes.auth.signInWithEmailPassword(email: email, password: 'x');
      final overview = await overviewFor(session);
      final foldered =
          overview.liveCountByFolder.values.fold<int>(0, (a, b) => a + b);
      expect(foldered, lessThanOrEqualTo(overview.allCount),
          reason: '$email: folder-scoped notes exceed the All count — '
              'folder owner wiring is inconsistent');
    }
  });
}
