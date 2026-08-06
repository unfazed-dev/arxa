import 'package:appbox_kit_genui_bridge/appbox_kit_genui_bridge.dart';
import 'package:test/test.dart';

const _create =
    '{"version":"v0.9","createSurface":{"surfaceId":"s1","catalogId":"c"}}';
const _components =
    '{"version":"v0.9","updateComponents":{"surfaceId":"s1","components":'
    '[{"id":"root","component":"Text","text":"hi"}]}}';
const _delete = '{"version":"v0.9","deleteSurface":{"surfaceId":"s1"}}';

Future<List<AppBoxKitA2uiStreamEvent>> parse(List<String> chunks) =>
    const AppBoxKitA2uiStreamParser().bind(Stream.fromIterable(chunks)).toList();

void main() {
  group('AppBoxKitA2uiStreamParser', () {
    test('parses a single message in one chunk', () async {
      final events = await parse([_create]);
      expect(events, hasLength(1));
      expect(events.single, isA<AppBoxKitA2uiMessageEvent>());
      expect(
        (events.single as AppBoxKitA2uiMessageEvent).message,
        isA<AppBoxKitCreateSurface>(),
      );
    });

    test('assembles a message split across chunks', () async {
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
      final message = (events.single as AppBoxKitA2uiMessageEvent).message;
      expect((message as AppBoxKitCreateSurface).surfaceId, 's1');
    });

    test('assembles a message split one byte at a time', () async {
      final chunks = [
        for (var i = 0; i < _components.length; i++) _components[i],
      ];
      final events = await parse(chunks);
      expect(events, hasLength(1));
      expect(
        (events.single as AppBoxKitA2uiMessageEvent).message,
        isA<AppBoxKitUpdateComponents>(),
      );
    });

    test('handles braces and escapes inside strings', () async {
      const tricky =
          '{"version":"v0.9","updateDataModel":{"surfaceId":"s1","path":"/t",'
          '"value":"a } { \\"nested\\" brace"}}';
      final events = await parse([tricky]);
      expect(events, hasLength(1));
      final message =
          (events.single as AppBoxKitA2uiMessageEvent).message as AppBoxKitUpdateDataModel;
      expect(message.value, 'a } { "nested" brace');
    });

    test('parses a JSONL stream of messages', () async {
      final events = await parse(['$_create\n$_components\n$_delete\n']);
      expect(events, hasLength(3));
      expect(events[0], isA<AppBoxKitA2uiMessageEvent>());
      expect(events[1], isA<AppBoxKitA2uiMessageEvent>());
      expect(events[2], isA<AppBoxKitA2uiMessageEvent>());
    });

    test('parses a markdown-fenced JSON block', () async {
      final events = await parse(['```json\n$_create\n```']);
      expect(events, hasLength(1));
      expect(events.single, isA<AppBoxKitA2uiMessageEvent>());
    });

    test('emits prose around messages as text events', () async {
      final events = await parse(['Here is the UI:\n$_create\nDone.']);
      final texts = events.whereType<AppBoxKitA2uiTextEvent>().map((e) => e.text);
      final messages = events.whereType<AppBoxKitA2uiMessageEvent>();
      expect(messages, hasLength(1));
      expect(texts.join(), contains('Here is the UI:'));
      expect(texts.join(), contains('Done.'));
    });

    test('strips <a2ui_message> protocol tags from text', () async {
      final events = await parse(['<a2ui_message>hello</a2ui_message>']);
      expect(events, hasLength(1));
      expect((events.single as AppBoxKitA2uiTextEvent).text, 'hello');
    });

    test('invalid JSON inside a fence is an error event, not text', () async {
      final events = await parse(['```json\n{"version":"v0.9", oops\n```']);
      expect(events, hasLength(1));
      expect(events.single, isA<AppBoxKitA2uiErrorEvent>());
      expect((events.single as AppBoxKitA2uiErrorEvent).raw, contains('oops'));
    });

    test('a structurally invalid A2UI envelope is an error event', () async {
      const bad = '{"version":"v0.9","deleteSurface":{"surfaceId":42}}';
      final events = await parse([bad]);
      expect(events, hasLength(1));
      final error = events.single as AppBoxKitA2uiErrorEvent;
      expect(error.error, isA<AppBoxKitA2uiFormatException>());
    });

    test('non-A2UI JSON falls through as text', () async {
      final events = await parse(['{"unrelated":true}']);
      expect(events, hasLength(1));
      expect(events.single, isA<AppBoxKitA2uiTextEvent>());
    });

    test('a truncated final message is an error event at stream end', () async {
      final events = await parse(['$_create\n{"version":"v0.9","deleteSur']);
      expect(events, hasLength(2));
      expect(events[0], isA<AppBoxKitA2uiMessageEvent>());
      expect(events[1], isA<AppBoxKitA2uiErrorEvent>());
      expect(
        (events[1] as AppBoxKitA2uiErrorEvent).error.toString(),
        contains('incomplete'),
      );
    });

    test('pure prose produces only text events', () async {
      final events = await parse(['Sorry, I cannot help with that.']);
      expect(events, hasLength(1));
      expect(events.single, isA<AppBoxKitA2uiTextEvent>());
    });

    test('legacy verb aliases parse through the stream', () async {
      const legacy =
          '{"version":"v0.9","surfaceUpdate":{"surfaceId":"s1","components":'
          '[{"id":"root","component":"Text","text":"hi"}]}}';
      final events = await parse([legacy]);
      expect(events.single, isA<AppBoxKitA2uiMessageEvent>());
      expect(
        (events.single as AppBoxKitA2uiMessageEvent).message,
        isA<AppBoxKitUpdateComponents>(),
      );
    });

    test('a JSON array of messages in a fence emits each message', () async {
      final events = await parse(['```json\n[$_create,$_delete]\n```']);
      expect(events, hasLength(2));
      expect(events.every((e) => e is AppBoxKitA2uiMessageEvent), isTrue);
    });
  });
}
