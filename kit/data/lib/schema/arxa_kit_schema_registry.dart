import '../models/arxa_kit_entity_registration.dart';
import 'arxa_kit_table_schema.dart';

/// Holds every entity registration the host declared, addressable by entity
/// type (for typed repositories) and by table name (for fixtures/emitters).
class ArxaKitSchemaRegistry {
  final List<ArxaKitEntityRegistration<dynamic>> _registrations = [];
  final Map<String, ArxaKitTableSchema> _byTable = {};

  void register(ArxaKitEntityRegistration<dynamic> registration) {
    final table = registration.schema.table;
    if (_byTable.containsKey(table)) {
      throw StateError('table "$table" registered twice');
    }
    _registrations.add(registration);
    _byTable[table] = registration.schema;
  }

  List<ArxaKitEntityRegistration<dynamic>> get registrations =>
      List.unmodifiable(_registrations);

  Map<String, ArxaKitTableSchema> get schemasByTable => Map.unmodifiable(_byTable);

  ArxaKitTableSchema schemaFor(String table) {
    final schema = _byTable[table];
    if (schema == null) {
      throw StateError('no schema registered for table "$table"');
    }
    return schema;
  }
}
