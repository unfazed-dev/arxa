/// Deliberately tiny query surface — swap rule 2.
///
/// Every operator here is satisfiable single-table on the seed store, on
/// Supabase `.stream()`, and on Appwrite TablesDB queries. Joins and
/// aggregates are facade-service work (`.map()` over streams), never query
/// work, so repositories stay portable across backends.
library;

enum AppBoxKitFilterOp { eq, gt, lt }

class AppBoxKitFilter {
  final String column;
  final AppBoxKitFilterOp op;
  final Object value;

  const AppBoxKitFilter(this.column, this.op, this.value);

  const AppBoxKitFilter.eq(String column, Object value)
      : this(column, AppBoxKitFilterOp.eq, value);
  const AppBoxKitFilter.gt(String column, Object value)
      : this(column, AppBoxKitFilterOp.gt, value);
  const AppBoxKitFilter.lt(String column, Object value)
      : this(column, AppBoxKitFilterOp.lt, value);
}

class AppBoxKitQuery {
  final List<AppBoxKitFilter> filters;
  final String? orderBy;
  final bool descending;
  final int? limit;

  const AppBoxKitQuery({
    this.filters = const [],
    this.orderBy,
    this.descending = false,
    this.limit,
  });
}
