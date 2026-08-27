import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../support/post_harness.dart';

/// The CRDT capability (phase 4d): `CairnKitRepository` implements
/// [ArxaKitCrdtCapable] so facade services feature-detect
/// (`repo is ArxaKitCrdtCapable`) instead of hard-casting to cairn types.
///
/// Branches under test:
/// - adjustCounter routes by sign onto cairn's counterIncrement /
///   counterDecrement with the canonical pk; a zero delta writes nothing.
/// - orSetAdd / orSetRemove delegate table, canonical pk, and element.
/// - Verbs on a table NOT declared in ArxaKitCairnConfig throw a StateError
///   naming the config field — the client side of the triple-consistency
///   rule (config ↔ server env ↔ schema flags).
void main() {
  group('kit.cairn.crdt', () {
    test(
      'kit.cairn.crdt — the repository feature-detects as ArxaKitCrdtCapable',
      () async {
        // Given a cairn-backed repository resolved through the port type
        final h = await bootstrapPostsForTest(
          orSetTables: {'posts'},
          counterTables: {'posts'},
        );
        final ArxaKitRepository<Post> port = h.repo;

        // Then a service can feature-detect the CRDT verbs without a cast
        expect(port, isA<ArxaKitCrdtCapable>());
      },
    );

    test(
      'kit.cairn.crdt — adjustCounter routes by sign with the canonical pk',
      () async {
        // Given a counter-tagged table with one row
        final h = await bootstrapPostsForTest(counterTables: {'posts'});
        final stored = await h.repo.upsert(
          const Post(
            id: 'p-1',
            title: 'x',
            likes: 0,
            score: 0,
            published: false,
          ),
        );

        // When the counter is adjusted up and down
        final crdt = h.repo as ArxaKitCrdtCapable;
        await crdt.adjustCounter('p-1', 3);
        await crdt.adjustCounter(stored.id, -1);

        // Then the engine saw increment(3) and decrement(1) on the canonical pk
        expect(h.engine.counterIncrementCalls.single.value, 3);
        expect(h.engine.counterIncrementCalls.single.pk, stored.id);
        expect(h.engine.counterDecrementCalls.single.value, 1);
        expect(h.engine.counterDecrementCalls.single.pk, stored.id);
      },
    );

    test(
      'kit.cairn.crdt — a zero delta writes nothing',
      () async {
        // Given a counter-tagged table
        final h = await bootstrapPostsForTest(counterTables: {'posts'});

        // When a zero adjustment is requested
        await (h.repo as ArxaKitCrdtCapable).adjustCounter('p-1', 0);

        // Then no engine verb fired
        expect(h.engine.counterIncrementCalls, isEmpty);
        expect(h.engine.counterDecrementCalls, isEmpty);
      },
    );

    test(
      'kit.cairn.crdt — or-set verbs delegate table, canonical pk and element',
      () async {
        // Given an or-set-tagged table
        final h = await bootstrapPostsForTest(orSetTables: {'posts'});
        final crdt = h.repo as ArxaKitCrdtCapable;

        // When an element is added and removed by seed key
        await crdt.orSetAdd('p-1', 'urgent');
        await crdt.orSetRemove('p-1', 'urgent');

        // Then the engine saw both with the canonical pk
        final pk = h.ids.canonicalId('posts', 'p-1');
        expect(h.engine.orSetAddCalls.single.pk, pk);
        expect(h.engine.orSetAddCalls.single.value, 'urgent');
        expect(h.engine.orSetRemoveCalls.single.pk, pk);
        expect(h.engine.orSetRemoveCalls.single.value, 'urgent');
      },
    );

    test(
      'kit.cairn.crdt — undeclared tables fail loudly naming the config field',
      () async {
        // Given a repository whose config declares NO crdt tables
        final h = await bootstrapPostsForTest();
        final crdt = h.repo as ArxaKitCrdtCapable;

        // Then every verb names the missing config field
        expect(
          () => crdt.adjustCounter('p-1', 1),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('counterTables'))),
        );
        expect(
          () => crdt.orSetAdd('p-1', 'x'),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('orSetTables'))),
        );
      },
    );
  });
}
