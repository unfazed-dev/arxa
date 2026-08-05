// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate_data.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:appbox_kit_data/auth/kit_auth_types.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';

const kShowcaseNotesTable = 'notes';

const showcaseNoteSchema = KitTableSchema(
  table: kShowcaseNotesTable,
  columns: [
    KitColumn.id(),
    KitColumn('folder_id', KitColumnType.reference,
        references: kShowcaseNoteFoldersTable),
    KitColumn('owner', KitColumnType.reference, references: kKitAuthUsersTable),
    KitColumn('body', KitColumnType.text),
    KitColumn('pinned', KitColumnType.boolean),
    KitColumn('attachments', KitColumnType.jsonb),
    KitColumn('deleted_at', KitColumnType.timestamptz, nullable: true),
    KitColumn('created_at', KitColumnType.timestamptz),
    KitColumn('updated_at', KitColumnType.timestamptz),
  ],
);

final showcaseNoteRegistration = KitEntityRegistration<ShowcaseNoteModel>(
  schema: showcaseNoteSchema,
  fromJson: ShowcaseNoteModel.fromJson,
  toJson: (note) => note.toJson(),
);
