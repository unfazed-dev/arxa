import '../schema/kit_table_schema.dart';

/// The codec binding an entity type to its table: how `T` maps onto the wire
/// shape described by [schema]. The host declares one per entity and passes
/// them to `KitData.initialize`.
class KitEntityRegistration<T> {
  final KitTableSchema schema;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T entity) toJson;

  const KitEntityRegistration({
    required this.schema,
    required this.fromJson,
    required this.toJson,
  });

  /// Reifies `T` for callers holding a `KitEntityRegistration<dynamic>` —
  /// `KitData.initialize` uses this to construct and register
  /// `KitRepository<T>` without knowing `T` statically.
  R apply<R>(R Function<E>(KitEntityRegistration<E> registration) fn) =>
      fn<T>(this);
}
