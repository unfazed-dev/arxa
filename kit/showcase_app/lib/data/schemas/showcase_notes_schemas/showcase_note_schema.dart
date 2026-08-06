// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate_data.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:appbox_kit_data/auth/appbox_kit_auth_types.dart';
import 'package:appbox_kit_data/models/appbox_kit_entity_registration.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_model.dart';
import 'package:appbox_kit_showcase_app/data/schemas/showcase_notes_schemas/showcase_note_folder_schema.dart';

const kShowcaseNotesTable = 'notes';

const showcaseNoteSchema = AppBoxKitTableSchema(
  table: kShowcaseNotesTable,
  columns: [
    AppBoxKitColumn.id(),
    AppBoxKitColumn('folder_id', AppBoxKitColumnType.reference,
        references: kShowcaseNoteFoldersTable),
    AppBoxKitColumn('owner', AppBoxKitColumnType.reference, references: kAppBoxKitAuthUsersTable),
    AppBoxKitColumn('body', AppBoxKitColumnType.text),
    AppBoxKitColumn('pinned', AppBoxKitColumnType.boolean),
    AppBoxKitColumn('attachments', AppBoxKitColumnType.jsonb),
    AppBoxKitColumn('deleted_at', AppBoxKitColumnType.timestamptz, nullable: true),
    AppBoxKitColumn('created_at', AppBoxKitColumnType.timestamptz),
    AppBoxKitColumn('updated_at', AppBoxKitColumnType.timestamptz),
  ],
);

final showcaseNoteRegistration = AppBoxKitEntityRegistration<ShowcaseNoteModel>(
  schema: showcaseNoteSchema,
  fromJson: ShowcaseNoteModel.fromJson,
  toJson: (note) => note.toJson(),
);
