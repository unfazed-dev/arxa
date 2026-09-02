// The conversation tunnel client — same shape as the approvals client:
// engine HTTP over the iroh pairing tunnel's loopback proxy, dart:io
// HttpClient on purpose (no new dependency for JSON calls), no bearer
// header (the loopback proxy carries the auth).
//
// Routes are the LOCKED engine contract. The {id} below is the
// dshSessionId ("arxa-"-prefixed) form — the engine 404s
// (session-not-found) on the bare sidebar row id — and the transcript
// response echoes that same form as each message's sessionId:
//   GET  /__arxa/conversations                        -> { sessions: [...] }
//   GET  /__arxa/conversations/{id}/messages?limit=N  -> { sessionId, messages: [...] } | 404
//   POST /__arxa/conversations/{id}/messages          { text, mode? }

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/transport_service.dart';
import 'conversation.dart';

/// The tunnel is down or unusable — no loopback URL, or the request failed
/// at the transport level (the zombie-link failure mode). Callers surface
/// 'not connected' inline, never queue.
class ConversationOfflineException implements Exception {
  ConversationOfflineException([this.cause]);

  /// The underlying transport error, when there was one. Diagnostics only.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'not connected to the studio'
      : 'not connected to the studio ($cause)';
}

/// The engine refused the send (409): no live agent on that session.
/// Refreshing resolves the view.
class ConversationConflictException implements Exception {
  ConversationConflictException(this.reason);
  final String reason;
  @override
  String toString() => 'send refused: $reason';
}

/// Any other non-200 from the engine (including the 404 no-such-session).
class ConversationRemoteException implements Exception {
  ConversationRemoteException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'studio answered $status: $body';
}

