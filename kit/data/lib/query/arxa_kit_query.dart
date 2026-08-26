/// Deliberately tiny query surface — swap rule 2.
///
/// Every operator here is satisfiable single-table on the seed store, on
/// Supabase `.stream()`, and on Appwrite TablesDB queries. Joins and
/// aggregates are facade-service work (`.map()` over streams), never query
/// work, so repositories stay portable across backends.
library;

enum ArxaKitFilterOp { eq, gt, lt }

class ArxaKitFilter {
  final String column;
  final ArxaKitFilterOp op;
  final Object value;

  const ArxaKitFilter(this.column, this.op, this.value);

  const ArxaKitFilter.eq(String column, Object value)
      : this(column, ArxaKitFilterOp.eq, value);
  const ArxaKitFilter.gt(String column, Object value)
      : this(column, ArxaKitFilterOp.gt, value);
  const ArxaKitFilter.lt(String column, Object value)
      : this(column, ArxaKitFilterOp.lt, value);
}

class ArxaKitQuery {
  final List<ArxaKitFilter> filters;
  final String? orderBy;
  final bool descending;
  final int? limit;

  const ArxaKitQuery({
    this.filters = const [],
    this.orderBy,
    this.descending = false,
    this.limit,
  });
}
