import '../schema/arxa_kit_table_schema.dart';

/// The codec binding an entity type to its table: how `T` maps onto the wire
/// shape described by [schema]. The host declares one per entity and passes
/// them to `ArxaKitData.initialize`.
class ArxaKitEntityRegistration<T> {
  final ArxaKitTableSchema schema;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T entity) toJson;

  const ArxaKitEntityRegistration({
    required this.schema,
    required this.fromJson,
    required this.toJson,
  });

  /// Reifies `T` for callers holding a `ArxaKitEntityRegistration<dynamic>` —
  /// `ArxaKitData.initialize` uses this to construct and register
  /// `ArxaKitRepository<T>` without knowing `T` statically.
  R apply<R>(R Function<E>(ArxaKitEntityRegistration<E> registration) fn) =>
      fn<T>(this);
}
