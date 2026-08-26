// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate_data.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:arxa_kit_data/auth/arxa_kit_auth_types.dart';
import 'package:arxa_kit_data/models/arxa_kit_entity_registration.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:arxa_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';

const kShowcaseNotesTable = 'notes';

const showcaseNoteSchema = ArxaKitTableSchema(
  table: kShowcaseNotesTable,
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('folder_id', ArxaKitColumnType.reference,
        references: kShowcaseNoteFoldersTable),
    ArxaKitColumn('owner', ArxaKitColumnType.reference,
        references: kArxaKitAuthUsersTable),
    ArxaKitColumn('body', ArxaKitColumnType.text),
    ArxaKitColumn('pinned', ArxaKitColumnType.boolean),
    ArxaKitColumn('attachments', ArxaKitColumnType.jsonb),
    ArxaKitColumn('deleted_at', ArxaKitColumnType.timestamptz,
        nullable: true),
    ArxaKitColumn('created_at', ArxaKitColumnType.timestamptz),
    ArxaKitColumn('updated_at', ArxaKitColumnType.timestamptz),
  ],
);

final showcaseNoteRegistration = ArxaKitEntityRegistration<ShowcaseNoteModel>(
  schema: showcaseNoteSchema,
  fromJson: ShowcaseNoteModel.fromJson,
  toJson: (note) => note.toJson(),
);
