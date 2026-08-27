import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../support/post_harness.dart';

/// The repository adapter (phase 4c): `CairnKitRepository<E>` satisfies the
/// kit/data [ArxaKitRepository] port over a cairn `Collection` handle, so the
/// same entity codecs and facades run on cairn unchanged.
///
/// Branches under test:
/// - ID canonicalization on every write and id/reference-targeted read —
///   seed keys (`p-1`) and UUIDs are interchangeable on cairn too.
/// - The read path normalizes the WS2 view encoding (booleans as 0/1, jsonb
///   as JSON text) back into the types the codecs expect.
/// - patch writes ONLY the differing columns (cairn per-field LWW), no-ops
///   write nothing, and a patch on a missing row fails loudly.
/// - watch streams emit the current set immediately, re-emit on writes, and
///   replay the latest set to late listeners (navigation rebuilds).
/// - The tenant-table `user_id` stamping hook fires on upsert only when the
///   row lacks one — PgWriteBack's `auth.uid()` is NULL for local writes.
void main() {
  group('kit.cairn.repository', () {
    test(
      'kit.cairn.repository — upsert canonicalizes ids and returns the stored entity',
      () async {
        // Given a repository over an empty local database
        final h = await bootstrapPostsForTest();

        // When an entity with seed-key ids is upserted
        final stored = await h.repo.upsert(const Post(
          id: 'p-1',
          title: 'hello',
          likes: 0,
          score: 1.5,
          published: false,
          author: 'u-1',
        ));

        // Then the stored entity carries canonical UUIDs
        expect(stored.id, h.ids.canonicalId('posts', 'p-1'));
        expect(stored.author, h.ids.canonicalId('users', 'u-1'));
        // And the row is actually in the store, fetchable by the seed key
        expect(await h.repo.getById('p-1'), stored);
      },
    );

    test(
      'kit.cairn.repository — getById finds by seed key or UUID and misses cleanly',
      () async {
        // Given one stored row
        final h = await bootstrapPostsForTest();
        final stored = await h.repo.upsert(_post('p-1', title: 'hello'));

        // Then both key spellings resolve to it, and an absent row is null
        expect(await h.repo.getById('p-1'), stored);
        expect(await h.repo.getById(stored.id), stored);
        expect(await h.repo.getById('p-absent'), isNull);
      },
    );

    test(
      'kit.cairn.repository — getAll applies filters, order and limit',
      () async {
        // Given three stored rows
        final h = await bootstrapPostsForTest();
        await h.repo.upsertMany([
          _post('p-1', title: 'a', likes: 5, published: true),
          _post('p-2', title: 'b', likes: 10),
          _post('p-3', title: 'c', likes: 20, published: true),
        ]);

        // Then an eq filter selects, a gt filter bounds, order and limit shape
        final published = await h.repo.getAll(
          const ArxaKitQuery(filters: [ArxaKitFilter.eq('published', true)]),
        );
        expect(published.map((p) => p.title), ['a', 'c']);

        final top = await h.repo.getAll(
          const ArxaKitQuery(
            filters: [ArxaKitFilter.gt('likes', 4)],
            orderBy: 'likes',
            descending: true,
            limit: 2,
          ),
        );
        expect(top.map((p) => p.title), ['c', 'b']);

        final scarce = await h.repo.getAll(
          const ArxaKitQuery(filters: [ArxaKitFilter.lt('likes', 6)]),
        );
        expect(scarce.map((p) => p.title), ['a']);
      },
    );

    test(
      'kit.cairn.repository — watchAll emits now, on writes, and replays to late listeners',
      () async {
        // Given an empty table and a first listener
        final h = await bootstrapPostsForTest();
        final first = await h.repo.watchAll().first;
        expect(first, isEmpty);

        // When a write lands, an active listener re-emits
        final seen = h.repo.watchAll().skip(1).first;
        await h.repo.upsert(_post('p-1', title: 'live'));
        expect((await seen).single.title, 'live');

        // Then a LATE listener (mounted after the write — a rebuilt page)
        // still receives the current set without any new write
        final replayed = await h.repo.watchAll().first;
        expect(replayed.single.title, 'live');
      },
    );

    test(
      'kit.cairn.repository — watchById emits the row, null when absent, and changes',
      () async {
        // Given one stored row
        final h = await bootstrapPostsForTest();
        await h.repo.upsert(_post('p-1', title: 'before'));

        // Then the watch emits it immediately
        expect((await h.repo.watchById('p-1').first)?.title, 'before');

        // And an absent id watches as null
        expect(await h.repo.watchById('p-absent').first, isNull);

        // When the row changes, the watch re-emits the new value
        final changed = h.repo.watchById('p-1').skip(1).first;
        final original = (await h.repo.getById('p-1'))!;
        await h.repo.patch(original, original.copyWith(title: 'after'));
        expect((await changed)?.title, 'after');
      },
    );

    test(
      'kit.cairn.repository — patch writes only the diff, so a concurrent edit survives',
      () async {
        // Given a stored row and two readers holding the same original
        final h = await bootstrapPostsForTest();
        await h.repo.upsert(_post('p-1', title: 'orig', likes: 1));
        final alice = (await h.repo.getById('p-1'))!;
        final bob = alice;

        // When Alice patches the title and Bob concurrently patches likes
        await h.repo.patch(alice, alice.copyWith(title: 'alice'));
        await h.repo.patch(bob, bob.copyWith(likes: 42));

        // Then both edits survive — the title write never touched likes
        final stored = (await h.repo.getById('p-1'))!;
        expect(stored.title, 'alice');
        expect(stored.likes, 42);
      },
    );

    test(
      'kit.cairn.repository — a no-op patch writes nothing and returns patched',
      () async {
        // Given a stored row
        final h = await bootstrapPostsForTest();
        await h.repo.upsert(_post('p-1', title: 'same'));
        final original = (await h.repo.getById('p-1'))!;
        final writesBefore = h.engine.writeCalls;

        // When patch is called with no changes
        final result = await h.repo.patch(original, original.copyWith());

        // Then nothing was written and the patched entity is returned as-is
        expect(h.engine.writeCalls, writesBefore);
        expect(result, original);
      },
    );

    test(
      'kit.cairn.repository — patch on a missing row fails loudly',
      () async {
        // Given an entity that was never stored
        final h = await bootstrapPostsForTest();
        const ghost = Post(
          id: 'p-ghost',
          title: 'x',
          likes: 0,
          score: 0,
          published: false,
        );

        // Then patching it throws rather than silently inserting or no-opping
        expect(
          () => h.repo.patch(ghost, ghost.copyWith(title: 'y')),
          throwsStateError,
        );
      },
    );

    test(
      'kit.cairn.repository — delete removes the row and watches observe it',
      () async {
        // Given a stored row and an active watch
        final h = await bootstrapPostsForTest();
        await h.repo.upsert(_post('p-1', title: 'doomed'));
        final gone = h.repo.watchById('p-1').skip(1).first;

        // When the row is deleted by seed key
        await h.repo.delete('p-1');

        // Then the watch observes the removal and the row is gone
        expect(await gone, isNull);
        expect(await h.repo.getById('p-1'), isNull);
      },
    );

    test(
      'kit.cairn.repository — booleans and jsonb round-trip the view encoding',
      () async {
        // Given a row whose bool/jsonb columns cross the json_extract views
        // (served as 0/1 integers and JSON text, never as Dart bool/List)
        final h = await bootstrapPostsForTest();
        await h.repo.upsert(
          _post('p-1', title: 'typed', published: true, tags: ['x', 'y']),
        );

        // Then the decoded entity carries real Dart types
        final stored = (await h.repo.getById('p-1'))!;
        expect(stored.published, isTrue);
        expect(stored.tags, ['x', 'y']);

        // And an eq filter on the bool column still matches
        final published = await h.repo.getAll(
          const ArxaKitQuery(filters: [ArxaKitFilter.eq('published', true)]),
        );
        expect(published.single.published, isTrue);
      },
    );

    test(
      'kit.cairn.repository — upsert stamps user_id only when the row lacks one',
      () async {
        // Given a repository with a tenant id provider
        final h = await bootstrapPostsForTest(userIdProvider: () => 'auth-user-1');

        // When a row without user_id is upserted
        final stamped = await h.repo.upsert(_post('p-1', title: 'mine'));

        // Then the hook stamped it (PgWriteBack auth.uid() is NULL locally)
        expect(stamped.userId, 'auth-user-1');

        // But an explicit user_id is never overwritten
        final kept = await h.repo.upsert(
          _post('p-2', title: 'theirs').copyWith(userId: 'auth-user-2'),
        );
        expect(kept.userId, 'auth-user-2');
      },
    );

    test(
      'kit.cairn.repository — upsertMany batches and returns the stored entities',
      () async {
        // Given an empty table
        final h = await bootstrapPostsForTest();

        // When several entities are upserted at once
        final stored = await h.repo.upsertMany([
          _post('p-1', title: 'a'),
          _post('p-2', title: 'b'),
        ]);

        // Then they landed as ONE batch (local-atomic outbox entry) and the
        // returned entities are the stored rows in input order
        expect(h.engine.writeBatchCalls, 1);
        expect(h.engine.writeCalls, 0);
        expect(stored.map((p) => p.title), ['a', 'b']);
        expect(await h.repo.getAll(), hasLength(2));

        // And an empty batch is a no-op, not an engine call
        expect(await h.repo.upsertMany(const []), isEmpty);
        expect(h.engine.writeBatchCalls, 1);
      },
    );
  });
}

Post _post(
  String id, {
  required String title,
  int likes = 0,
  bool published = false,
  List<String>? tags,
}) =>
    Post(
      id: id,
      title: title,
      likes: likes,
      score: 0,
      published: published,
      tags: tags,
    );
