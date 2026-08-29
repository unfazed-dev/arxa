// The approvals tunnel client — the phone's transport to the engine half
// (grill D61/D62: engine HTTP over the iroh pairing tunnel's loopback
// proxy, direct POST with loud failure, never a queue).
//
// Routes are the engine plugin's (arxa-studio plugins/approvals):
//   GET  /__arxa/approvals            → { approvals: [record…] }
//   POST /__arxa/approvals/action     { action: 'decide', arg: { id, answers } }
//
// dart:io HttpClient on purpose: the app targets iOS/Android only and this
// avoids a new dependency for two JSON calls (the studioUrl base comes
// from the TransportService — no tunnel, no calls).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/transport_service.dart';
import 'approval.dart';

/// The tunnel is down or unusable — no loopback URL, or the request failed
/// at the transport level (socket refused, connection closed mid-response,
/// timeout — the zombie-link failure mode). D62's loud inline failure:
/// callers surface 'reconnect to act', never queue.
class ApprovalsOfflineException implements Exception {
  ApprovalsOfflineException([this.cause]);

  /// The underlying transport error, when there was one (null when the
  /// tunnel was simply not connected). Diagnostics only.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'not connected to the studio'
      : 'not connected to the studio ($cause)';
}

/// The engine refused the decision (409): someone answered first (first
/// claimant wins) or the approval is gone. Refreshing resolves the view.
class ApprovalsConflictException implements Exception {
  ApprovalsConflictException(this.reason);
  final String reason;
  @override
  String toString() => 'decision refused: $reason';
}

/// Any other non-200 from the engine.
class ApprovalsRemoteException implements Exception {
  ApprovalsRemoteException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'studio answered $status: $body';
}

class ApprovalsApiClient {
  ApprovalsApiClient({required this.transport, HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final TransportService transport;
  final HttpClient _httpClient;

  /// Current loopback base; null when the tunnel is down.
  Uri? get _base => transport.current.studioUrl;

  Future<List<Approval>> list() async {
    final body = await _json('GET', '/__arxa/approvals');
    return [
      for (final record in (body['approvals'] as List<dynamic>? ?? <dynamic>[]))
        Approval.fromJson(record as Map<String, dynamic>),
    ];
  }

  /// Answer a pending approval. Throws [ApprovalsConflictException] on 409,
  /// [ApprovalsOfflineException] with no tunnel.
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {
    await _json('POST', '/__arxa/approvals/action',
        body: {'action': 'decide', 'arg': {'id': id, 'answers': [for (final a in answers) a.toJson()]}});
  }

  Future<Map<String, dynamic>> _json(String method, String path,
      {Map<String, dynamic>? body}) async {
    final base = _base;
    if (base == null) throw ApprovalsOfflineException();
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
        throw ApprovalsConflictException(
            (jsonDecode(text)['error'] as String?) ?? 'not-pending');
      }
      if (response.statusCode != 200) {
        throw ApprovalsRemoteException(response.statusCode, text);
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on IOException catch (e) {
      // Refused/unreachable socket, connection closed mid-response — the
      // zombie link fails exactly here, fast, on every request.
      throw ApprovalsOfflineException(e);
    } on TimeoutException catch (e) {
      throw ApprovalsOfflineException(e);
    }
    // Non-IO errors stay loud and raw: a malformed engine body (FormatException)
    // is an engine bug, not an offline phone.
  }
}
