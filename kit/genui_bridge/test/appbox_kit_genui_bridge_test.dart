import 'package:appbox_kit_genui_bridge/appbox_kit_genui_bridge.dart';
import 'package:appbox_kit_genui_bridge/appbox_kit_testing.dart';
import 'package:test/test.dart';

const _catalogId = 'test.com:catalog';

final _catalog = <String, AppBoxKitJsonSchema>{
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

AppBoxKitGenuiBridge bridge(FakeAppBoxKitChatStream chat) =>
    AppBoxKitGenuiBridge(chat: chat, catalog: _catalog, catalogId: _catalogId);

void main() {
  group('AppBoxKitGenuiBridge.generate', () {
    test('happy path: valid output passes in one attempt', () async {
      final chat = FakeAppBoxKitChatStream()..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate([
        const AppBoxKitChatMessage.user('show a greeting'),
      ]);
      expect(turn.attempts, 1);
      expect(turn.messages, hasLength(2));
      expect(turn.messages[0], isA<AppBoxKitCreateSurface>());
      expect(turn.messages[1], isA<AppBoxKitUpdateComponents>());
      expect(chat.calls, hasLength(1));
    });

    test('toJsonl is the canonical forwardable wire form', () async {
      final chat = FakeAppBoxKitChatStream()..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate(const []);
      expect(
        turn.toJsonl().split('\n'),
        [
          startsWith('{"version":"v0.9","createSurface"'),
          startsWith('{"version":"v0.9","updateComponents"'),
        ],
      );
    });

    test('prepends the catalog-bearing system prompt', () async {
      final chat = FakeAppBoxKitChatStream()..scriptText(_create);
      await bridge(chat).generate(const [AppBoxKitChatMessage.user('hi')]);
      final first = chat.calls.single.first;
      expect(first.role, AppBoxKitChatRole.system);
      expect(first.content, contains(_catalogId));
      expect(first.content, contains('"Text"'));
      expect(first.content, contains('v0.9'));
    });

    test('invalid then repaired: re-asks with the validation error', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('$_create\n$_badComponents')
        ..scriptText('$_create\n$_goodComponents');
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(turn.messages, hasLength(2));
      // The repair turn carries the previous failure back to the provider.
      expect(chat.calls, hasLength(2));
      expect(chat.calls[1].length, greaterThan(chat.calls[0].length));
      final repair = chat.lastMessage;
      expect(repair.role, AppBoxKitChatRole.user);
      expect(repair.content, contains('A2UI validation error'));
      expect(repair.content, contains('"text"'));
    });

    test('only valid messages ever leave the bridge', () async {
      // Attempt 1 mixes one valid and one invalid message; the whole batch
      // must be discarded, not partially emitted.
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('$_create\n$_badComponents')
        ..scriptText(_goodComponents);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(turn.messages, hasLength(1));
      expect(turn.messages.single, isA<AppBoxKitUpdateComponents>());
    });

    test('permanently invalid output throws a typed AppBoxKitGenuiBridgeFailure',
        () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText(_badComponents)
        ..scriptText(_badComponents)
        ..scriptText(_badComponents);
      await expectLater(
        bridge(chat).generate(const []),
        throwsA(
          isA<AppBoxKitGenuiBridgeFailure>()
              .having((f) => f.attempts, 'attempts', 3)
              .having((f) => f.errors.length, 'errors', 3)
              .having((f) => f.lastRawOutput, 'lastRawOutput',
                  contains('updateComponents')),
        ),
      );
      expect(chat.calls, hasLength(3)); // 1 + maxRepairs(2)
    });

    test('malformed JSON triggers the repair loop too', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('```json\n{"version":"v0.9", oops\n```')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('A2UI validation error'));
    });

    test('a truncated stream is repaired, not silently accepted', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('{"version":"v0.9","deleteSur')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
    });

    test('output with no A2UI messages is repaired', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('I cannot render UI, sorry.')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('no A2UI messages'));
    });

    test('a hallucinated catalogId is rejected and repaired', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('{"version":"v0.9","createSurface":{"surfaceId":"s1",'
            '"catalogId":"evil.com:other"}}')
        ..scriptText(_create);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('catalogId'));
    });

    test('component types outside the catalog are rejected', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Chart","data":[]}]}}')
        ..scriptText(_goodComponents);
      final turn = await bridge(chat).generate(const []);
      expect(turn.attempts, 2);
      expect(chat.lastMessage.content, contains('"Chart"'));
    });

    test('an empty catalog disables per-component validation', () async {
      final chat = FakeAppBoxKitChatStream()
        ..scriptText('{"version":"v0.9","createSurface":{"surfaceId":"s1",'
            '"catalogId":"$appBoxKitA2uiBasicCatalogId"}}\n'
            '{"version":"v0.9","updateComponents":{"surfaceId":"s1",'
            '"components":[{"id":"root","component":"Chart","anything":1}]}}');
      final turn =
          await AppBoxKitGenuiBridge(chat: chat).generate(const []); // default catalog
      expect(turn.attempts, 1);
      expect(turn.messages, hasLength(2));
    });

    test('prose alongside valid messages passes through as texts', () async {
      final chat = FakeAppBoxKitChatStream()..scriptText('Setting that up.\n$_create');
      final turn = await bridge(chat).generate(const []);
      expect(turn.texts.join(), contains('Setting that up.'));
      expect(turn.messages, hasLength(1));
    });
  });
}
