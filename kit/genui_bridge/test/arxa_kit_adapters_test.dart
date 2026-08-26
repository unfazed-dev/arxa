import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_genui_bridge/arxa_kit_genui_bridge.dart';
import 'package:test/test.dart';

/// Records the request and replays a scripted raw response — no network.
class FakeArxaKitTransport {
  Uri? uri;
  Map<String, String>? headers;
  Map<String, Object?>? body;

  List<String> responseChunks = const [];
  Object? responseError;

  Stream<String> call(
    Uri uri,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    final error = responseError;
    if (error != null) return Stream.error(error);
    return Stream.fromIterable(responseChunks);
  }

  Map<String, dynamic> get decodedBody =>
      jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
}

void main() {
  group('ArxaKitOpenAIChatStream', () {
    test('kit.genui-bridge.openai-adapter — request shape: URL, auth header, body', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const ['data: [DONE]\n\n'];
      final chat = ArxaKitOpenAIChatStream(
        model: 'gpt-4o-mini',
        apiKey: 'sk-test',
        transport: transport.call,
      );
      await chat.complete(const [
        ArxaKitChatMessage.system('be brief'),
        ArxaKitChatMessage.user('hi'),
      ]).drain();

      expect(transport.uri.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(transport.headers!['authorization'], 'Bearer sk-test');
      expect(transport.decodedBody['model'], 'gpt-4o-mini');
      expect(transport.decodedBody['stream'], isTrue);
      expect(transport.decodedBody['messages'], [
        {'role': 'system', 'content': 'be brief'},
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(transport.decodedBody.containsKey('response_format'), isFalse);
    });

    test('kit.genui-bridge.openai-adapter — maps the schema hint to response_format', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const ['data: [DONE]\n\n'];
      final chat = ArxaKitOpenAIChatStream(
        model: 'gpt-4o-mini',
        apiKey: 'k',
        transport: transport.call,
      );
      await chat.complete(
        const [ArxaKitChatMessage.user('hi')],
        schema: const {
          'type': 'object',
          'properties': {
            'version': {'const': 'v0.9'}
          },
        },
      ).drain();

      final format = transport.decodedBody['response_format'];
      expect(format, {
        'type': 'json_schema',
        'json_schema': {
          'name': 'a2ui_message',
          'schema': {
            'type': 'object',
            'properties': {
              'version': {'const': 'v0.9'},
            },
          },
        },
      });
    });

    test('kit.genui-bridge.openai-adapter — jsonObjectOnly policy: json_object on the wire, schema in a system '
        'message (the documented Kimi idiom)', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const ['data: [DONE]\n\n'];
      final chat = ArxaKitOpenAIChatStream(
        model: 'kimi-k2',
        apiKey: 'k',
        baseUrl: Uri.parse('https://api.moonshot.ai'),
        transport: transport.call,
        paramPolicy: ArxaKitOpenAIParamPolicy.jsonObjectOnly,
      );
      const schema = {
        'type': 'object',
        'properties': {
          'version': {'const': 'v0.9'}
        },
      };
      await chat.complete(const [ArxaKitChatMessage.user('hi')],
          schema: schema).drain();

      expect(transport.decodedBody['response_format'],
          {'type': 'json_object'});
      final messages = transport.decodedBody['messages'] as List<dynamic>;
      expect(messages.last, {
        'role': 'system',
        'content': 'Respond with a single JSON object matching this JSON '
            'schema: ${jsonEncode(schema)}',
      });
    });

    test('kit.genui-bridge.openai-adapter — configurable baseUrl covers Ollama/llama.cpp; auth optional',
        () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const ['data: [DONE]\n\n'];
      final chat = ArxaKitOpenAIChatStream(
        model: 'qwen3:8b',
        baseUrl: Uri.parse('http://localhost:11434'),
        transport: transport.call,
      );
      await chat.complete(const [ArxaKitChatMessage.user('hi')]).drain();

      expect(transport.uri.toString(),
          'http://localhost:11434/v1/chat/completions');
      expect(transport.headers!.containsKey('authorization'), isFalse);
    });

    test('kit.genui-bridge.openai-adapter — extracts streamed deltas across raw chunk boundaries', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const [
          'data: {"choices":[{"delta":{"content":"{\\"version\\":"}}]}',
          '\n\ndata: {"choices":[{"delta":{"content":"\\"v0.9\\""}}]}\n\nda',
          'ta: {"choices":[{"delta":{}}]}\n\ndata: [DONE]\n\n',
        ];
      final chat = ArxaKitOpenAIChatStream(
        model: 'm',
        apiKey: 'k',
        transport: transport.call,
      );
      final text = await chat
          .complete(const [ArxaKitChatMessage.user('hi')]).fold<StringBuffer>(
              StringBuffer(), (b, s) => b..write(s));
      expect(text.toString(), '{"version":"v0.9"');
    });

    test('kit.genui-bridge.openai-adapter — a provider error payload throws ArxaKitChatStreamException', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const [
          'data: {"error":{"message":"rate limited","type":"tokens"}}\n\n',
        ];
      final chat = ArxaKitOpenAIChatStream(
        model: 'm',
        apiKey: 'k',
        transport: transport.call,
      );
      await expectLater(
        chat.complete(const [ArxaKitChatMessage.user('hi')]).drain(),
        throwsA(isA<ArxaKitChatStreamException>()
            .having((e) => e.message, 'message', contains('rate limited'))),
      );
    });

    test('kit.genui-bridge.openai-adapter — a non-200 transport failure propagates', () async {
      final transport = FakeArxaKitTransport()
        ..responseError = const ArxaKitChatStreamException('HTTP 500',
            statusCode: 500, body: 'boom');
      final chat = ArxaKitOpenAIChatStream(
        model: 'm',
        apiKey: 'k',
        transport: transport.call,
      );
      await expectLater(
        chat.complete(const [ArxaKitChatMessage.user('hi')]).drain(),
        throwsA(isA<ArxaKitChatStreamException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('ArxaKitAnthropicChatStream', () {
    test('kit.genui-bridge.anthropic-adapter — request shape: URL, headers, system hoisted out of messages',
        () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const [
          'event: message_stop\ndata: {"type":"message_stop"}\n\n',
        ];
      final chat = ArxaKitAnthropicChatStream(
        model: 'claude-sonnet-4-5',
        apiKey: 'sk-ant',
        transport: transport.call,
      );
      await chat.complete(const [
        ArxaKitChatMessage.system('be brief'),
        ArxaKitChatMessage.user('hi'),
        ArxaKitChatMessage.assistant('hello'),
        ArxaKitChatMessage.user('again'),
      ]).drain();

      expect(transport.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(transport.headers!['x-api-key'], 'sk-ant');
      expect(transport.headers!['anthropic-version'], '2023-06-01');
      expect(transport.decodedBody['model'], 'claude-sonnet-4-5');
      expect(transport.decodedBody['stream'], isTrue);
      expect(transport.decodedBody['max_tokens'], 8192);
      expect(transport.decodedBody['system'], 'be brief');
      expect(transport.decodedBody['messages'], [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
        {'role': 'user', 'content': 'again'},
      ]);
    });

    test('kit.genui-bridge.anthropic-adapter — extracts text deltas and ignores pings and other events', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const [
          'event: message_start\n',
          'data: {"type":"message_start","message":{"content":[]}}\n\n',
          'event: ping\ndata: {"type":"ping"}\n\n',
          'event: content_block_delta\n',
          'data: {"type":"content_block_delta","index":0,',
          '"delta":{"type":"text_delta","text":"Hel"}}\n\n',
          'event: content_block_delta\n',
          'data: {"type":"content_block_delta","index":0,'
              '"delta":{"type":"text_delta","text":"lo"}}\n\n',
          'event: message_stop\ndata: {"type":"message_stop"}\n\n',
        ];
      final chat = ArxaKitAnthropicChatStream(
        model: 'm',
        apiKey: 'k',
        transport: transport.call,
      );
      final text = await chat
          .complete(const [ArxaKitChatMessage.user('hi')]).fold<StringBuffer>(
              StringBuffer(), (b, s) => b..write(s));
      expect(text.toString(), 'Hello');
    });

    test('kit.genui-bridge.anthropic-adapter — a provider error event throws ArxaKitChatStreamException', () async {
      final transport = FakeArxaKitTransport()
        ..responseChunks = const [
          'event: error\n',
          'data: {"type":"error","error":{"type":"overloaded_error",'
              '"message":"Overloaded"}}\n\n',
        ];
      final chat = ArxaKitAnthropicChatStream(
        model: 'm',
        apiKey: 'k',
        transport: transport.call,
      );
      await expectLater(
        chat.complete(const [ArxaKitChatMessage.user('hi')]).drain(),
        throwsA(isA<ArxaKitChatStreamException>()
            .having((e) => e.message, 'message', contains('Overloaded'))),
      );
    });
  });

  group('arxaKitSplitSseEvents', () {
    test('kit.genui-bridge.sse-transport — joins multi-line data payloads per the SSE spec', () async {
      final events = await arxaKitSplitSseEvents(
        Stream.fromIterable(const [
          'data: {"a":\ndata: 1}\n\ndata: x\n\n',
        ]),
      ).toList();
      expect(events, ['{"a":\n1}', 'x']);
    });

    test('kit.genui-bridge.sse-transport — handles CRLF line endings and an unterminated final event', () async {
      final events = await arxaKitSplitSseEvents(
        Stream.fromIterable(const ['data: a\r\n\r\ndata: b']),
      ).toList();
      expect(events, ['a', 'b']);
    });
  });

  group('arxaKitHttpPostStream', () {
    test('kit.genui-bridge.sse-transport — decodes UTF-8 incrementally across chunk boundaries', () async {
      // A multi-byte char ('ż' = 0xC5 0xBC) split across two HTTP chunks
      // must not corrupt: guards the utf8.decoder.bind in arxa_kit_sse_transport.dart.
      const payload = 'data: {"choices":[{"delta":{"content":"zażółć"}}]}'
          '\n\ndata: [DONE]\n\n';
      final bytes = utf8.encode(payload);
      final splitAt = bytes.indexOf(0xC5) + 1; // mid-'ż'

      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.add(bytes.sublist(0, splitAt));
        await request.response.flush();
        request.response.add(bytes.sublist(splitAt));
        await request.response.close();
      });

      final chat = ArxaKitOpenAIChatStream(
        model: 'm',
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      );
      final text = await chat
          .complete(const [ArxaKitChatMessage.user('hi')]).fold<StringBuffer>(
              StringBuffer(), (b, s) => b..write(s));
      expect(text.toString(), 'zażółć');
    });
  });
}
