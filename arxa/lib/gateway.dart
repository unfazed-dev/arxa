import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'fabric.dart';
import 'memory.dart';
import 'vault.dart';

/// The loopback LLM gateway (decision E2): OpenAI-compatible and
/// Anthropic-compatible endpoints on 127.0.0.1, scoped per-consumer tokens,
/// provider routing over the model fabric catalog (E4), and per-request usage
/// attribution feeding the routing scorecard.
///
/// Raw provider keys never leave the daemon: consumers hold only scoped
/// tokens minted in-process, and the gateway reads provider keys from the
/// [Vault] by the catalog's `key_ref`.

/// Whether this provider speaks the Anthropic Messages API natively —
/// `openai*` (openai-compat, openai-responses) speaks chat/completions,
/// `anthropic*` (anthropic-messages) speaks /v1/messages.
bool _isAnthropic(FabricProvider provider) =>
    provider.protocol.startsWith('anthropic');

/// A minted per-consumer token's scope.
class ScopedToken {
  const ScopedToken({
    required this.id,
    required this.consumer,
    required this.tiers,
  });

  final String id;

  /// Who holds this token, e.g. `pipeline-stage:design`, `genui-runtime`.
  final String consumer;

  /// Fabric tiers this token may request.
  final List<String> tiers;
}

/// Mints and verifies scoped per-consumer tokens (E2).
///
/// kimitail: tokens are random and in-memory — they die with the daemon and
/// there is no revocation list. Upgrade path when persistence is needed:
/// HMAC-signed tokens (consumer|tiers|expiry) verified statelessly.
class TokenMinter {
  final _tokens = <String, ScopedToken>{};
  final _random = Random.secure();
  var _nextId = 0;

  /// Issues a token for [consumer] allowed to request [tiers].
  String mint({required String consumer, required List<String> tiers}) {
    final id = 'tok-${++_nextId}';
    final token =
        'abx_${List.generate(24, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    _tokens[token] =
        ScopedToken(id: id, consumer: consumer, tiers: List.unmodifiable(tiers));
    return token;
  }

  /// Returns the scope for [token], or null when unknown.
  ScopedToken? verify(String token) => _tokens[token];
}

/// The selected upstream route for one request.
class _Route {
  const _Route(this.provider, this.model, this.apiKey);
  final FabricProvider provider;
  final String model;
  final String apiKey;
}

/// Serves `/llm/v1/chat/completions` (OpenAI shape) and `/llm/v1/messages`
/// (Anthropic shape), translating to/from the selected upstream's protocol.
class Gateway {
  Gateway({
    required this.repoRoot,
    required this.vault,
    TokenMinter? minter,
    HttpClient? client,
  })  : minter = minter ?? TokenMinter(),
        _client = client ?? HttpClient();

  final String repoRoot;
  final Vault vault;

  /// The daemon mints consumer tokens here at spawn (E3 stage runs,
  /// genui runtime) — minting is an in-process API, never an HTTP endpoint.
  final TokenMinter minter;

  final HttpClient _client;

  ModelFabric? _catalog;
  var _catalogLoaded = false;

  ModelFabric? _catalogOrNull() {
    // kimitail: catalog is loaded once per daemon run — restart to pick up
    // catalog edits. Hot reload if it ever annoys anyone.
    if (!_catalogLoaded) {
      _catalog = _loadCatalog();
      _catalogLoaded = true;
    }
    return _catalog;
  }

  /// The canonical loader is [ModelFabric] (lib/fabric.dart owns the
  /// schema). A missing or unparseable catalog degrades to null → /llm
  /// answers 503 while the rest of the daemon keeps serving.
  ModelFabric? _loadCatalog() {
    final file = File(p.join(repoRoot, 'config', 'model-fabric.json'));
    if (!file.existsSync()) return null;
    try {
      return ModelFabric.parse(file.readAsStringSync());
    } on FormatException {
      return null;
    }
  }

