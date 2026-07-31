/// Deliberately tiny query surface — swap rule 2.
///
/// Every operator here is satisfiable single-table on the seed store, on
/// Supabase `.stream()`, and on Appwrite TablesDB queries. Joins and
/// aggregates are facade-service work (`.map()` over streams), never query
/// work, so repositories stay portable across backends.
library;

enum KitFilterOp { eq, gt, lt }

class KitFilter {
  final String column;
  final KitFilterOp op;
  final Object value;

  const KitFilter(this.column, this.op, this.value);

  const KitFilter.eq(String column, Object value)
      : this(column, KitFilterOp.eq, value);
  const KitFilter.gt(String column, Object value)
      : this(column, KitFilterOp.gt, value);
  const KitFilter.lt(String column, Object value)
      : this(column, KitFilterOp.lt, value);
}

class KitQuery {
  final List<KitFilter> filters;
  final String? orderBy;
  final bool descending;
  final int? limit;

  const KitQuery({
    this.filters = const [],
    this.orderBy,
    this.descending = false,
    this.limit,
  });
}
