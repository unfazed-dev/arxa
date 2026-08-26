/// Sample [ArxaKitTableSchema] descriptors for `example/generate.dart`.
///
/// `products` demonstrates every column kind the emitters handle: a
/// `reference` to `categories`, a nullable `jsonb` list, and a nullable
/// `timestamptz`.
library;

import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

const ArxaKitTableSchema categoriesSchema = ArxaKitTableSchema(
  table: 'categories',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('name', ArxaKitColumnType.text),
  ],
);

const ArxaKitTableSchema productsSchema = ArxaKitTableSchema(
  table: 'products',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('name', ArxaKitColumnType.text),
    ArxaKitColumn('price', ArxaKitColumnType.real),
    ArxaKitColumn(
      'category',
      ArxaKitColumnType.reference,
      references: 'categories',
    ),
    ArxaKitColumn('tags', ArxaKitColumnType.jsonb, nullable: true),
    ArxaKitColumn('created_at', ArxaKitColumnType.timestamptz, nullable: true),
  ],
);

/// Referenced tables (`categories`) come before their dependents
/// (`products`); the emitters re-derive this order themselves, so the
/// declaration order here is for readability only.
final List<ArxaKitTableSchema> exampleSchemas = [
  categoriesSchema,
  productsSchema,
];
