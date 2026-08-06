// Targeted imports (not the barrel) keep this file pure-Dart so
// `tool/generate_data.dart` can compile it as a CLI — the barrel pulls in the
// Supabase/Appwrite clients and their FFI deps.
import 'package:appbox_kit_data/auth/appbox_kit_auth_types.dart';
import 'package:appbox_kit_data/models/appbox_kit_entity_registration.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';

import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/showcase_note_folder_model.dart';

const kShowcaseNoteFoldersTable = 'notes_folders';

const showcaseNoteFolderSchema = AppBoxKitTableSchema(
  table: kShowcaseNoteFoldersTable,
  columns: [
    AppBoxKitColumn.id(),
    AppBoxKitColumn('name', AppBoxKitColumnType.text),
    AppBoxKitColumn('sort_order', AppBoxKitColumnType.integer),
    // References the reserved auth users table: exists as a real seed-store
    // table locally, as an id namespace everywhere. Phase-2 ceiling: the SQL
    // emitter will emit a FK to "kit_auth_users", which on Supabase should be
    // mapped to auth.users (or the FK dropped) by the operator.
    AppBoxKitColumn('owner', AppBoxKitColumnType.reference, references: kAppBoxKitAuthUsersTable),
    AppBoxKitColumn('created_at', AppBoxKitColumnType.timestamptz),
  ],
);

final showcaseNoteFolderRegistration =
    AppBoxKitEntityRegistration<ShowcaseNoteFolderModel>(
  schema: showcaseNoteFolderSchema,
  fromJson: ShowcaseNoteFolderModel.fromJson,
  toJson: (folder) => folder.toJson(),
);