  /// Handles one `/llm/...` request; the server routes those here.
  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    final openAiShape = path == '/llm/v1/chat/completions';
    final anthropicShape = path == '/llm/v1/messages';
    if (!openAiShape && !anthropicShape) {
      return _json(request, {'error': 'not found'}, status: HttpStatus.notFound);
    }
    if (request.method != 'POST') {
      return _json(request, {'error': 'POST required'},
          status: HttpStatus.methodNotAllowed);
    }

    final scope = _scopeOf(request);
    if (scope == null) {
      return _json(request, {'error': 'missing or invalid token'},
          status: HttpStatus.unauthorized);
    }

    final Map<String, dynamic> body;
    try {
      body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();
    } on FormatException {
      return _json(request, {'error': 'invalid JSON body'},
          status: HttpStatus.badRequest);
    }

    // The request's `model` field names a fabric tier; the gateway owns
    // which concrete model serves it (E4 tier semantics).
    final tier = body['model'];
    if (tier is! String || tier.isEmpty) {
      return _json(request, {'error': 'model must name a fabric tier'},
          status: HttpStatus.badRequest);
    }
    if (!scope.tiers.contains(tier)) {
      return _json(request, {'error': 'token not scoped for tier "$tier"'},
          status: HttpStatus.forbidden);
    }
    // SSE passthrough, routed after route selection — see _streamUpstream.
    final streaming = body['stream'] == true;

    final catalog = _catalogOrNull();
    if (catalog == null) {
      return _json(request,
          {'error': 'model fabric catalog missing or unparseable'},
          status: HttpStatus.serviceUnavailable);
    }
    final route = await _selectRoute(catalog, tier, scope);
    if (route == null) {
      return _json(request,
          {'error': 'no provider in tier "$tier" has a vault key'},
          status: HttpStatus.serviceUnavailable);
    }

    if (streaming) {
      return _streamUpstream(request, scope, tier, route, body,
          openAiShape: openAiShape);
    }

