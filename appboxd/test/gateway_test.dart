import 'dart:convert';
import 'dart:io';

import 'package:appboxd/config.dart';
import 'package:appboxd/gateway.dart';
import 'package:appboxd/server.dart';
import 'package:appboxd/vault.dart';
import 'package:test/test.dart';

/// A mock LLM upstream on loopback: captures the last request and answers
/// with a canned status/body. No real keys or network involved.
class MockUpstream {
  late HttpServer server;
  Map<String, dynamic>? lastBody;
  String? lastPath;
  String? lastAuthorization;
  String? lastApiKey;
  int respondStatus = HttpStatus.ok;
  Map<String, dynamic> respondBody = {};

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      lastPath = request.uri.path;
      lastAuthorization = request.headers.value('authorization');
      lastApiKey = request.headers.value('x-api-key');
      lastBody = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();
      request.response
        ..statusCode = respondStatus
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(respondBody));
      await request.response.close();
    });
  }

  int get port => server.port;

  Future<void> stop() => server.close(force: true);
}

Map<String, dynamic> _openAiResponse(String content,
    {int tokensIn = 11, int tokensOut = 7}) {
  return {
    'id': 'chatcmpl-mock',
    'object': 'chat.completion',
    'model': 'mock',
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': content},
        'finish_reason': 'stop',
      },
    ],
    'usage': {'prompt_tokens': tokensIn, 'completion_tokens': tokensOut},
  };
}

Map<String, dynamic> _anthropicResponse(String text,
    {int tokensIn = 13, int tokensOut = 5}) {
  return {
    'id': 'msg_mock',
    'type': 'message',
    'role': 'assistant',
    'model': 'mock',
    'content': [
      {'type': 'text', 'text': text},
    ],
    'stop_reason': 'end_turn',
    'usage': {'input_tokens': tokensIn, 'output_tokens': tokensOut},
  };
}

