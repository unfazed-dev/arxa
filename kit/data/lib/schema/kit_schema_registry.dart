import '../models/kit_entity_registration.dart';
import 'kit_table_schema.dart';

/// Holds every entity registration the host declared, addressable by entity
/// type (for typed repositories) and by table name (for fixtures/emitters).
class KitSchemaRegistry {
  final List<KitEntityRegistration<dynamic>> _registrations = [];
  final Map<String, KitTableSchema> _byTable = {};

  void register(KitEntityRegistration<dynamic> registration) {
    final table = registration.schema.table;
    if (_byTable.containsKey(table)) {
      throw StateError('table "$table" registered twice');
    }
    _registrations.add(registration);
    _byTable[table] = registration.schema;
  }

  List<KitEntityRegistration<dynamic>> get registrations =>
      List.unmodifiable(_registrations);

  Map<String, KitTableSchema> get schemasByTable => Map.unmodifiable(_byTable);

  KitTableSchema schemaFor(String table) {
    final schema = _byTable[table];
    if (schema == null) {
      throw StateError('no schema registered for table "$table"');
    }
    return schema;
  }
}
