# Warehouse Inventory — the arxa way, on cairn

How an arxa-produced Flutter app builds a warehouse inventory feature with cairn as the
sync/persistence backend. Same layering as the showcase app (`kit/showcase_app`):

```
View  →  ViewModel (stacked)  →  Facade service  →  Repository service  →  ArxaKitRepository<T>
                                                                              └─ CairnKitRepository<T> (adapter)
                                                                                   └─ cairn_flutter (SQLite on-device, sync to Postgres)
```

Rules preserved from the kit:
- ViewModels talk ONLY to the facade.
- Facade owns derived streams (rxdart) + every mutation goes through `mutate()` → ActionHub
  busy/error/snackbar automation.
- Repository service owns `ArxaKitQuery` construction and id minting; never aggregates.
- Backend swap happens at ONE seam: `ArxaKitRepository<T>`. Supabase → cairn is a locator
  registration change, nothing above the seam moves.
- Offline/no-database users: cairn runs local-only on its on-device SQLite; when a sync
  endpoint exists it connects. Facade/VM code is identical in both modes.

---

## 1. Model — `lib/data/models/warehouse_models/warehouse_item_model.dart`

```dart
class WarehouseItemModel {
  final String id;          // minted by repository service
  final String sku;
  final String name;
  final String location;    // aisle/bin, e.g. "A3-14"
  final int qty;            // cairn counter column — merges concurrent adjustments
  final int minStock;
  final bool isArchived;    // soft delete (trash/restore), hard delete purges
  final DateTime updatedAt;

  const WarehouseItemModel({
    required this.id,
    required this.sku,
    required this.name,
    required this.location,
    this.qty = 0,
    this.minStock = 0,
    this.isArchived = false,
    required this.updatedAt,
  });

  WarehouseItemModel copyWith({...}) => ...;

  factory WarehouseItemModel.fromMap(Map<String, Object?> m) => ...;
  Map<String, Object?> toMap() => {...};
}
```

## 2. Schema — `lib/data/schemas/warehouse_schemas/warehouse_item_schema.dart`

cairn payloads are schema-less JSON in `cairn_data`; declaring the schema materializes the
per-table view AND opts columns into CRDT tiers. `qty` is a counter column
(`counter_tables` / `CAIRN_COUNTER_COLUMNS` must match server-side).

```dart
final warehouseItemSchema = CairnTable(
  name: 'warehouse_items',
  columns: [
    CairnColumn.text('sku'),
    CairnColumn.text('name'),
    CairnColumn.text('location'),
    CairnColumn.counter('qty'),        // concurrent scanners merge, no lost updates
    CairnColumn.integer('min_stock'),
    CairnColumn.boolean('is_archived'),
    CairnColumn.text('updated_at'),
  ],
);
```

## 3. Backend adapter — `CairnKitRepository<T>` implements `ArxaKitRepository<T>`

One generic class for the whole app (sibling of the supabase/appwrite/seed adapters in
`kit/data/lib/repositories/`). Registered by `ArxaKitData.initialize` when the backend
config says cairn.

```dart
class CairnKitRepository<T> implements ArxaKitRepository<T> {
  CairnKitRepository(this._db, this._table, this._fromMap, this._toMap);

  final CairnDatabase _db;
  final String _table;
  final T Function(Map<String, Object?>) _fromMap;
  final Map<String, Object?> Function(T) _toMap;

  @override
  Future<T?> getById(String id) async {
    final row = await _db.fetchById(_table, id);
    return row == null ? null : _fromMap(row);
  }

  @override
  Future<List<T>> getAll([ArxaKitQuery query = const ArxaKitQuery()]) async =>
      (await _db.getAllMapped(_table, where: query.toSql(), orderBy: query.orderSql(),
          limit: query.limit)).map(_fromMap).toList();

  @override
  Stream<T?> watchById(String id) =>
      _db.watchMapped(_table, where: 'id = ?', args: [id])   // push-invalidation, no polling
          .map((rows) => rows.isEmpty ? null : _fromMap(rows.first));

  @override
  Stream<List<T>> watchAll([ArxaKitQuery query = const ArxaKitQuery()]) =>
      _db.watchMapped(_table, where: query.toSql(), orderBy: query.orderSql())
          .map((rows) => rows.map(_fromMap).toList());

  @override
  Future<T> upsert(T entity) async {
    await _db.upsert(_table, _toMap(entity));
    return entity;
  }

  @override
  Future<List<T>> upsertMany(List<T> entities) async {
    await _db.writeBatch([for (final e in entities) CairnWrite.upsert(_table, _toMap(e))]);
    return entities;
  }

  @override
  Future<T> patch(T original, T patched) async {
    // Diff original vs patched; only changed columns hit storage → a concurrent
    // edit to any OTHER column survives (kit patch contract == cairn LWW per-field).
    final diff = _diff(_toMap(original), _toMap(patched));
    if (diff.isNotEmpty) await _db.patch(_table, (_toMap(original))['id'] as String, diff);
    return patched;
  }

  @override
  Future<void> delete(String id) => _db.delete(_table, id);

  // cairn extras surfaced past the generic seam (repository services may cast):
  Future<void> adjustCounter(String id, String column, int delta) =>
      delta >= 0
          ? _db.counterIncrement(_table, id, column, delta)
          : _db.counterDecrement(_table, id, column, -delta);
}
```

