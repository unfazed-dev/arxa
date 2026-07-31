/// A JSON Schema as plain decoded JSON. Catalog dataSchemas are runtime
/// inputs (supplied by the app/daemon), never compiled into this package.
typedef JsonSchema = Map<String, Object?>;

/// One schema violation found by [JsonSchemaValidator].
class SchemaError {
  const SchemaError(this.path, this.message);

  /// JSON-path-ish location of the offending value, e.g. `$.components[2].text`.
  final String path;

  /// Human-readable description, suitable for appending to a repair prompt.
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Validates decoded JSON values against caller-supplied [JsonSchema]s.
///
/// kimitail: validates only the subset a component catalog actually needs —
/// `type` (incl. `"integer"` and multi-type lists), `properties`, `required`,
/// `additionalProperties: false`, `items`, `enum`, `const`, `minItems`,
/// `minLength`, `minimum`/`maximum`. Everything else (`$ref`/`$defs`,
/// `allOf`/`oneOf`/`anyOf`/`not`, `pattern`, `format`, …) is ignored, so
/// callers must flatten refs and unions before handing schemas over.
/// Upgrade path: depend on a real json_schema package the day a catalog
/// needs union types or remote refs.
class JsonSchemaValidator {
  const JsonSchemaValidator();

  /// Returns every violation of [value] against [schema]; empty means valid.
  List<SchemaError> validate(Object? value, JsonSchema schema,
          [String path = r'$']) =>
      _validate(value, schema, path);

  List<SchemaError> _validate(Object? value, JsonSchema schema, String path) {
    final errors = <SchemaError>[];

    final const_ = schema['const'];
    if (schema.containsKey('const') && value != const_) {
      errors.add(SchemaError(path, 'must be $const_'));
      return errors; // A failed const makes deeper checks noise.
    }

    final enum_ = schema['enum'];
    if (enum_ is List && !enum_.any((e) => _deepEquals(e, value))) {
      errors.add(SchemaError(path, 'must be one of $enum_'));
      return errors;
    }

    final type = schema['type'];
    if (type != null && !_matchesType(value, type)) {
      errors.add(
          SchemaError(path, 'must be of type $type, got ${_typeName(value)}'));
      return errors; // Type mismatch makes property/item checks noise.
    }

    if (value is Map<String, dynamic>) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required) {
          if (!value.containsKey(key)) {
            errors.add(SchemaError(path, 'missing required property "$key"'));
          }
        }
      }
      final properties = schema['properties'];
      if (properties is Map<String, dynamic>) {
        for (final entry in properties.entries) {
          if (value.containsKey(entry.key) && entry.value is JsonSchema) {
            errors.addAll(_validate(value[entry.key],
                entry.value! as JsonSchema, '$path.${entry.key}'));
          }
        }
      }
      if (schema['additionalProperties'] == false && properties is Map) {
        for (final key in value.keys) {
          if (!properties.containsKey(key)) {
            errors.add(SchemaError(path, 'unexpected property "$key"'));
          }
        }
      }
    }

    if (value is List) {
      final minItems = schema['minItems'];
      if (minItems is int && value.length < minItems) {
        errors.add(SchemaError(
            path, 'must have at least $minItems item(s), got ${value.length}'));
      }
      final items = schema['items'];
      if (items is JsonSchema) {
        for (var i = 0; i < value.length; i++) {
          errors.addAll(_validate(value[i], items, '$path[$i]'));
        }
      }
    }

    if (value is String) {
      final minLength = schema['minLength'];
      if (minLength is int && value.length < minLength) {
        errors
            .add(SchemaError(path, 'must be at least $minLength character(s)'));
      }
    }

    if (value is num) {
      final minimum = schema['minimum'];
      if (minimum is num && value < minimum) {
        errors.add(SchemaError(path, 'must be >= $minimum'));
      }
      final maximum = schema['maximum'];
      if (maximum is num && value > maximum) {
        errors.add(SchemaError(path, 'must be <= $maximum'));
      }
    }

    return errors;
  }

  static bool _matchesType(Object? value, Object? type) {
    if (type is List) return type.any((t) => _matchesType(value, t));
    return switch (type) {
      'object' => value is Map<String, dynamic>,
      'array' => value is List,
      'string' => value is String,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num,
      'null' => value == null,
      _ => true, // Unknown type keyword: accept (subset validator).
    };
  }

  static String _typeName(Object? value) => switch (value) {
        null => 'null',
        bool() => 'boolean',
        int() => 'integer',
        num() => 'number',
        String() => 'string',
        List() => 'array',
        Map() => 'object',
        _ => 'unknown',
      };

  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          [for (var i = 0; i < a.length; i++) i]
              .every((i) => _deepEquals(a[i], b[i]));
    }
    return a == b;
  }
}
