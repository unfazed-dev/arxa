import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/config/arxa_kit_seed_profile.dart';
import 'package:arxa_kit_data/ids/arxa_kit_id_service.dart';
import 'package:arxa_kit_data/models/arxa_kit_entity_registration.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_persistence.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_repository.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_store.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

/// ArxaKitSeedProfile tests — the Seed Profile machinery (latency + failure
/// injection) every ArxaKitSeedRepository applies.
///
/// Branches under test:
/// - the default profile is a pass-through: `apply` returns the identical
///   stream and every operation behaves exactly as without a profile;
/// - `ArxaKitSeedProfile.failing` throws the typed [ArxaKitSeedException] from every
///   one-shot operation and turns every watch emission into a stream error;
/// - `ArxaKitSeedProfile.slow` holds one-shot results and watch emissions until
///   the latency elapses (fake clock), then delivers them unchanged.
class _Widget {
  final String id;
  final String name;

  const _Widget({required this.id, required this.name});
}

final _schema = ArxaKitTableSchema(
  table: 'widgets',
  columns: const [ArxaKitColumn.id(), ArxaKitColumn('name', ArxaKitColumnType.text)],
);

final _registration = ArxaKitEntityRegistration<_Widget>(
  schema: _schema,
  fromJson: (json) => _Widget(
    id: json['id'] as String,
    name: json['name'] as String,
  ),
  toJson: (w) => {'id': w.id, 'name': w.name},
);

void main() {
  final idService = ArxaKitIdService();

  /// A repo on a shared store, plus a pass-through writer on the same store
  /// so failing-profile setups can still seed rows.
  ({
    ArxaKitSeedRepository<_Widget> repo,
    ArxaKitSeedRepository<_Widget> seeder,
  }) makeRepo([ArxaKitSeedProfile profile = const ArxaKitSeedProfile()]) {
    final store = ArxaKitSeedStore(persistence: ArxaKitNoPersistence());
    return (
      repo: ArxaKitSeedRepository<_Widget>(
        store: store,
        registration: _registration,
        idService: idService,
        profile: profile,
      ),
      seeder: ArxaKitSeedRepository<_Widget>(
        store: store,
        registration: _registration,
        idService: idService,
      ),
    );
  }

  test('kit.data.seed-repos — default profile is a pass-through', () async {
    const profile = ArxaKitSeedProfile();
    final source = Stream<int>.value(1);
    expect(identical(profile.apply(source), source), isTrue,
        reason: 'no injection → the exact source stream is returned');

    final repos = makeRepo();
    await repos.repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));
    expect((await repos.repo.getAll()).single.name, 'Alpha');
    expect((await repos.repo.getById('w-1'))!.name, 'Alpha');
  });

  group('failing profile', () {
    const failure = ArxaKitSeedException('injected backend failure');

    test('kit.data.seed-repos — every one-shot operation throws the typed ArxaKitSeedException', () {
      final repos = makeRepo(const ArxaKitSeedProfile.failing(failure));

      expect(repos.repo.getAll(), throwsA(isA<ArxaKitSeedException>()));
      expect(repos.repo.getById('w-1'), throwsA(isA<ArxaKitSeedException>()));
      expect(
        repos.repo.upsert(const _Widget(id: 'w-1', name: 'Alpha')),
        throwsA(isA<ArxaKitSeedException>()),
      );
      expect(repos.repo.delete('w-1'), throwsA(isA<ArxaKitSeedException>()));
    });

    test('kit.data.seed-repos — watch emissions become stream errors', () async {
      final repos = makeRepo(const ArxaKitSeedProfile.failing(failure));
      await repos.seeder.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

      final errors = <Object>[];
      final sub = repos.repo.watchAll().listen(
            (_) {},
            onError: errors.add,
          );
      await pumpEventQueue();
      expect(errors, hasLength(1));
      expect(errors.single, isA<ArxaKitSeedException>());

      final byIdErrors = <Object>[];
      final byIdSub = repos.repo.watchById('w-1').listen(
            (_) {},
            onError: byIdErrors.add,
          );
      await pumpEventQueue();
      expect(byIdErrors, hasLength(1));
      expect(byIdErrors.single, isA<ArxaKitSeedException>());

      await sub.cancel();
      await byIdSub.cancel();
    });
  });

  group('slow profile', () {
    const latency = Duration(seconds: 2);

    test('kit.data.seed-repos — one-shot operations resolve only after the latency', () {
      fakeAsync((async) {
        final repos = makeRepo(const ArxaKitSeedProfile.slow(latency));

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

    test('kit.data.seed-repos — watch emits nothing before the latency, then the rows', () {
      fakeAsync((async) {
        final repos = makeRepo(const ArxaKitSeedProfile.slow(latency));
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
