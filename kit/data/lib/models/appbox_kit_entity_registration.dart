import '../schema/appbox_kit_table_schema.dart';

/// The codec binding an entity type to its table: how `T` maps onto the wire
/// shape described by [schema]. The host declares one per entity and passes
/// them to `AppBoxKitData.initialize`.
class AppBoxKitEntityRegistration<T> {
  final AppBoxKitTableSchema schema;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T entity) toJson;

  const AppBoxKitEntityRegistration({
    required this.schema,
    required this.fromJson,
    required this.toJson,
  });

  /// Reifies `T` for callers holding a `AppBoxKitEntityRegistration<dynamic>` —
  /// `AppBoxKitData.initialize` uses this to construct and register
  /// `AppBoxKitRepository<T>` without knowing `T` statically.
  R apply<R>(R Function<E>(AppBoxKitEntityRegistration<E> registration) fn) =>
      fn<T>(this);
}
