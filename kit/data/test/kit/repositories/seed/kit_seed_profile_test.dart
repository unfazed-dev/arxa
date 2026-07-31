import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/config/kit_seed_profile.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_persistence.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_repository.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_store.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// KitSeedProfile tests — the Seed Profile machinery (latency + failure
/// injection) every KitSeedRepository applies.
///
/// Branches under test:
/// - the default profile is a pass-through: `apply` returns the identical
///   stream and every operation behaves exactly as without a profile;
/// - `KitSeedProfile.failing` throws the typed [KitSeedException] from every
///   one-shot operation and turns every watch emission into a stream error;
/// - `KitSeedProfile.slow` holds one-shot results and watch emissions until
///   the latency elapses (fake clock), then delivers them unchanged.
class _Widget {
  final String id;
  final String name;

  const _Widget({required this.id, required this.name});
}

final _schema = KitTableSchema(
  table: 'widgets',
  columns: const [KitColumn.id(), KitColumn('name', KitColumnType.text)],
);

final _registration = KitEntityRegistration<_Widget>(
  schema: _schema,
  fromJson: (json) => _Widget(
    id: json['id'] as String,
    name: json['name'] as String,
  ),
  toJson: (w) => {'id': w.id, 'name': w.name},
);

void main() {
  final idService = KitIdService();

  /// A repo on a shared store, plus a pass-through writer on the same store
  /// so failing-profile setups can still seed rows.
  ({
    KitSeedRepository<_Widget> repo,
    KitSeedRepository<_Widget> seeder,
  }) makeRepo([KitSeedProfile profile = const KitSeedProfile()]) {
    final store = KitSeedStore(persistence: KitNoPersistence());
    return (
      repo: KitSeedRepository<_Widget>(
        store: store,
        registration: _registration,
        idService: idService,
        profile: profile,
      ),
      seeder: KitSeedRepository<_Widget>(
        store: store,
        registration: _registration,
        idService: idService,
      ),
    );
  }

  test('default profile is a pass-through', () async {
    const profile = KitSeedProfile();
    final source = Stream<int>.value(1);
    expect(identical(profile.apply(source), source), isTrue,
        reason: 'no injection → the exact source stream is returned');

    final repos = makeRepo();
    await repos.repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));
    expect((await repos.repo.getAll()).single.name, 'Alpha');
    expect((await repos.repo.getById('w-1'))!.name, 'Alpha');
  });

  group('failing profile', () {
    const failure = KitSeedException('injected backend failure');

    test('every one-shot operation throws the typed KitSeedException', () {
      final repos = makeRepo(const KitSeedProfile.failing(failure));

      expect(repos.repo.getAll(), throwsA(isA<KitSeedException>()));
      expect(repos.repo.getById('w-1'), throwsA(isA<KitSeedException>()));
      expect(
        repos.repo.upsert(const _Widget(id: 'w-1', name: 'Alpha')),
        throwsA(isA<KitSeedException>()),
      );
      expect(repos.repo.delete('w-1'), throwsA(isA<KitSeedException>()));
    });

    test('watch emissions become stream errors', () async {
      final repos = makeRepo(const KitSeedProfile.failing(failure));
      await repos.seeder.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

      final errors = <Object>[];
      final sub = repos.repo.watchAll().listen(
            (_) {},
            onError: errors.add,
          );
      await pumpEventQueue();
      expect(errors, hasLength(1));
      expect(errors.single, isA<KitSeedException>());

      final byIdErrors = <Object>[];
      final byIdSub = repos.repo.watchById('w-1').listen(
            (_) {},
            onError: byIdErrors.add,
          );
      await pumpEventQueue();
      expect(byIdErrors, hasLength(1));
      expect(byIdErrors.single, isA<KitSeedException>());

      await sub.cancel();
      await byIdSub.cancel();
    });
  });

  group('slow profile', () {
    const latency = Duration(seconds: 2);

    test('one-shot operations resolve only after the latency', () {
      fakeAsync((async) {
        final repos = makeRepo(const KitSeedProfile.slow(latency));

        var upserted = false;
        repos.repo
            .upsert(const _Widget(id: 'w-1', name: 'Alpha'))
            .then((_) => upserted = true);
        async.flushMicrotasks();
        expect(upserted, isFalse, reason: 'write held by the latency gate');
        async.elapse(latency);
        expect(upserted, isTrue);

        List<_Widget>? got;
        repos.repo.getAll().then((value) => got = value);
        async.flushMicrotasks();
        expect(got, isNull, reason: 'read held by the latency gate');
        async.elapse(latency);
        expect(got, hasLength(1));
        expect(got!.single.name, 'Alpha');
      });
    });

    test('watch emits nothing before the latency, then the rows', () {
      fakeAsync((async) {
        final repos = makeRepo(const KitSeedProfile.slow(latency));
        // Seed through the pass-through writer so setup isn't itself gated.
        repos.seeder
            .upsert(const _Widget(id: 'w-1', name: 'Alpha'))
            .ignore();
        async.flushMicrotasks();

        final emissions = <List<_Widget>>[];
        final sub = repos.repo.watchAll().listen(emissions.add);
        async.flushMicrotasks();
        expect(emissions, isEmpty,
            reason: 'first emission delayed — the loading Read State');
        async.elapse(latency);
        expect(emissions, hasLength(1));
        expect(emissions.single.single.name, 'Alpha');

        sub.cancel().ignore();
        async.flushMicrotasks();
      });
    });
  });
}
