import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

/// The cairn schema emitter (phase 4b): turns kit schema descriptors into the
/// cairn client schema the backend opens with, plus the server-side CRDT env
/// declaration snippet so client flags, client config, and server env cannot
/// drift silently (triple consistency).
///
/// Branches under test:
/// - Every kit column type maps onto the cairn affinity the read-views
///   actually serve: id/text/timestamptz/reference/jsonb read as TEXT,
///   integer/boolean read as INTEGER (json_extract booleans are 0/1), real
///   reads as REAL.
/// - The kit table name and its `id` primary key carry across.
/// - `crdt:`-flagged columns become `table:column` entries in the emitted
///   CAIRN_COUNTER_COLUMNS / CAIRN_OR_SET_COLUMNS snippet; unflagged schemas
///   emit both envs empty.
void main() {
  const posts = ArxaKitTableSchema(
    table: 'posts',
    columns: [
      ArxaKitColumn.id(),
      ArxaKitColumn('title', ArxaKitColumnType.text),
      ArxaKitColumn('body', ArxaKitColumnType.text, nullable: true),
      ArxaKitColumn('likes', ArxaKitColumnType.integer,
          crdt: ArxaKitCrdtTier.counter),
      ArxaKitColumn('score', ArxaKitColumnType.real),
      ArxaKitColumn('published', ArxaKitColumnType.boolean),
      ArxaKitColumn('createdAt', ArxaKitColumnType.timestamptz),
      ArxaKitColumn('tags', ArxaKitColumnType.jsonb, nullable: true,
          crdt: ArxaKitCrdtTier.orSet),
      ArxaKitColumn('author', ArxaKitColumnType.reference,
          references: 'users'),
    ],
  );
  const users = ArxaKitTableSchema(
    table: 'users',
    columns: [ArxaKitColumn.id(), ArxaKitColumn('name', ArxaKitColumnType.text)],
  );

  group('kit.cairn.emitter', () {
    test(
      'kit.cairn.emitter — every kit column type maps onto the view affinity',
      () {
        // When the kit schema is emitted as a cairn schema
        final schema = CairnSchemaEmitter().schemaFor(const [posts, users]);

        // Then both tables carry their names and id primary key
        expect(schema.tables.map((t) => t.name), ['posts', 'users']);
        expect(schema.tables.first.primaryKey, ['id']);

        // And each column lands on the affinity the WS2 view serves
        final columns = {
          for (final c in schema.tables.first.columns) c.name: c.affinity,
        };
        expect(columns, {
          'id': 'TEXT',
          'title': 'TEXT',
          'body': 'TEXT',
          'likes': 'INTEGER',
          'score': 'REAL',
          'published': 'INTEGER', // json_extract booleans arrive as 0/1
          'createdAt': 'TEXT', // timestamptz travels as ISO-8601 text
          'tags': 'TEXT', // jsonb arrives as JSON text
          'author': 'TEXT', // references are canonical UUID strings
        });
      },
    );

    test(
      'kit.cairn.emitter — flagged columns become table:column server env entries',
      () {
        // When the server declaration is emitted for the flagged schema
        final snippet = CairnSchemaEmitter().emitServerCrdtEnv(const [posts]);

        // Then it is stamped generated and lists each tier's table:column pairs
        expect(snippet, contains('Do not edit by hand'));
        expect(snippet, contains('CAIRN_COUNTER_COLUMNS=posts:likes'));
        expect(snippet, contains('CAIRN_OR_SET_COLUMNS=posts:tags'));
      },
    );

    test(
      'kit.cairn.emitter — an unflagged schema emits empty server envs',
      () {
        // When no column carries a tier
        final snippet = CairnSchemaEmitter().emitServerCrdtEnv(const [users]);

        // Then both env declarations are present but empty (deterministic
        // output — a diff shows exactly what changed between generations)
        expect(snippet, contains('CAIRN_COUNTER_COLUMNS=\n'));
        expect(snippet, contains('CAIRN_OR_SET_COLUMNS=\n'));
      },
    );
  });
}
