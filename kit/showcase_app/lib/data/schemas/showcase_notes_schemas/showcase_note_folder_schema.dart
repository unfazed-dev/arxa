// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate_data.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:appbox_kit_data/auth/kit_auth_types.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';

const kShowcaseNoteFoldersTable = 'notes_folders';

const showcaseNoteFolderSchema = KitTableSchema(
  table: kShowcaseNoteFoldersTable,
  columns: [
    KitColumn.id(),
    KitColumn('name', KitColumnType.text),
    KitColumn('sort_order', KitColumnType.integer),
    // References the reserved auth users table: exists as a real seed-store
    // table locally, as an id namespace everywhere. Phase-2 ceiling: the SQL
    // emitter will emit a FK to "kit_auth_users", which on Supabase should be
    // mapped to auth.users (or the FK dropped) by the operator.
    KitColumn('owner', KitColumnType.reference, references: kKitAuthUsersTable),
    KitColumn('created_at', KitColumnType.timestamptz),
  ],
);

final showcaseNoteFolderRegistration =
    KitEntityRegistration<ShowcaseNoteFolderModel>(
  schema: showcaseNoteFolderSchema,
  fromJson: ShowcaseNoteFolderModel.fromJson,
  toJson: (folder) => folder.toJson(),
);
