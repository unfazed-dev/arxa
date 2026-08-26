import 'package:arxa_kit_genui_bridge/arxa_kit_genui_bridge.dart';
import 'package:test/test.dart';

const _create =
    '{"version":"v0.9","createSurface":{"surfaceId":"s1","catalogId":"c"}}';
const _components =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1","components":'
    '[{"id":"root","component":"Text","text":"hi"}]}}';
const _delete = '{"version":"v0.9","deleteSurface":{"surfaceId":"s1"}}';

Future<List<ArxaKitA2uiStreamEvent>> parse(List<String> chunks) =>
    const ArxaKitA2uiStreamParser().bind(Stream.fromIterable(chunks)).toList();

void main() {
  group('ArxaKitA2uiStreamParser', () {
    test('kit.genui-bridge.stream-parser — parses a single message in one chunk', () async {
      final events = await parse([_create]);
      expect(events, hasLength(1));
      expect(events.single, isA<ArxaKitA2uiMessageEvent>());
      expect(
        (events.single as ArxaKitA2uiMessageEvent).message,
        isA<ArxaKitCreateSurface>(),
      );
    });

    test('kit.genui-bridge.stream-parser — assembles a message split across chunks', () async {
      // Split mid-keyword, mid-string and mid-escape — none may lose data.
      final full = _create;
      final chunks = [
        full.substring(0, 13),
        full.substring(13, 40),
        full.substring(40, 55),
        full.substring(55),
      ];
      final events = await parse(chunks);
      expect(events, hasLength(1));
      final message = (events.single as ArxaKitA2uiMessageEvent).message;
      expect((message as ArxaKitCreateSurface).surfaceId, 's1');
    });

    test('kit.genui-bridge.stream-parser — assembles a message split one byte at a time', () async {
      final chunks = [
        for (var i = 0; i < _components.length; i++) _components[i],
      ];
      final events = await parse(chunks);
      expect(events, hasLength(1));
      expect(
        (events.single as ArxaKitA2uiMessageEvent).message,
        isA<ArxaKitUpdateComponents>(),
      );
    });

    test('kit.genui-bridge.stream-parser — handles braces and escapes inside strings', () async {
      const tricky =
          '{"version":"v0.9","updateDataModel":{"surfaceId":"s1","path":"/t",'
          '"value":"a } { \\"nested\\" brace"}}';
      final events = await parse([tricky]);
      expect(events, hasLength(1));
      final message =
          (events.single as ArxaKitA2uiMessageEvent).message as ArxaKitUpdateDataModel;
      expect(message.value, 'a } { "nested" brace');
    });

    test('kit.genui-bridge.stream-parser — parses a JSONL stream of messages', () async {
      final events = await parse(['$_create\n$_components\n$_delete\n']);
      expect(events, hasLength(3));
      expect(events[0], isA<ArxaKitA2uiMessageEvent>());
      expect(events[1], isA<ArxaKitA2uiMessageEvent>());
      expect(events[2], isA<ArxaKitA2uiMessageEvent>());
    });

    test('kit.genui-bridge.stream-parser — parses a markdown-fenced JSON block', () async {
      final events = await parse(['```json\n$_create\n```']);
      expect(events, hasLength(1));
      expect(events.single, isA<ArxaKitA2uiMessageEvent>());
    });

    test('kit.genui-bridge.stream-parser — emits prose around messages as text events', () async {
      final events = await parse(['Here is the UI:\n$_create\nDone.']);
      final texts = events.whereType<ArxaKitA2uiTextEvent>().map((e) => e.text);
      final messages = events.whereType<ArxaKitA2uiMessageEvent>();
      expect(messages, hasLength(1));
      expect(texts.join(), contains('Here is the UI:'));
      expect(texts.join(), contains('Done.'));
    });

    test('kit.genui-bridge.stream-parser — strips <a2ui_message> protocol tags from text', () async {
      final events = await parse(['<a2ui_message>hello</a2ui_message>']);
      expect(events, hasLength(1));
      expect((events.single as ArxaKitA2uiTextEvent).text, 'hello');
    });

    test('kit.genui-bridge.stream-parser — invalid JSON inside a fence is an error event, not text', () async {
      final events = await parse(['```json\n{"version":"v0.9", oops\n```']);
      expect(events, hasLength(1));
      expect(events.single, isA<ArxaKitA2uiErrorEvent>());
      expect((events.single as ArxaKitA2uiErrorEvent).raw, contains('oops'));
    });

    test('kit.genui-bridge.stream-parser — a structurally invalid A2UI envelope is an error event', () async {
      const bad = '{"version":"v0.9","deleteSurface":{"surfaceId":42}}';
      final events = await parse([bad]);
      expect(events, hasLength(1));
      final error = events.single as ArxaKitA2uiErrorEvent;
      expect(error.error, isA<ArxaKitA2uiFormatException>());
    });

    test('kit.genui-bridge.stream-parser — non-A2UI JSON falls through as text', () async {
      final events = await parse(['{"unrelated":true}']);
      expect(events, hasLength(1));
      expect(events.single, isA<ArxaKitA2uiTextEvent>());
    });

    test('kit.genui-bridge.stream-parser — a truncated final message is an error event at stream end', () async {
      final events = await parse(['$_create\n{"version":"v0.9","deleteSur']);
      expect(events, hasLength(2));
      expect(events[0], isA<ArxaKitA2uiMessageEvent>());
      expect(events[1], isA<ArxaKitA2uiErrorEvent>());
      expect(
        (events[1] as ArxaKitA2uiErrorEvent).error.toString(),
        contains('incomplete'),
      );
    });

    test('kit.genui-bridge.stream-parser — pure prose produces only text events', () async {
      final events = await parse(['Sorry, I cannot help with that.']);
      expect(events, hasLength(1));
      expect(events.single, isA<ArxaKitA2uiTextEvent>());
    });

    test('kit.genui-bridge.stream-parser — legacy verb aliases parse through the stream', () async {
      const legacy =
          '{"version":"v0.9","surfaceUpdate":{"surfaceId":"s1","components":'
          '[{"id":"root","component":"Text","text":"hi"}]}}';
      final events = await parse([legacy]);
      expect(events.single, isA<ArxaKitA2uiMessageEvent>());
      expect(
        (events.single as ArxaKitA2uiMessageEvent).message,
        isA<ArxaKitUpdateComponents>(),
      );
    });

    test('kit.genui-bridge.stream-parser — a JSON array of messages in a fence emits each message', () async {
      final events = await parse(['```json\n[$_create,$_delete]\n```']);
      expect(events, hasLength(2));
      expect(events.every((e) => e is ArxaKitA2uiMessageEvent), isTrue);
    });
  });
}