class ConversationApiClient {
  ConversationApiClient({required this.transport, HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final TransportService transport;
  final HttpClient _httpClient;

  /// Current loopback base; null when the tunnel is down.
  Uri? get _base => transport.current.studioUrl;

  Future<List<CodeSession>> listSessions() async {
    final body = await _json('GET', '/__arxa/conversations');
    return [
      for (final record in (body['sessions'] as List<dynamic>? ?? <dynamic>[]))
        CodeSession.fromJson(record as Map<String, dynamic>),
    ];
  }

  /// The transcript for one session, ascending by seq, plus the session's
  /// effective sandbox mode (last sandbox/mode event, or the deployment
  /// default). A 404 (no-such-session) throws [ConversationRemoteException].
  Future<(String?, List<ConversationMessage>)> messages(String sessionId,
      {int limit = 200}) async {
    final body = await _json(
        'GET', '/__arxa/conversations/$sessionId/messages?limit=$limit');
    final messages = [
      for (final record in (body['messages'] as List<dynamic>? ?? <dynamic>[]))
        ConversationMessage.fromJson(record as Map<String, dynamic>),
    ];
    return (body['mode'] as String?, messages);
  }

  /// The session's model directory — current selection plus the advisory
  /// provider groups for the composer's model menu.
  Future<Map<String, dynamic>> models(String sessionId) async {
    return _json('GET', '/__arxa/conversations/$sessionId/models');
  }

  /// Select the model the session's next step uses.
  Future<void> selectModel(
      String sessionId, String provider, String model) async {
    await _json('POST', '/__arxa/conversations/$sessionId/model',
        body: {'provider': provider, 'model': model});
  }

  /// Switch the session's sandbox mode
  /// (read-only | workspace-write | danger-full-access).
  Future<void> setMode(String sessionId, String mode) async {
    await _json('POST', '/__arxa/conversations/$sessionId/mode',
        body: {'mode': mode});
  }

  /// Queue or steer a prompt into a session. [images] ride as base64
  /// content parts (the host admits count/bytes/media-type at admission).
  /// Throws [ConversationConflictException] on 409 (no live agent),
  /// [ConversationOfflineException] with no tunnel.
  Future<void> send(String sessionId, String text,
      {String mode = 'queue',
      List<({String mediaType, String data})> images = const []}) async {
    await _json('POST', '/__arxa/conversations/$sessionId/messages', body: {
      'text': text,
      'mode': mode,
      if (images.isNotEmpty)
        'images': [
          for (final image in images) {'mediaType': image.mediaType, 'data': image.data},
        ],
    });
  }

  /// One stored image attachment — { attachment: ref, data: base64 }. The
  /// host refuses ids this session never referenced (404 attachment-not-found).
  Future<Map<String, dynamic>> attachment(
      String sessionId, String attachmentId) async {
    return _json('GET', '/__arxa/conversations/$sessionId/attachments/$attachmentId');
  }

  /// The engine's human-command palette — the studio composer's `+` list,
  /// verbatim from the engine registry (compact/export/feedback/goal/
  /// permission/plan/model today; whatever the engine ships tomorrow).
  Future<List<EngineCommand>> commands(String sessionId) async {
    final body = await _json('GET', '/__arxa/conversations/$sessionId/commands');
    return [
      for (final record
          in (body['commands'] as List<dynamic>? ?? <dynamic>[]))
        EngineCommand.fromJson(record as Map<String, dynamic>),
    ];
  }

  /// Execute one slash-command line in the session (the registry answers
  /// from the log and its seams — the line never reaches the model).
  /// Returns the command's own kind/text; a 400 unknown-command and every
  /// other non-200 throw [ConversationRemoteException] with the body.
  Future<({String kind, String text})> runCommand(
      String sessionId, String line) async {
    final body = await _json(
        'POST', '/__arxa/conversations/$sessionId/commands',
        body: {'line': line});
    return (
      kind: body['kind'] as String? ?? 'success',
      text: body['text'] as String? ?? '',
    );
  }

  /// Download the transcript as a markdown file to [savePath]; returns
  /// the path (the share sheet's payload).
  Future<String> exportTranscript(String sessionId, String savePath) async {
    final base = _base;
    if (base == null) throw ConversationOfflineException();
    try {
      final request = await _httpClient
          .openUrl('GET', base.resolve('/__arxa/conversations/$sessionId/export'))
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final text = await response.transform(utf8.decoder).join();
        throw ConversationRemoteException(response.statusCode, text);
      }
      final sink = File(savePath).openWrite();
      await response.pipe(sink);
      return savePath;
    } on IOException catch (e) {
      throw ConversationOfflineException(e);
    } on TimeoutException catch (e) {
      throw ConversationOfflineException(e);
    }
  }

  // ---- the live rail -----------------------------------------------------

  final StreamController<ConversationLiveEvent> _live =
      StreamController<ConversationLiveEvent>.broadcast();
  HttpClientRequest? _liveRequest;
  bool _liveDialing = false;

  /// When the last live event arrived (null until the rail says anything,
  /// hello included). Consumers use it as the staleness guard: if the SSE
  /// carrier (the iroh loopback proxy) ever buffers a long-lived stream, a
  /// slow poll keeps the view honest while the rail stays up in spirit.
  DateTime? get lastLiveAt => _lastLiveAt;
  DateTime? _lastLiveAt;

  /// The engine's live pings (SSE). Broadcast: several screens subscribe
  /// to one shared connection. Reconnects with a short backoff on loss.
  Stream<ConversationLiveEvent> events() => _live.stream;

  void startLive() {
    if (_liveDialing || _liveRequest != null) return;
    if (!_live.hasListener) return;
    _liveDialing = true;
    _dialLive();
  }

  Future<void> _dialLive() async {
    final base = _base;
    if (base == null) {
      _liveDialing = false;
      return; // tunnel down — the connected announcement re-kicks startLive
    }
    try {
      final request = await _httpClient
          .openUrl('GET', base.resolve('/__arxa/conversations/events'))
          .timeout(const Duration(seconds: 10));
      request.headers.set('accept', 'text/event-stream');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const SocketException('live rail dial failed');
      }
      _liveRequest = request;
      _liveDialing = false;
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        // EVERY line is liveness — the 15s `: ping` comments prove the
        // carrier moves even when no event fires.
        _lastLiveAt = DateTime.now();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          _lastLiveAt = DateTime.now();
          _live.add(ConversationLiveEvent(
            type: json['type'] as String? ?? '',
            sessionId: json['sessionId'] as String?,
            reason: json['reason'] as String?,
          ));
        } on FormatException {
          continue; // a bad frame never kills the rail
        }
      }
      // server closed — fall through to the reconnect
    } on IOException {
      // dial failure or dropped mid-stream
    } on TimeoutException {
      // dial timeout
    } finally {
      _liveRequest = null;
      _liveDialing = false;
    }
    unawaited(Future<void>.delayed(const Duration(seconds: 2)).then((_) {
      startLive();
    }));
  }
  Future<Map<String, dynamic>> _json(String method, String path,
      {Map<String, dynamic>? body}) async {
    final base = _base;
    if (base == null) throw ConversationOfflineException();
    try {
      final request = await _httpClient.openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 10));
      request.headers.set('accept', 'application/json');
      if (body != null) {
        final encoded = jsonEncode(body);
        request.headers.set('content-type', 'application/json');
        request.headers.contentLength = utf8.encode(encoded).length;
        request.write(encoded);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 409) {
        throw ConversationConflictException(
            (jsonDecode(text)['error'] as String?) ?? 'no-live-agent');
      }
      if (response.statusCode != 200) {
        throw ConversationRemoteException(response.statusCode, text);
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on IOException catch (e) {
      // Refused/unreachable socket, connection closed mid-response — the
      // zombie link fails exactly here, fast, on every request.
      throw ConversationOfflineException(e);
    } on TimeoutException catch (e) {
      throw ConversationOfflineException(e);
    }
    // Non-IO errors stay loud and raw: a malformed engine body
    // (FormatException) is an engine bug, not an offline phone.
  }
}
