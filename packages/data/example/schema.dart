/// Sample [KitTableSchema] descriptors for `example/generate.dart`.
///
/// `products` demonstrates every column kind the emitters handle: a
/// `reference` to `categories`, a nullable `jsonb` list, and a nullable
/// `timestamptz`.
library;

import 'package:appbox_kit_data/schema/kit_table_schema.dart';

const KitTableSchema categoriesSchema = KitTableSchema(
  table: 'categories',
  columns: [
    KitColumn.id(),
    KitColumn('name', KitColumnType.text),
  ],
);

const KitTableSchema productsSchema = KitTableSchema(
  table: 'products',
  columns: [
    KitColumn.id(),
    KitColumn('name', KitColumnType.text),
    KitColumn('price', KitColumnType.real),
    KitColumn(
      'category',
      KitColumnType.reference,
      references: 'categories',
    ),
    KitColumn('tags', KitColumnType.jsonb, nullable: true),
    KitColumn('created_at', KitColumnType.timestamptz, nullable: true),
  ],
);

/// Referenced tables (`categories`) come before their dependents
/// (`products`); the emitters re-derive this order themselves, so the
/// declaration order here is for readability only.
final List<KitTableSchema> exampleSchemas = [
  categoriesSchema,
  productsSchema,
];