## 4. Repository service — `lib/services/warehouse_services/repositories/warehouse_items_repository_service.dart`

```dart
/// The warehouse items repository — app-level persistence seam. Owns query
/// construction and id minting; raw single-table reads/writes only. Never
/// aggregates (counts/low-stock/sections live in the facade).
class WarehouseItemsRepositoryService {
  ArxaKitRepository<WarehouseItemModel> get _repo =>
      arxaKitLocator<ArxaKitRepository<WarehouseItemModel>>();
  ArxaKitIdService get _ids => arxaKitLocator<ArxaKitIdService>();

  // ── streams ────────────────────────────────────────────────
  Stream<List<WarehouseItemModel>> watchActive() => _repo.watchAll(const ArxaKitQuery(
        filters: [ArxaKitFilter('is_archived', ArxaKitFilterOp.eq, false)],
        orderBy: 'name',
      ));

  Stream<List<WarehouseItemModel>> watchArchived() => _repo.watchAll(const ArxaKitQuery(
        filters: [ArxaKitFilter('is_archived', ArxaKitFilterOp.eq, true)],
        orderBy: 'updated_at', descending: true,
      ));

  Stream<WarehouseItemModel?> watchItem(String id) => _repo.watchById(id);

  // ── actions ────────────────────────────────────────────────
  Future<WarehouseItemModel> createItem({
    required String sku, required String name, required String location,
    int qty = 0, int minStock = 0, 
  }) =>
      _repo.upsert(WarehouseItemModel(
        id: _ids.mint(), sku: sku, name: name, location: location,
        qty: qty, minStock: minStock, updatedAt: DateTime.now().toUtc(),
      ));

  Future<WarehouseItemModel> patchItem(
          WarehouseItemModel original, WarehouseItemModel patched) =>
      _repo.patch(original, patched);

  /// CRDT counter — safe under concurrent scanners at different bins.
  Future<void> adjustQty(String id, int delta) =>
      (_repo as CairnKitRepository<WarehouseItemModel>).adjustCounter(id, 'qty', delta);

  Future<void> deleteForever(String id) => _repo.delete(id);
}
```

## 5. Facade — `lib/services/warehouse_services/facades/warehouse_facade_service.dart`

