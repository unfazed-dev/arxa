import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/emitters/arxa_kit_supabase_sql_emitter.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

/// The optional CRDT tier on [ArxaKitColumn] (phase 4 of the cairn kit chain):
/// cairn's counter / or-set columns merge instead of last-writer-wins, and the
/// tier must be declared on the schema so the cairn kit's emitter can stamp the
/// matching server env (`CAIRN_COUNTER_COLUMNS` / `CAIRN_OR_SET_COLUMNS`) —
/// client, server, and schema cannot then drift silently.
///
/// Branches under test:
/// - The tier defaults to absent — every existing schema keeps compiling and
///   meaning the same thing (backward-compatible add).
/// - A flagged column round-trips its tier for the cairn emitter to read.
/// - The flag is inert for the other backends: the Supabase SQL emitter
///   renders the column exactly as if it were unflagged.
void main() {
  group('kit.data.schema crdt', () {
    test(
      'kit.data.schema — a column carries no CRDT tier unless flagged',
      () {
        // Given a plain column and a flagged column
        const plain = ArxaKitColumn('likes', ArxaKitColumnType.integer);
        const flagged = ArxaKitColumn(
          'likes',
          ArxaKitColumnType.integer,
          crdt: ArxaKitCrdtTier.counter,
        );

        // Then the tier defaults to null and survives construction
        expect(plain.crdt, isNull);
        expect(flagged.crdt, ArxaKitCrdtTier.counter);
      },
    );

    test(
      'kit.data.schema — the supabase SQL emitter ignores the CRDT tier',
      () {
        // Given two schemas identical but for the tier flag
        const unflagged = ArxaKitTableSchema(
          table: 'posts',
          columns: [
            ArxaKitColumn.id(),
            ArxaKitColumn('likes', ArxaKitColumnType.integer),
          ],
        );
        const flagged = ArxaKitTableSchema(
          table: 'posts',
          columns: [
            ArxaKitColumn.id(),
            ArxaKitColumn(
              'likes',
              ArxaKitColumnType.integer,
              crdt: ArxaKitCrdtTier.counter,
            ),
          ],
        );

        // Then both emit byte-identical SQL — the flag is cairn-only
        expect(
          ArxaKitSupabaseSqlEmitter().emit(const [flagged]),
          ArxaKitSupabaseSqlEmitter().emit(const [unflagged]),
        );
      },
    );
  });
}
