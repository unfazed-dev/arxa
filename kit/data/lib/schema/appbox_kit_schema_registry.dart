import '../models/appbox_kit_entity_registration.dart';
import 'appbox_kit_table_schema.dart';

/// Holds every entity registration the host declared, addressable by entity
/// type (for typed repositories) and by table name (for fixtures/emitters).
class AppBoxKitSchemaRegistry {
  final List<AppBoxKitEntityRegistration<dynamic>> _registrations = [];
  final Map<String, AppBoxKitTableSchema> _byTable = {};

  void register(AppBoxKitEntityRegistration<dynamic> registration) {
    final table = registration.schema.table;
    if (_byTable.containsKey(table)) {
      throw StateError('table "$table" registered twice');
    }
    _registrations.add(registration);
    _byTable[table] = registration.schema;
  }

  List<AppBoxKitEntityRegistration<dynamic>> get registrations =>
      List.unmodifiable(_registrations);

  Map<String, AppBoxKitTableSchema> get schemasByTable => Map.unmodifiable(_byTable);

  AppBoxKitTableSchema schemaFor(String table) {
    final schema = _byTable[table];
    if (schema == null) {
      throw StateError('no schema registered for table "$table"');
    }
    return schema;
  }
}