```dart
/// The warehouse facade — the only service layer viewmodels talk to. Adds
/// derived composition (sections by location, low-stock alerts, search) and
/// routes every mutation through [mutate] for busy/error/snackbar automation.
class WarehouseFacadeService extends ArxaKitDataFacade {
  WarehouseItemsRepositoryService get _repo =>
      arxaKitLocator<WarehouseItemsRepositoryService>();

  // ── UI-state subjects (facade-owned, disposed with the facade) ─────────
  late final BehaviorSubject<String> searchTerm$ =
      registerSubject(BehaviorSubject.seeded(''));

  // ── derived streams (aggregation lives HERE, never in the repository) ──
  late final Stream<List<WarehouseItemModel>> items$ = Rx.combineLatest2(
    _repo.watchActive(),
    searchTerm$.debounceTime(const Duration(milliseconds: 200)),
    (List<WarehouseItemModel> items, String term) => term.isEmpty
        ? items
        : items.where((i) =>
            i.name.toLowerCase().contains(term.toLowerCase()) ||
            i.sku.toLowerCase().contains(term.toLowerCase())).toList(),
  );

  late final Stream<Map<String, List<WarehouseItemModel>>> byLocation$ =
      items$.map((items) => groupBy(items, (i) => i.location));

  late final Stream<List<WarehouseItemModel>> lowStock$ =
      items$.map((items) => items.where((i) => i.qty <= i.minStock).toList());

  late final Stream<int> totalUnits$ =
      items$.map((items) => items.fold(0, (sum, i) => sum + i.qty));

  Stream<List<WarehouseItemModel>> get archived$ = _repo.watchArchived();

  // ── C ──────────────────────────────────────────────────────
  Future<WarehouseItemModel> createItem({
    required String sku, required String name, required String location,
    int qty = 0, int minStock = 0,
  }) =>
      mutate(
        () => _repo.createItem(sku: sku, name: name, location: location,
            qty: qty, minStock: minStock),
        name: 'create', entity: sku,
        error: 'Could not create the item',
      );

  // ── U ──────────────────────────────────────────────────────
  Future<WarehouseItemModel> renameItem(WarehouseItemModel item, String name) =>
      mutate(
        // patch, not upsert: only `name` is written — a concurrent qty
        // adjustment on another device survives.
        () => _repo.patchItem(item, item.copyWith(name: name)),
        name: 'rename', entity: item.id,
        error: 'Could not rename the item',
      );

  Future<WarehouseItemModel> moveItem(WarehouseItemModel item, String location) =>
      mutate(
        () => _repo.patchItem(item, item.copyWith(location: location)),
        name: 'move', entity: item.id,
        error: 'Could not move the item',
      );

  /// Receive or pick stock. CRDT counter: two scanners adjusting the same
  /// SKU offline both land; qty converges to the true total after sync.
  Future<void> adjustStock(WarehouseItemModel item, int delta) => mutate(
        () => _repo.adjustQty(item.id, delta),
        name: 'adjust', entity: item.id,
        error: 'Stock adjustment failed',
      );

  // ── D (trash / restore / purge — mirrors the notes facade) ─
  Future<WarehouseItemModel> archiveItem(WarehouseItemModel item) => mutate(
        () => _repo.patchItem(item, item.copyWith(isArchived: true)),
        name: 'archive', entity: item.id,
        error: 'Could not archive the item',
        success: 'Item moved to archive',
      );

  Future<WarehouseItemModel> restoreItem(WarehouseItemModel item) => mutate(
        () => _repo.patchItem(item, item.copyWith(isArchived: false)),
        name: 'restore', entity: item.id,
        error: 'Could not restore the item',
      );

  Future<void> deleteForever(WarehouseItemModel item) => mutate(
        () => _repo.deleteForever(item.id),
        name: 'purge', entity: item.id,
        error: 'Could not delete the item',
        success: 'Item deleted',
      );
}
```

## 6. ViewModel — `lib/ui/views/warehouse_shell/warehouse_inventory/warehouse_inventory_viewmodel.dart`

```dart
/// The inventory viewmodel — binds facade streams for the list surface and
/// forwards user intents. No aggregation, no persistence, no queries.
class WarehouseInventoryViewModel extends ArxaKitViewModel {
  WarehouseFacadeService get _warehouse => arxaKitLocator<WarehouseFacadeService>();

  List<WarehouseItemModel> items = [];
  List<WarehouseItemModel> lowStock = [];
  int totalUnits = 0;

  void onModelReady() {
    listenTo(_warehouse.items$, (v) { items = v; notifyListeners(); });
    listenTo(_warehouse.lowStock$, (v) { lowStock = v; notifyListeners(); });
    listenTo(_warehouse.totalUnits$, (v) { totalUnits = v; notifyListeners(); });
  }

  void onSearchChanged(String term) => _warehouse.searchTerm$.add(term);

  // Hot sends — facade mutations are already running; VM never awaits for UI.
  void addItem(String sku, String name, String location) =>
      _warehouse.createItem(sku: sku, name: name, location: location);
  void receive(WarehouseItemModel item, int units) => _warehouse.adjustStock(item, units);
  void pick(WarehouseItemModel item, int units) => _warehouse.adjustStock(item, -units);
  void rename(WarehouseItemModel item, String name) => _warehouse.renameItem(item, name);
  void archive(WarehouseItemModel item) => _warehouse.archiveItem(item);
}
```

## 7. View (excerpt) — bind and render

```dart
class WarehouseInventoryView extends StackedView<WarehouseInventoryViewModel> {
  @override
  Widget builder(BuildContext context, WarehouseInventoryViewModel vm, _) =>
      Column(children: [
        ArxaKitSearchField(onChanged: vm.onSearchChanged),
        if (vm.lowStock.isNotEmpty) LowStockBanner(items: vm.lowStock),
        Expanded(
          child: ListView.builder(
            itemCount: vm.items.length,
            itemBuilder: (_, i) => WarehouseItemTile(
              item: vm.items[i],
              onReceive: (n) => vm.receive(vm.items[i], n),
              onPick: (n) => vm.pick(vm.items[i], n),
            ),
          ),
        ),
      ]);
}
```

