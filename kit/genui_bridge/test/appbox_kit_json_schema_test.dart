import 'package:appbox_kit_genui_bridge/appbox_kit_genui_bridge.dart';
import 'package:test/test.dart';

void main() {
  const validator = AppBoxKitJsonSchemaValidator();

  group('AppBoxKitJsonSchemaValidator (subset)', () {
    test('kit.genui-bridge.json-schema — valid object passes', () {
      final errors = validator.validate(
        {'text': 'hi', 'variant': 'h1'},
        {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
            'variant': {
              'type': 'string',
              'enum': ['h1', 'h2', 'body'],
            },
          },
          'required': ['text'],
        },
      );
      expect(errors, isEmpty);
    });

    test('kit.genui-bridge.json-schema — missing required property is reported', () {
      final errors = validator.validate(
        <String, dynamic>{},
        {
          'type': 'object',
          'required': ['text'],
        },
      );
      expect(errors.single.path, r'$');
      expect(errors.single.message, contains('"text"'));
    });

    test('kit.genui-bridge.json-schema — type mismatch is reported with actual type', () {
      final errors = validator.validate(
        {'weight': 'one'},
        {
          'type': 'object',
          'properties': {
            'weight': {'type': 'integer'},
          },
        },
      );
      expect(errors.single.toString(), contains(r'$.weight'));
      expect(errors.single.message, contains('integer'));
    });

    test('kit.genui-bridge.json-schema — integer does not accept doubles, number accepts both', () {
      expect(
        validator.validate(1.5, {'type': 'integer'}),
        isNotEmpty,
      );
      expect(validator.validate(1, {'type': 'integer'}), isEmpty);
      expect(validator.validate(1.5, {'type': 'number'}), isEmpty);
    });

    test('kit.genui-bridge.json-schema — enum violation is reported', () {
      final errors = validator.validate(
        'giant',
        {
          'type': 'string',
          'enum': ['h1', 'body'],
        },
      );
      expect(errors.single.message, contains('one of'));
    });

    test('kit.genui-bridge.json-schema — const violation is reported', () {
      final errors = validator.validate('Row', {
        'const': 'Text',
      });
      expect(errors.single.message, contains('Text'));
    });

    test('kit.genui-bridge.json-schema — additionalProperties: false rejects unknown keys', () {
      final errors = validator.validate(
        {'id': 'a', 'bogus': 1},
        {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
          },
          'additionalProperties': false,
        },
      );
      expect(errors.single.message, contains('"bogus"'));
    });

    test('kit.genui-bridge.json-schema — array items and minItems are checked recursively', () {
      final errors = validator.validate(
        {
          'children': ['a', 1],
        },
        {
          'type': 'object',
          'properties': {
            'children': {
              'type': 'array',
              'minItems': 3,
              'items': {'type': 'string'},
            },
          },
        },
      );
      expect(errors, hasLength(2));
      expect(errors.map((e) => e.path),
          containsAll([r'$.children', r'$.children[1]']));
    });

    test('kit.genui-bridge.json-schema — multi-type lists accept any listed type', () {
      final schema = {
        'type': ['string', 'null'],
      };
      expect(validator.validate('x', schema), isEmpty);
      expect(validator.validate(null, schema), isEmpty);
      expect(validator.validate(5, schema), isNotEmpty);
    });

    test('kit.genui-bridge.json-schema — unknown keywords are ignored (subset ceiling)', () {
      // pattern/format/$ref are out of the supported subset and must pass.
      final errors = validator.validate('not-an-email', {
        'type': 'string',
        'pattern': r'^[^@]+@[^@]+$',
        'format': 'email',
        r'$ref': '#/nowhere',
      });
      expect(errors, isEmpty);
    });

    test('kit.genui-bridge.json-schema — nested object paths compose', () {
      final errors = validator.validate(
        {
          'action': {
            'event': {'name': 42},
          },
        },
        {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'object',
              'properties': {
                'event': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                  },
                },
              },
            },
          },
        },
      );
      expect(errors.single.path, r'$.action.event.name');
    });
  });
}
