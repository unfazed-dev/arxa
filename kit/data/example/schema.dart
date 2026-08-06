/// Sample [AppBoxKitTableSchema] descriptors for `example/generate.dart`.
///
/// `products` demonstrates every column kind the emitters handle: a
/// `reference` to `categories`, a nullable `jsonb` list, and a nullable
/// `timestamptz`.
library;

import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';

const AppBoxKitTableSchema categoriesSchema = AppBoxKitTableSchema(
  table: 'categories',
  columns: [
    AppBoxKitColumn.id(),
    AppBoxKitColumn('name', AppBoxKitColumnType.text),
  ],
);

const AppBoxKitTableSchema productsSchema = AppBoxKitTableSchema(
  table: 'products',
  columns: [
    AppBoxKitColumn.id(),
    AppBoxKitColumn('name', AppBoxKitColumnType.text),
    AppBoxKitColumn('price', AppBoxKitColumnType.real),
    AppBoxKitColumn(
      'category',
      AppBoxKitColumnType.reference,
      references: 'categories',
    ),
    AppBoxKitColumn('tags', AppBoxKitColumnType.jsonb, nullable: true),
    AppBoxKitColumn('created_at', AppBoxKitColumnType.timestamptz, nullable: true),
  ],
);

/// Referenced tables (`categories`) come before their dependents
/// (`products`); the emitters re-derive this order themselves, so the
/// declaration order here is for readability only.
final List<AppBoxKitTableSchema> exampleSchemas = [
  categoriesSchema,
  productsSchema,
];