    try {
      final (status, upstream) = await _callUpstream(
          route, body, openAiShape: openAiShape);
      if (status != HttpStatus.ok) {
        return _json(request, upstream, status: status);
      }
      final response = openAiShape
          ? (_isAnthropic(route.provider)
              ? _anthropicResponseToOpenAi(upstream)
              : upstream)
          : (_isAnthropic(route.provider)
              ? upstream
              : _openAiResponseToAnthropic(upstream));
      _recordUsage(scope, tier, route, _usageOf(upstream));
      await _recordEvent(scope, tier, route, _usageOf(upstream));
      return _json(request, response);
    } on HttpException catch (e) {
      return _json(request, {'error': 'upstream unreachable: ${e.message}'},
          status: HttpStatus.badGateway);
    } on SocketException catch (e) {
      return _json(request, {'error': 'upstream unreachable: ${e.message}'},
          status: HttpStatus.badGateway);
    }
  }

  /// SSE passthrough (E2): forwards a streaming request to a SAME-protocol
  /// upstream and relays the chunks verbatim, flushing per chunk. Usage is
  /// harvested from the relayed `data:` lines — the OpenAI final-chunk usage
  /// object, or Anthropic's message_start (input) / message_delta (output) —
  /// and recorded like the non-streaming path.
  ///
  /// kimitail: cross-protocol streaming (an OpenAI caller on an Anthropic
  /// provider or vice versa) would need SSE event translation, not
  /// passthrough — rejected with a clear error; set stream=false there.
  /// Upgrade path: a chunk-by-chunk translator beside the response mappers.
  Future<void> _streamUpstream(
    HttpRequest request,
    ScopedToken scope,
    String tier,
    _Route route,
    Map<String, dynamic> body, {
    required bool openAiShape,
  }) async {
    final provider = route.provider;
    final anthropicUpstream = _isAnthropic(provider);
    if (anthropicUpstream == openAiShape) {
      return _json(request, {
        'error': 'streaming is pass-through only — tier "$tier" routes to an '
            '${anthropicUpstream ? 'Anthropic' : 'OpenAI'}-protocol provider; '
            'set stream=false for translated calls',
      }, status: HttpStatus.badRequest);
    }

    final upstreamBody = openAiShape
        ? _normalizeOpenAi(
            Map<String, dynamic>.of(body), provider.paramPolicy)
        : Map<String, dynamic>.of(body);
    upstreamBody['model'] = route.model;
    upstreamBody['stream'] = true;

    final HttpClientResponse upstream;
    try {
      final req = await _client
          .postUrl(Uri.parse(_upstreamUrl(provider, anthropicUpstream)));
      req.headers.contentType = ContentType.json;
      if (anthropicUpstream) {
        req.headers.set('x-api-key', route.apiKey);
        req.headers.set('anthropic-version', '2023-06-01');
      } else {
        req.headers.set('authorization', 'Bearer ${route.apiKey}');
      }
      req.write(jsonEncode(upstreamBody));
      upstream = await req.close();
    } on HttpException catch (e) {
      return _json(request, {'error': 'upstream unreachable: ${e.message}'},
          status: HttpStatus.badGateway);
    } on SocketException catch (e) {
      return _json(request, {'error': 'upstream unreachable: ${e.message}'},
          status: HttpStatus.badGateway);
    }

    final response = request.response;
    if (upstream.statusCode != HttpStatus.ok) {
      // Errors relay as JSON like the non-streaming path; nothing recorded.
      response.statusCode = upstream.statusCode;
      response.headers.contentType = ContentType.json;
      response.write(await utf8.decoder.bind(upstream).join());
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('text', 'event-stream');
    response.headers.set('cache-control', 'no-cache');
    response.bufferOutput = false;

    var tokensIn = 0;
    var tokensOut = 0;
    final pending = StringBuffer();
    try {
      await for (final text in utf8.decoder.bind(upstream)) {
        response.add(utf8.encode(text));
        // Scan complete SSE data lines for usage; the partial tail carries
        // over to the next chunk.
        pending.write(text);
        final lines = pending.toString().split('\n');
        pending.clear();
        pending.write(lines.removeLast());
        for (final line in lines) {
          if (!line.startsWith('data:') || line.startsWith('data: [DONE]')) {
            continue;
          }
          Object? decoded;
          try {
            decoded = jsonDecode(line.substring(5).trim());
          } on FormatException {
            continue; // Non-JSON data lines are relayed, never parsed.
          }
          if (decoded is! Map) continue;
          final map = decoded.cast<String, dynamic>();
          // Anthropic's message_start nests usage inside `message`.
          var (i, o) = _usageOf(map);
          if (i == 0 && o == 0 && map['message'] is Map) {
            (i, o) = _usageOf((map['message'] as Map).cast<String, dynamic>());
          }
          if (i > 0) tokensIn = i;
          if (o > 0) tokensOut = o;
        }
      }
      // Recorded BEFORE the response closes: the caller's stream completes
      // on close, so this ordering keeps the usage/event lands visible to
      // the caller once it holds the full stream.
      _recordUsage(scope, tier, route, (tokensIn, tokensOut));
      await _recordEvent(scope, tier, route, (tokensIn, tokensOut));
      await response.close();
    } on HttpException {
      // The caller hung up mid-stream; nothing more to relay, and a partial
      // stream records nothing.
    }
  }

  ScopedToken? _scopeOf(HttpRequest request) {
    // Accept OpenAI-style `Authorization: Bearer` and Anthropic-style
    // `x-api-key` — stage CLIs speak one or the other (E2).
    final auth = request.headers.value('authorization');
    final token = auth != null && auth.startsWith('Bearer ')
        ? auth.substring(7).trim()
        : request.headers.value('x-api-key');
    return token == null ? null : minter.verify(token);
  }

  /// First candidate in the tier whose provider has a vault key (E4).
  ///
  /// Maker/checker split (E4, stages.review.notes): for the review stage the
  /// build stage's provider is tried LAST — review ≠ build whenever the tier
  /// offers a keyed alternative; with no alternative the maker provider still
  /// serves (a 503 helps nobody). Behavior is unchanged when the providers
  /// already differ.
  Future<_Route?> _selectRoute(
      ModelFabric catalog, String tier, ScopedToken scope) async {
    var candidates = catalog.tiers[tier] ?? const <FabricModel>[];
    if (scope.consumer == 'pipeline-stage:review') {
      final buildTier = catalog.stages['build']?.tier;
      if (buildTier != null) {
        final maker = await _routeFor(
            catalog, catalog.tiers[buildTier] ?? const <FabricModel>[]);
        if (maker != null) {
          candidates = catalog.checkerFirst(tier, maker.provider.name);
        }
      }
    }
    return _routeFor(catalog, candidates);
  }

  /// First route in [candidates] whose provider has a vault key (E4).
  Future<_Route?> _routeFor(
      ModelFabric catalog, List<FabricModel> candidates) async {
    for (final candidate in candidates) {
      final FabricProvider provider;
      try {
        provider = catalog.provider(candidate.provider);
      } on ArgumentError {
        continue; // Candidate names an undeclared provider — skip it.
      }
      // Optional entries with no endpoint yet (e.g. fugu) cannot serve.
      if (provider.baseUrl == null) continue;
      final key = await vault.read(provider.keyRef);
      if (key != null && key.isNotEmpty) {
        return _Route(provider, candidate.model, key);
      }
    }
    return null;
  }

  Future<(int, Map<String, dynamic>)> _callUpstream(
    _Route route,
    Map<String, dynamic> body, {
    required bool openAiShape,
  }) async {
    final provider = route.provider;
    final anthropicUpstream = _isAnthropic(provider);

    final Map<String, dynamic> upstreamBody = anthropicUpstream
        ? (openAiShape
            ? _openAiToAnthropic(body)
            : Map<String, dynamic>.of(body))
        : _normalizeOpenAi(
            openAiShape ? body : _anthropicToOpenAi(body), provider.paramPolicy);
    upstreamBody['model'] = route.model;
    upstreamBody.remove('stream');

    final url = Uri.parse(_upstreamUrl(provider, anthropicUpstream));

    final req = await _client.postUrl(url);
    req.headers.contentType = ContentType.json;
    if (anthropicUpstream) {
      req.headers.set('x-api-key', route.apiKey);
      req.headers.set('anthropic-version', '2023-06-01');
    } else {
      req.headers.set('authorization', 'Bearer ${route.apiKey}');
    }
    req.write(jsonEncode(upstreamBody));
    final resp = await req.close();
    final text = await utf8.decoder.bind(resp).join();
    Map<String, dynamic> parsed;
    try {
      parsed = (jsonDecode(text) as Map).cast<String, dynamic>();
    } on FormatException {
      parsed = {'error': 'upstream returned non-JSON', 'body': text};
    }
    return (resp.statusCode, parsed);
  }

  /// The concrete upstream URL. Catalog `base_url`/`anthropic_url` values
  /// are unversioned for the anthropic-messages protocol — the gateway owns
  /// the `/v1/messages` suffix (trailing slash stripped first). OpenAI-style
  /// bases carry their version in the catalog (…/v1) and only get the
  /// `/chat/completions` suffix.
  static String _upstreamUrl(FabricProvider provider, bool anthropicUpstream) {
    final base =
        (anthropicUpstream ? (provider.anthropicUrl ?? provider.baseUrl) : provider.baseUrl)!;
    if (anthropicUpstream) {
      final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      return '$trimmed/v1/messages';
    }
    return '$base/chat/completions';
  }

  /// Per-provider quirk normalization (E4 `param_policy`), OpenAI shape only.
  /// Policy names are the canonical set in [ModelFabric.knownParamPolicies]:
  /// - `omit_temperature` — drop `temperature` (OpenAI reasoning models).
  /// - `omit_sampling` — drop `temperature` + `top_p` (Kimi errors on them).
  /// - `json_object_only` — map `response_format: json_schema` → `json_object`.
  /// - `echo_reasoning_content` — DeepSeek: strip echoed `reasoning_content`
  ///   from assistant messages unless they carry `tool_calls` (tool loops
  ///   must echo it or the upstream 400s).
  static Map<String, dynamic> _normalizeOpenAi(
      Map<String, dynamic> body, List<String> policy) {
    final b = Map<String, dynamic>.of(body);
    if (policy.contains('omit_temperature') || policy.contains('omit_sampling')) {
      b.remove('temperature');
    }
    if (policy.contains('omit_sampling')) {
      b.remove('top_p');
    }
    if (policy.contains('json_object_only')) {
      final rf = b['response_format'];
      if (rf is Map && rf['type'] == 'json_schema') {
        b['response_format'] = {'type': 'json_object'};
      }
    }
    if (policy.contains('echo_reasoning_content')) {
      for (final m in b['messages'] as List? ?? const []) {
        if (m is Map && m['role'] == 'assistant' && m['tool_calls'] == null) {
          m.remove('reasoning_content');
        }
      }
    }
    return b;
  }

  // --- shape translation ----------------------------------------------------
  // kimitail: text content only — tool_use/tool_result blocks and multimodal
  // parts collapse to their text. Add block pass-through when a consumer
  // actually drives a tool loop through the gateway.

  static String _textOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((b) => b['text'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  static Map<String, dynamic> _openAiToAnthropic(Map<String, dynamic> body) {
    final system = <String>[];
    final messages = <Map<String, dynamic>>[];
    for (final m in body['messages'] as List? ?? const []) {
      if (m is! Map) continue;
      final msg = m.cast<String, dynamic>();
      if (msg['role'] == 'system') {
        system.add(_textOf(msg['content']));
      } else {
        messages.add({
          'role': msg['role'],
          'content': _textOf(msg['content']),
        });
      }
    }
    final out = <String, dynamic>{
      'model': body['model'],
      'messages': messages,
      // kimitail: Anthropic requires max_tokens; 4096 ceiling when the caller
      // omitted it. Callers needing more set max_tokens explicitly.
      'max_tokens':
          body['max_tokens'] ?? body['max_completion_tokens'] ?? 4096,
    };
    if (system.isNotEmpty) out['system'] = system.join('\n');
    if (body['temperature'] != null) out['temperature'] = body['temperature'];
    if (body['top_p'] != null) out['top_p'] = body['top_p'];
    if (body['stop'] != null) out['stop_sequences'] = body['stop'];
    return out;
  }

  static Map<String, dynamic> _anthropicToOpenAi(Map<String, dynamic> body) {
    final messages = <Map<String, dynamic>>[
      if (body['system'] is String)
        {'role': 'system', 'content': body['system']},
      for (final m in body['messages'] as List? ?? const [])
        if (m is Map)
          {'role': m['role'], 'content': _textOf(m['content'])},
    ];
    final out = <String, dynamic>{'model': body['model'], 'messages': messages};
    if (body['max_tokens'] != null) out['max_tokens'] = body['max_tokens'];
    if (body['temperature'] != null) out['temperature'] = body['temperature'];
    if (body['top_p'] != null) out['top_p'] = body['top_p'];
    if (body['stop_sequences'] != null) out['stop'] = body['stop_sequences'];
    return out;
  }

  static Map<String, dynamic> _anthropicResponseToOpenAi(
      Map<String, dynamic> resp) {
    final usage = (resp['usage'] as Map?) ?? const {};
    final tokensIn = (usage['input_tokens'] as num?)?.toInt() ?? 0;
    final tokensOut = (usage['output_tokens'] as num?)?.toInt() ?? 0;
    return {
      'id': resp['id'] ?? 'chatcmpl-gateway',
      'object': 'chat.completion',
      'created': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      'model': resp['model'],
      'choices': [
        {
          'index': 0,
          'message': {
            'role': 'assistant',
            'content': _textOf(resp['content']),
          },
          'finish_reason': switch (resp['stop_reason']) {
            'max_tokens' => 'length',
            'tool_use' => 'tool_calls',
            _ => 'stop',
          },
        },
      ],
      'usage': {
        'prompt_tokens': tokensIn,
        'completion_tokens': tokensOut,
        'total_tokens': tokensIn + tokensOut,
      },
    };
  }

  static Map<String, dynamic> _openAiResponseToAnthropic(
      Map<String, dynamic> resp) {
    final choices = resp['choices'] as List? ?? const [];
    final first = choices.isNotEmpty ? choices.first as Map? : null;
    final message = (first?['message'] as Map?) ?? const {};
    final usage = (resp['usage'] as Map?) ?? const {};
    return {
      'id': resp['id'] ?? 'msg_gateway',
      'type': 'message',
      'role': 'assistant',
      'model': resp['model'],
      'content': [
        {'type': 'text', 'text': message['content'] ?? ''},
      ],
      'stop_reason': switch (first?['finish_reason']) {
        'length' => 'max_tokens',
        'tool_calls' => 'tool_use',
        _ => 'end_turn',
      },
      'usage': {
        'input_tokens': (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
        'output_tokens': (usage['completion_tokens'] as num?)?.toInt() ?? 0,
      },
    };
  }

  // --- usage attribution (E4 scorecard feed) --------------------------------

  static (int, int) _usageOf(Map<String, dynamic> resp) {
    final usage = resp['usage'];
    if (usage is! Map) return (0, 0);
    final tokensIn =
        ((usage['prompt_tokens'] ?? usage['input_tokens']) as num?)?.toInt() ??
            0;
    final tokensOut =
        ((usage['completion_tokens'] ?? usage['output_tokens']) as num?)
                ?.toInt() ??
            0;
    return (tokensIn, tokensOut);
  }

  void _recordUsage(
      ScopedToken scope, String tier, _Route route, (int, int) tokens) {
    final (tokensIn, tokensOut) = tokens;
    final file = File(p.join(repoRoot, 'pipeline', 'state', 'usage.jsonl'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode({
        'consumer_token_id': scope.id,
        'consumer': scope.consumer,
        'tier': tier,
        'provider': route.provider.name,
        'model': route.model,
        'tokens_in': tokensIn,
        'tokens_out': tokensOut,
        'ts': DateTime.now().toUtc().toIso8601String(),
      })}\n',
      mode: FileMode.append,
    );
  }

  /// Appends one `llm_request` MemoryEvent per served request (M1: the
  /// gateway is a deterministic writer of raw memory events). Best-effort:
  /// a write failure warns on stderr and never fails the request — the
  /// caller already holds the upstream's answer.
  Future<void> _recordEvent(ScopedToken scope, String tier, _Route route,
      (int, int) tokens) async {
    final (tokensIn, tokensOut) = tokens;
    try {
      await EventLog(p.join(repoRoot, 'pipeline', 'state')).append(MemoryEvent(
        kind: MemoryKinds.llmRequest,
        actor: 'gateway',
        payload: {
          'consumer': scope.consumer,
          'tier': tier,
          'provider': route.provider.name,
          'model': route.model,
          'tokens_in': tokensIn,
          'tokens_out': tokensOut,
          'ok': true,
        },
      ));
    } catch (e) {
      stderr.writeln('gateway: WARN memory event append failed: $e');
    }
  }

  Future<void> _json(HttpRequest request, Map<String, Object?> body,
      {int status = HttpStatus.ok}) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
