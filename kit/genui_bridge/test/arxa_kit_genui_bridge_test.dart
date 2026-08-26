import 'package:arxa_kit_genui_bridge/arxa_kit_genui_bridge.dart';
import 'package:arxa_kit_genui_bridge/arxa_kit_testing.dart';
import 'package:test/test.dart';

const _catalogId = 'test.com:catalog';

final _catalog = <String, ArxaKitJsonSchema>{
  'Text': {
    'type': 'object',
    'properties': {
      'id': {'type': 'string'},
      'component': {'const': 'Text'},
      'text': {'type': 'string'},
    },
    'required': ['id', 'component', 'text'],
  },
};

const _create =
    '{"version":"v0.9","createSurface":{"surfaceId":"s1","catalogId":"$_catalogId"}}';
const _goodComponents =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1","components":'
    '[{"id":"root","component":"Text","text":"hi"}]}}';
const _badComponents =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1","components":'
    '[{"id":"root","component":"Text"}]}}'; // missing required "text"

ArxaKitGenuiBridge bridge(FakeArxaKitChatStream chat) =>
    ArxaKitGenuiBridge(chat: chat, catalog: _catalog, catalogId: _catalogId);

void main() {
  group('ArxaKitGenuiBridge.generate', () {
    test('kit.genui-bridge.bridge — happy path: valid output passes in one attempt', () async {
      final chat = FakeArxaKitChatStream()..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate([
        const ArxaKitChatMessage.user('show a greeting'),
      ]);
      expect(turn.attempts, 1);
      expect(turn.messages, hasLength(2));
      expect(turn.messages[0], isA<ArxaKitCreateSurface>());
      expect(turn.messages[1], isA<ArxaKitUpdateComponents>());
      expect(chat.calls, hasLength(1));
    });

    test('kit.genui-bridge.bridge — toJsonl is the canonical forwardable wire form', () async {
      final chat = FakeArxaKitChatStream()..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate(const []);
      expect(
        turn.toJsonl().split('\n'),
        [
          startsWith('{"version":"v0.9","createSurface"'),
          startsWith('{"version":"v0.9","updateComponents"'),
        ],
      );
    });

    test('kit.genui-bridge.bridge — prepends the catalog-bearing system prompt', () async {
      final chat = FakeArxaKitChatStream()..scriptText(_create);
      await bridge(chat).generate(const [ArxaKitChatMessage.user('hi')]);
      final first = chat.calls.single.first;
      expect(first.role, ArxaKitChatRole.system);
      expect(first.content, contains(_catalogId));
      expect(first.content, contains('"Text"'));
      expect(first.content, contains('v0.9'));
    });

    test('kit.genui-bridge.bridge — invalid then repaired: re-asks with the validation error', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('$_create\n$_badComponents')
        ..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(turn.messages, hasLength(2));
      // The repair turn carries the previous failure back to the provider.
      expect(chat.calls, hasLength(2));
      expect(chat.calls[1].length, greaterThan(chat.calls[0].length));
      final repair = chat.lastMessage;
      expect(repair.role, ArxaKitChatRole.user);
      expect(repair.content, contains('A2UI validation error'));
      expect(repair.content, contains('"text"'));
    });

    test('kit.genui-bridge.bridge — only valid messages ever leave the bridge', () async {
      // Attempt 1 mixes one valid and one invalid message; the whole batch
      // must be discarded, not partially emitted.
      final chat = FakeArxaKitChatStream()
        ..scriptText('$_create\n$_badComponents')
        ..scriptText(_goodComponents);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(turn.messages, hasLength(1));
      expect(turn.messages.single, isA<ArxaKitUpdateComponents>());
    });

    test('kit.genui-bridge.bridge — permanently invalid output throws a typed ArxaKitGenuiBridgeFailure',
        () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText(_badComponents)
        ..scriptText(_badComponents)
        ..scriptText(_badComponents);
      await expectLater(
        bridge(chat).generate(const []),
        throwsA(
          isA<ArxaKitGenuiBridgeFailure>()
              .having((f) => f.attempts, 'attempts', 3)
              .having((f) => f.errors.length, 'errors', 3)
              .having((f) => f.lastRawOutput, 'lastRawOutput',
                  contains('updateComponents')),
        ),
      );
      expect(chat.calls, hasLength(3)); // 1 + maxRepairs(2)
    });

    test('kit.genui-bridge.bridge — malformed JSON triggers the repair loop too', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('```json\n{"version":"v0.9", oops\n```')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('A2UI validation error'));
    });

    test('kit.genui-bridge.bridge — a truncated stream is repaired, not silently accepted', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('{"version":"v0.9","deleteSur')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
    });

    test('kit.genui-bridge.bridge — output with no A2UI messages is repaired', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('I cannot render UI, sorry.')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('no A2UI messages'));
    });

    test('kit.genui-bridge.bridge — a hallucinated catalogId is rejected and repaired', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('{"version":"v0.9","createSurface":{"surfaceId":"s1",'
            '"catalogId":"evil.com:other"}}')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('catalogId'));
    });

    test('kit.genui-bridge.bridge — component types outside the catalog are rejected', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Chart","data":[]}]}}')
        ..scriptText(_goodComponents);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('"Chart"'));
    });

    test('kit.genui-bridge.bridge — an empty catalog disables per-component validation', () async {
      final chat = FakeArxaKitChatStream()
        ..scriptText('{"version":"v0.9","createSurface":{"surfaceId":"s1",'
            '"catalogId":"$arxaKitA2uiBasicCatalogId"}}\n'
            '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Chart","anything":1}]}}');
      final turn =
          await ArxaKitGenuiBridge(chat: chat).generate(const []); // default catalog
      expect(turn.attempts, 1);
      expect(turn.messages, hasLength(2));
    });

    test('kit.genui-bridge.bridge — prose alongside valid messages passes through as texts', () async {
      final chat = FakeArxaKitChatStream()..scriptText('Setting that up.\n$_create');
      final turn = await bridge(chat).generate(const []);
      expect(turn.texts.join(), contains('Setting that up.'));
      expect(turn.messages, hasLength(1));
    });
  });
}