## Wiring — `ArxaKitData.initialize`

```dart
await ArxaKitData.initialize(
  config: ArxaKitDataConfig(
    backend: CairnBackend(
      // Local-only when null → free users, no database. Set later to sync.
      syncUrl: env.cairnSyncUrl,          // e.g. wss://…/sync
      token: session?.jwt,
    ),
    entities: [
      ArxaKitEntityRegistration<WarehouseItemModel>(
        table: warehouseItemSchema,
        fromMap: WarehouseItemModel.fromMap,
        toMap: (m) => m.toMap(),
      ),
    ],
  ),
);
```

## Why this maps cleanly

| kit contract | cairn primitive |
|---|---|
| `watchAll/watchById` streams | `watchMapped` push-invalidation (write → notify, no polling) |
| `patch(original, patched)` column diff | per-field LWW — concurrent edits to different columns both survive |
| `upsertMany` | `writeBatch` (atomic outbox entry) |
| qty adjustments under concurrency | `counterIncrement/counterDecrement` (CRDT counter tier) |
| offline-first for free users | on-device SQLite, sync optional; same code path with or without a server |

Open items (from the cairn audit, still true here): the counter/or-set tables must be
declared on both client and server (`CAIRN_COUNTER_COLUMNS` mismatch fails loudly), and the
Tauri SDK does not yet expose these verbs — Flutter is the flagship; studio-side parity is
covered by the cairn integration plan.

---

# Appendix — the same feature on the PROPOSED ergonomics

Everything above uses cairn's current surface (raw `where:` SQL strings, composition via
rxdart in the facade). Under the redesigned DX (one watch verb + structured predicates,
explicit-get `computed`, differential results with keyed equality) two layers change and
two stay identical:

| Layer | Change |
|---|---|
| View / ViewModel | **none** — still bind facade streams |
| Facade | composition moves from `Rx.combineLatest` to cairn `computed` (still exposed as streams) |
| Repository service | hand-rolled SQL strings → structured query builder |
| Adapter | shrinks: builder passes through, no string assembly |

## Repository service, redesigned

```dart
// BEFORE (current): raw strings, per-SDK dialect drift
_repo.watchAll(const ArxaKitQuery(
  filters: [ArxaKitFilter('is_archived', ArxaKitFilterOp.eq, false)], orderBy: 'name'));

// AFTER (proposed): structured predicate, identical mental model in every SDK
Stream<List<WarehouseItemModel>> watchActive() => db
    .watch<WarehouseItemModel>('warehouse_items')
    .where((i) => i.isArchived.eq(false))
    .orderBy((i) => i.name)
    .stream();   // Dart: Stream · Swift: AsyncSequence · Rust: Stream — native per platform
```

## Facade composition, redesigned

```dart
// BEFORE: rxdart combineLatest + debounce, recomputed wholesale
late final items$ = Rx.combineLatest2(_repo.watchActive(), searchTerm$..., ...);

// AFTER: explicit-get computed — lazy, pure, dependency-tracked by the runtime;
// differential delivery means an untouched result emits nothing (render-storm
// protection comes from the engine, not from dedupe in the facade).
late final items = computed((get) {
  final all  = get(_repo.activeItems);
  final term = get(searchTerm).toLowerCase();
  return term.isEmpty
      ? all
      : all.where((i) => i.name.toLowerCase().contains(term)
                      || i.sku.toLowerCase().contains(term)).toList();
});

late final lowStock   = computed((get) =>
    get(items).where((i) => i.qty <= i.minStock).toList());
late final totalUnits = computed((get) =>
    get(items).fold(0, (sum, i) => sum + i.qty));

// Kit seam unchanged: expose as streams so ArxaKitStreamBuilder / listenTo keep working.
Stream<List<WarehouseItemModel>> get items$ = items.stream();
```

## Differential lists (proposed `.diffs()`)

```dart
// For the big inventory ListView: keyed adds/updates/removes instead of
// whole-list emissions — animated list insertion for a received pallet.
db.watch<WarehouseItemModel>('warehouse_items').diffs()   // {added, updated, removed}
```

Writes are unchanged — `upsert/patch/delete/writeBatch/counterIncrement` already match the
unified-verb contract (ADR-0032 Wave 1 landed in Flutter), so the facade's `mutate()`
wrappers above carry over verbatim. What does NOT carry over yet: the query builder,
`computed`, and `.diffs()` are the redesign — they exist in the DX plan, not in
`cairn_flutter 0.1.0`.