void main() {
  late Directory fixture;
  late InMemoryVault vault;
  late Gateway gateway;
  late HttpServer server;
  late HttpClient client;
  late int port;
  late MockUpstream alpha; // openai protocol, no quirks
  late MockUpstream beta; // openai protocol, kimi-like quirks
  late MockUpstream claude; // anthropic protocol
  late String stdToken;
  late String frontierToken;

  setUp(() async {
    fixture = Directory.systemTemp.createTempSync('gateway_test_');
    Directory('${fixture.path}/config').createSync();
    Directory('${fixture.path}/pipeline/state').createSync(recursive: true);

    alpha = MockUpstream();
    beta = MockUpstream();
    claude = MockUpstream();
    await alpha.start();
    await beta.start();
    await claude.start();

    File('${fixture.path}/config/model-fabric.json').writeAsStringSync(
        jsonEncode({
      'schema_version': 1,
      'providers': [
        {
          'name': 'alpha',
          'base_url': 'http://127.0.0.1:${alpha.port}',
          'protocol': 'openai-compat',
          'key_ref': 'key.alpha',
          'param_policy': <String>[],
        },
        {
          'name': 'beta',
          'base_url': 'http://127.0.0.1:${beta.port}',
          'protocol': 'openai-compat',
          'key_ref': 'key.beta',
          'param_policy': [
            'omit_sampling',
            'json_object_only',
            'echo_reasoning_content',
          ],
        },
        {
          'name': 'claude',
          'base_url': 'http://127.0.0.1:${claude.port}',
          // Unversioned native endpoint with a trailing slash — the gateway
          // must normalize it to <base>/v1/messages (pinned below).
          'anthropic_url': 'http://127.0.0.1:${claude.port}/',
          'protocol': 'anthropic-messages',
          'key_ref': 'key.claude',
          'param_policy': <String>[],
        },
      ],
      'tiers': {
        'standard': [
          {'provider': 'alpha', 'model': 'alpha-1'},
          {'provider': 'beta', 'model': 'beta-1'},
        ],
        'frontier': [
          {'provider': 'claude', 'model': 'claude-x'},
        ],
      },
      'stages': {
        'build': {'tier': 'standard'},
        'review': {'tier': 'frontier'},
      },
      'escalation': <String, Object?>{'rule': 'test fixture'},
    }));

    vault = InMemoryVault();
    gateway = Gateway(repoRoot: fixture.path, vault: vault);
    stdToken =
        gateway.minter.mint(consumer: 'pipeline-stage:build', tiers: ['standard']);
    frontierToken =
        gateway.minter.mint(consumer: 'pipeline-stage:review', tiers: ['frontier']);

    final config = AppboxdConfig(
      repoRoot: fixture.path,
      port: 0,
      webRoot: fixture.path,
    );
    server = await startServer(config, gateway: gateway);
    port = server.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await alpha.stop();
    await beta.stop();
    await claude.stop();
    fixture.deleteSync(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> post(String path, Map<String, dynamic> body,
      {String? token, bool useApiKeyHeader = false}) async {
    final request =
        await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    if (token != null) {
      if (useApiKeyHeader) {
        request.headers.set('x-api-key', token);
      } else {
        request.headers.set('authorization', 'Bearer $token');
      }
    }
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (response.statusCode,
        (jsonDecode(text) as Map).cast<String, dynamic>());
  }

  Map<String, dynamic> chatBody({String tier = 'standard'}) => {
        'model': tier,
        'messages': [
          {'role': 'user', 'content': 'hello'},
        ],
      };

  group('token minter', () {
    test('mint/verify round-trips consumer and tier scope', () {
      final minter = TokenMinter();
      final token =
          minter.mint(consumer: 'genui-runtime', tiers: ['fast', 'standard']);
      final scope = minter.verify(token);
      expect(scope, isNotNull);
      expect(scope!.consumer, 'genui-runtime');
      expect(scope.tiers, ['fast', 'standard']);
      expect(minter.verify('abx_bogus'), isNull);
    });

    test('missing or bad token gets 401 on both endpoints', () async {
      for (final path in ['/llm/v1/chat/completions', '/llm/v1/messages']) {
        final (noToken, _) = await post(path, chatBody());
        expect(noToken, HttpStatus.unauthorized, reason: '$path no token');
        final (badToken, _) = await post(path, chatBody(), token: 'abx_nope');
        expect(badToken, HttpStatus.unauthorized, reason: '$path bad token');
      }
    });

    test('x-api-key header is accepted (Anthropic-style clients)', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('hi');
      final (status, _) = await post('/llm/v1/chat/completions', chatBody(),
          token: stdToken, useApiKeyHeader: true);
      expect(status, HttpStatus.ok);
    });

    test('token scoped for another tier gets 403', () async {
      final (status, body) = await post(
          '/llm/v1/chat/completions', chatBody(tier: 'frontier'),
          token: stdToken);
      expect(status, HttpStatus.forbidden);
      expect(body['error'], contains('frontier'));
    });
  });

  group('provider routing', () {
    test('first candidate with a vault key wins', () async {
      await vault.write('key.beta', 'beta-secret');
      beta.respondBody = _openAiResponse('from beta');
      final (status, body) =
          await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(status, HttpStatus.ok);
      expect(body['choices'][0]['message']['content'], 'from beta');
      expect(alpha.lastBody, isNull, reason: 'alpha has no vault key');
      expect(beta.lastBody!['model'], 'beta-1');
      expect(beta.lastAuthorization, 'Bearer beta-secret');
    });

    test('first candidate is used when it has a key', () async {
      await vault.write('key.alpha', 'alpha-secret');
      await vault.write('key.beta', 'beta-secret');
      alpha.respondBody = _openAiResponse('from alpha');
      final (status, _) =
          await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(status, HttpStatus.ok);
      expect(alpha.lastBody!['model'], 'alpha-1');
      expect(beta.lastBody, isNull);
    });

    test('no keyed provider in tier gets 503', () async {
      final (status, body) =
          await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(status, HttpStatus.serviceUnavailable);
      expect(body['error'], contains('standard'));
    });

    test('upstream error status passes through', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondStatus = 429;
      alpha.respondBody = {'error': 'rate limited'};
      final (status, body) =
          await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(status, 429);
      expect(body['error'], 'rate limited');
    });
  });

  group('param_policy normalization', () {
    test('omit_sampling drops temperature and top_p', () async {
      await vault.write('key.beta', 'beta-secret');
      beta.respondBody = _openAiResponse('ok');
      final body = chatBody()
        ..['temperature'] = 0.7
        ..['top_p'] = 0.9;
      await post('/llm/v1/chat/completions', body, token: stdToken);
      expect(beta.lastBody!.containsKey('temperature'), isFalse);
      expect(beta.lastBody!.containsKey('top_p'), isFalse);
    });

    test('json_object_only maps json_schema response_format down', () async {
      await vault.write('key.beta', 'beta-secret');
      beta.respondBody = _openAiResponse('{}');
      final body = chatBody()
        ..['response_format'] = {
          'type': 'json_schema',
          'json_schema': {'name': 'x', 'schema': {}},
        };
      await post('/llm/v1/chat/completions', body, token: stdToken);
      expect(beta.lastBody!['response_format'], {'type': 'json_object'});
    });

    test('provider without the policy passes sampling params through', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('ok');
      final body = chatBody()..['temperature'] = 0.7;
      await post('/llm/v1/chat/completions', body, token: stdToken);
      expect(alpha.lastBody!['temperature'], 0.7);
    });

    test('echo_reasoning_content strips echoed reasoning outside tool loops',
        () async {
      await vault.write('key.beta', 'beta-secret');
      beta.respondBody = _openAiResponse('ok');
      final body = chatBody()
        ..['messages'] = [
          {
            'role': 'assistant',
            'content': 'a',
            'reasoning_content': 'cot',
          },
          {
            'role': 'assistant',
            'content': 'b',
            'reasoning_content': 'cot',
            'tool_calls': [
              {'id': 't1'},
            ],
          },
          {'role': 'user', 'content': 'go on'},
        ];
      await post('/llm/v1/chat/completions', body, token: stdToken);
      final messages = beta.lastBody!['messages'] as List;
      expect((messages[0] as Map).containsKey('reasoning_content'), isFalse);
      expect((messages[1] as Map)['reasoning_content'], 'cot');
    });
  });

  group('shape translation', () {
    test('OpenAI client → anthropic upstream → OpenAI response', () async {
      await vault.write('key.claude', 'claude-secret');
      claude.respondBody = _anthropicResponse('bonjour');
      final body = chatBody(tier: 'frontier')
        ..['messages'] = [
          {'role': 'system', 'content': 'be terse'},
          {'role': 'user', 'content': 'hello'},
        ]
        ..['max_tokens'] = 100;
      final (status, resp) = await post('/llm/v1/chat/completions', body,
          token: frontierToken);
      expect(status, HttpStatus.ok);
      // Upstream saw the Anthropic Messages shape at the versioned URL.
      expect(claude.lastPath, '/v1/messages');
      expect(claude.lastApiKey, 'claude-secret');
      expect(claude.lastBody!['model'], 'claude-x');
      expect(claude.lastBody!['system'], 'be terse');
      expect(claude.lastBody!['max_tokens'], 100);
      expect(claude.lastBody!['messages'], [
        {'role': 'user', 'content': 'hello'},
      ]);
      // Client got the OpenAI chat.completion shape back.
      expect(resp['object'], 'chat.completion');
      expect(resp['choices'][0]['message']['content'], 'bonjour');
      expect(resp['choices'][0]['finish_reason'], 'stop');
      expect(resp['usage']['prompt_tokens'], 13);
      expect(resp['usage']['completion_tokens'], 5);
    });

    test('Anthropic client → openai upstream → Anthropic response', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('hola');
      final body = {
        'model': 'standard',
        'system': 'be terse',
        'max_tokens': 50,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
          },
        ],
      };
      final (status, resp) =
          await post('/llm/v1/messages', body, token: stdToken);
      expect(status, HttpStatus.ok);
      // Upstream saw the OpenAI chat shape.
      expect(alpha.lastPath, '/chat/completions');
      expect(alpha.lastBody!['messages'], [
        {'role': 'system', 'content': 'be terse'},
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(alpha.lastBody!['max_tokens'], 50);
      // Client got the Anthropic Messages shape back.
      expect(resp['type'], 'message');
      expect(resp['role'], 'assistant');
      expect(resp['content'], [
        {'type': 'text', 'text': 'hola'},
      ]);
      expect(resp['stop_reason'], 'end_turn');
      expect(resp['usage'], {'input_tokens': 11, 'output_tokens': 7});
    });

    test('Anthropic client → anthropic upstream passes through', () async {
      await vault.write('key.claude', 'claude-secret');
      claude.respondBody = _anthropicResponse('direct');
      final (status, resp) = await post(
          '/llm/v1/messages',
          {
            'model': 'frontier',
            'max_tokens': 10,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
          token: frontierToken);
      expect(status, HttpStatus.ok);
      expect(claude.lastBody!['model'], 'claude-x');
      expect(resp['content'][0]['text'], 'direct');
    });
  });

  group('upstream URL versioning', () {
    test('anthropic upstream URL is <base>/v1/messages, slash-normalized',
        () async {
      await vault.write('key.claude', 'claude-secret');
      claude.respondBody = _anthropicResponse('url check');
      // The fixture's anthropic_url carries a trailing slash; the final
      // request path must be exactly /v1/messages, no double slash.
      final (status, _) = await post(
          '/llm/v1/messages',
          {
            'model': 'frontier',
            'max_tokens': 10,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          },
          token: frontierToken);
      expect(status, HttpStatus.ok);
      expect(claude.lastPath, '/v1/messages');
      expect(claude.lastPath, isNot(contains('//')));
    });

    test('openai upstream keeps <base>/chat/completions', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('ok');
      await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(alpha.lastPath, '/chat/completions');
    });
  });

  group('catalog degradation', () {
    test('missing catalog → 503 on /llm, daemon keeps serving', () async {
      File('${fixture.path}/config/model-fabric.json').deleteSync();
      final (status, body) = await post('/llm/v1/chat/completions', chatBody(),
          token: stdToken);
      expect(status, HttpStatus.serviceUnavailable);
      expect(body['error'], contains('catalog'));
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/health'));
      expect((await request.close()).statusCode, HttpStatus.ok);
    });

    test('unparseable catalog → 503 on /llm', () async {
      File('${fixture.path}/config/model-fabric.json')
          .writeAsStringSync('{not json');
      final (status, _) = await post('/llm/v1/chat/completions', chatBody(),
          token: stdToken);
      expect(status, HttpStatus.serviceUnavailable);
    });

    test('wrong schema_version → 503 on /llm', () async {
      File('${fixture.path}/config/model-fabric.json')
          .writeAsStringSync(jsonEncode({'schema_version': 99}));
      final (status, _) = await post('/llm/v1/chat/completions', chatBody(),
          token: stdToken);
      expect(status, HttpStatus.serviceUnavailable);
    });
  });

  group('usage attribution', () {
    test('each request appends a usage.jsonl line', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('ok', tokensIn: 21, tokensOut: 9);
      await post('/llm/v1/chat/completions', chatBody(), token: stdToken);

      final file = File('${fixture.path}/pipeline/state/usage.jsonl');
      final lines = file.readAsLinesSync();
      expect(lines, hasLength(1));
      final record = (jsonDecode(lines.single) as Map).cast<String, dynamic>();
      expect(record['consumer_token_id'], isNotEmpty);
      expect(record['consumer'], 'pipeline-stage:build');
      expect(record['tier'], 'standard');
      expect(record['provider'], 'alpha');
      expect(record['model'], 'alpha-1');
      expect(record['tokens_in'], 21);
      expect(record['tokens_out'], 9);
      expect(DateTime.tryParse(record['ts'] as String), isNotNull);
    });

    test('each request appends an llm_request memory event', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondBody = _openAiResponse('ok', tokensIn: 21, tokensOut: 9);
      final (status, _) =
          await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(status, HttpStatus.ok);

      final file = File(
          '${fixture.path}/pipeline/state/memory/events.jsonl');
      final lines = file.readAsLinesSync();
      expect(lines, hasLength(1));
      final event = (jsonDecode(lines.single) as Map).cast<String, dynamic>();
      expect(DateTime.tryParse(event['ts'] as String), isNotNull);
      expect(event['kind'], 'llm_request');
      expect(event['actor'], 'gateway');
      final payload = (event['payload'] as Map).cast<String, dynamic>();
      expect(payload['consumer'], 'pipeline-stage:build');
      expect(payload['tier'], 'standard');
      expect(payload['provider'], 'alpha');
      expect(payload['model'], 'alpha-1');
      expect(payload['tokens_in'], 21);
      expect(payload['tokens_out'], 9);
      expect(payload['ok'], isTrue);
    });

    test('failed upstream calls record nothing', () async {
      await vault.write('key.alpha', 'alpha-secret');
      alpha.respondStatus = 500;
      alpha.respondBody = {'error': 'boom'};
      await post('/llm/v1/chat/completions', chatBody(), token: stdToken);
      expect(File('${fixture.path}/pipeline/state/usage.jsonl').existsSync(),
          isFalse);
      expect(
          File('${fixture.path}/pipeline/state/memory/events.jsonl')
              .existsSync(),
          isFalse);
    });
  });

  test('existing /api endpoints are untouched by the gateway', () async {
    final request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/health'));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
  });
}
