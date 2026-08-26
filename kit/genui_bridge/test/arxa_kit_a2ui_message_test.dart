import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_genui_bridge/arxa_kit_genui_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('ArxaKitA2uiMessage.fromJson', () {
    test('kit.genui-bridge.a2ui-message — parses createSurface with all fields', () {
      final message = ArxaKitA2uiMessage.fromJson({
        'version': 'v0.9',
        'createSurface': {
          'surfaceId': 's1',
          'catalogId': 'example.com:catalog',
          'theme': {'primaryColor': '#00BFFF'},
          'sendDataModel': true,
        },
      });
      expect(message, isA<ArxaKitCreateSurface>());
      final create = message as ArxaKitCreateSurface;
      expect(create.surfaceId, 's1');
      expect(create.catalogId, 'example.com:catalog');
      expect(create.theme, {'primaryColor': '#00BFFF'});
      expect(create.sendDataModel, isTrue);
    });

    test('kit.genui-bridge.a2ui-message — sendDataModel defaults to false', () {
      final message = ArxaKitA2uiMessage.fromJson(const {
        'version': 'v0.9',
        'createSurface': {'surfaceId': 's1', 'catalogId': 'c'},
      });
      expect((message as ArxaKitCreateSurface).sendDataModel, isFalse);
    });

    test('kit.genui-bridge.a2ui-message — parses updateComponents', () {
      final message = ArxaKitA2uiMessage.fromJson(const {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's1',
          'components': [
            {
              'id': 'root',
              'component': 'Column',
              'children': ['t']
            },
            {'id': 't', 'component': 'Text', 'text': 'hi'},
          ],
        },
      });
      final update = message as ArxaKitUpdateComponents;
      expect(update.components, hasLength(2));
      expect(update.components[1]['text'], 'hi');
    });

    test('kit.genui-bridge.a2ui-message — parses updateDataModel with optional fields omitted', () {
      final message = ArxaKitA2uiMessage.fromJson(const {
        'version': 'v0.9',
        'updateDataModel': {'surfaceId': 's1'},
      });
      final update = message as ArxaKitUpdateDataModel;
      expect(update.path, isNull);
      expect(update.value, isNull);
    });

    test('kit.genui-bridge.a2ui-message — parses deleteSurface', () {
      final message = ArxaKitA2uiMessage.fromJson(const {
        'version': 'v0.9',
        'deleteSurface': {'surfaceId': 's1'},
      });
      expect((message as ArxaKitDeleteSurface).surfaceId, 's1');
    });

    group('rename-in-flight tolerance (v0.8 aliases)', () {
      test('kit.genui-bridge.a2ui-message — accepts surfaceUpdate for updateComponents', () {
        final message = ArxaKitA2uiMessage.fromJson(const {
          'version': 'v0.9',
          'surfaceUpdate': {
            'surfaceId': 's1',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'hi'},
            ],
          },
        });
        expect(message, isA<ArxaKitUpdateComponents>());
      });

      test('kit.genui-bridge.a2ui-message — accepts dataModelUpdate for updateDataModel', () {
        final message = ArxaKitA2uiMessage.fromJson(const {
          'version': 'v0.9',
          'dataModelUpdate': {
            'surfaceId': 's1',
            'path': '/user',
            'value': 'Alice',
          },
        });
        final update = message as ArxaKitUpdateDataModel;
        expect(update.path, '/user');
        expect(update.value, 'Alice');
      });

      test('kit.genui-bridge.a2ui-message — writes canonical names after reading an alias', () {
        final message = ArxaKitA2uiMessage.fromJson(const {
          'version': 'v0.9',
          'surfaceUpdate': {
            'surfaceId': 's1',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'hi'},
            ],
          },
        });
        final json = message.toJson();
        expect(json.containsKey('updateComponents'), isTrue);
        expect(json.containsKey('surfaceUpdate'), isFalse);
      });
    });

    group('rejections (repairable format errors)', () {
      void expectFormatError(Map<String, dynamic> json) {
        expect(
          () => ArxaKitA2uiMessage.fromJson(json),
          throwsA(isA<ArxaKitA2uiFormatException>()),
        );
      }

      test('kit.genui-bridge.a2ui-message — missing version', () {
        expectFormatError(const {
          'deleteSurface': {'surfaceId': 's1'},
        });
      });

      test('kit.genui-bridge.a2ui-message — wrong version', () {
        expectFormatError(const {
          'version': 'v0.8',
          'deleteSurface': {'surfaceId': 's1'},
        });
      });

      test('kit.genui-bridge.a2ui-message — two verb keys', () {
        expectFormatError(const {
          'version': 'v0.9',
          'createSurface': {'surfaceId': 's1', 'catalogId': 'c'},
          'deleteSurface': {'surfaceId': 's1'},
        });
      });

      test('kit.genui-bridge.a2ui-message — canonical verb and its alias both present', () {
        expectFormatError(const {
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 's1', 'components': []},
          'surfaceUpdate': {'surfaceId': 's1', 'components': []},
        });
      });

      test('kit.genui-bridge.a2ui-message — no verb key', () {
        expectFormatError(const {'version': 'v0.9', 'foo': 1});
      });

      test('kit.genui-bridge.a2ui-message — missing surfaceId', () {
        expectFormatError(const {
          'version': 'v0.9',
          'deleteSurface': <String, dynamic>{},
        });
      });

      test('kit.genui-bridge.a2ui-message — missing catalogId', () {
        expectFormatError(const {
          'version': 'v0.9',
          'createSurface': {'surfaceId': 's1'},
        });
      });

      test('kit.genui-bridge.a2ui-message — components not a list', () {
        expectFormatError(const {
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 's1', 'components': 'nope'},
        });
      });

      test('kit.genui-bridge.a2ui-message — component entry not an object', () {
        expectFormatError(const {
          'version': 'v0.9',
          'updateComponents': {
            'surfaceId': 's1',
            'components': ['nope'],
          },
        });
      });
    });
  });

  group('toJson round-trips', () {
    final cases = <Map<String, dynamic>>[
      {
        'version': 'v0.9',
        'createSurface': {
          'surfaceId': 's1',
          'catalogId': 'c',
          'theme': {'primaryColor': '#00BFFF'},
          'sendDataModel': true,
        },
      },
      {
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': 's1',
          'components': [
            {'id': 'root', 'component': 'Text', 'text': 'hi'},
          ],
        },
      },
      {
        'version': 'v0.9',
        'updateDataModel': {
          'surfaceId': 's1',
          'path': '/user/name',
          'value': 'Jane',
        },
      },
      {
        'version': 'v0.9',
        'deleteSurface': {'surfaceId': 's1'},
      },
    ];

    for (final envelope in cases) {
      test('kit.genui-bridge.a2ui-message — ${envelope.keys.last} survives parse → serialize', () {
        final message = ArxaKitA2uiMessage.fromJson(envelope);
        expect(message.toJson(), envelope);
      });
    }

    test('kit.genui-bridge.a2ui-message — toJsonLine produces the JSONL wire form', () {
      const message = ArxaKitDeleteSurface(surfaceId: 's1');
      expect(
        message.toJsonLine(),
        '{"version":"v0.9","deleteSurface":{"surfaceId":"s1"}}',
      );
    });
  });

  group('shipped reference schema (assets/a2ui)', () {
    // Anchors the package to the canonical spec artifact — see
    // assets/a2ui/PROVENANCE.md for source URLs and fetch date.
    test('kit.genui-bridge.a2ui-message — server_to_client.json is the v0.9 four-verb schema', () {
      final file = File('assets/a2ui/server_to_client.json');
      expect(file.existsSync(), isTrue,
          reason: 'run tests from the package root');
      final schema =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(schema[r'$id'],
          'https://a2ui.org/specification/v0_9/server_to_client.json');
      final defs = schema[r'$defs'] as Map<String, dynamic>;
      expect(
        defs.keys,
        containsAll([
          'CreateSurfaceMessage',
          'UpdateComponentsMessage',
          'UpdateDataModelMessage',
          'DeleteSurfaceMessage',
        ]),
      );
      final create = defs['CreateSurfaceMessage'] as Map<String, dynamic>;
      expect(create['required'], containsAll(['createSurface', 'version']));
    });
  });
}
