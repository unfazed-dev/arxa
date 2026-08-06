import 'appbox_kit_consent_record.dart';

/// Persistence port for [AppBoxKitConsentRecord]s.
///
/// Anonymous (`userId == null`) and per-user records are **separate tracks**: a
/// query for one never returns records from the other (`userId` is matched
/// exactly, not treated as a wildcard). Implementations are append-only logs —
/// [withdraw] adds a withdrawal record rather than deleting.
abstract interface class AppBoxKitConsentStore {
  /// Appends [record] to the log.
  Future<void> record(AppBoxKitConsentRecord record);

  /// Appends a withdrawal for [documentId] on the given user track.
  ///
  /// [documentVersion] and [appVersion] are stored on the withdrawal record so
  /// the log stays self-describing.
  Future<void> withdraw({
    required String documentId,
    required String documentVersion,
    required String appVersion,
    String? userId,
    DateTime? at,
  });

  /// The most recent record for [documentId] on the [userId] track (null =
  /// anonymous), or null if none. Ties on [AppBoxKitConsentRecord.acceptedAt] break
  /// by insertion order.
  Future<AppBoxKitConsentRecord?> latestFor(String documentId, {String? userId});

  /// Records on the [userId] track (null = anonymous), oldest first, optionally
  /// narrowed to a single [documentId]. The track filter is always applied —
  /// pass the matching [userId] to audit a specific user.
  Future<List<AppBoxKitConsentRecord>> history({String? documentId, String? userId});
}

/// The working default [AppBoxKitConsentStore] — an in-memory append-only log.
///
/// Suitable for tests and for apps that bind their own durable store later; the
/// full cross-track log is available via [records] for audit/debugging.
class InMemoryAppBoxKitConsentStore implements AppBoxKitConsentStore {
  final List<_LoggedRecord> _log = <_LoggedRecord>[];
  int _seq = 0;

  @override
  Future<void> record(AppBoxKitConsentRecord record) async {
    _log.add(_LoggedRecord(record, _seq++));
  }

  @override
  Future<void> withdraw({
    required String documentId,
    required String documentVersion,
    required String appVersion,
    String? userId,
    DateTime? at,
  }) async {
    _log.add(_LoggedRecord(
      AppBoxKitConsentRecord(
        documentId: documentId,
        documentVersion: documentVersion,
        userId: userId,
        acceptedAt: at ?? DateTime.now(),
        method: AppBoxKitConsentMethod.withdrawn,
        appVersion: appVersion,
      ),
      _seq++,
    ));
  }

  @override
  Future<AppBoxKitConsentRecord?> latestFor(String documentId,
      {String? userId}) async {
    _LoggedRecord? best;
    for (final entry in _log) {
      final r = entry.record;
      if (r.documentId != documentId) continue;
      if (r.userId != userId) continue; // exact track; null == anonymous.
      if (best == null || _isAfter(entry, best)) best = entry;
    }
    return best?.record;
  }

  @override
  Future<List<AppBoxKitConsentRecord>> history(
      {String? documentId, String? userId}) async {
    final matches = _log.where((entry) {
      final r = entry.record;
      if (r.userId != userId) return false; // exact track; null == anonymous.
      if (documentId != null && r.documentId != documentId) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final byTime = a.record.acceptedAt.compareTo(b.record.acceptedAt);
        return byTime != 0 ? byTime : a.seq.compareTo(b.seq);
      });
    return List<AppBoxKitConsentRecord>.unmodifiable(
        [for (final entry in matches) entry.record]);
  }

  /// The full append-ordered log across **all** tracks (audit/debug only).
  List<AppBoxKitConsentRecord> get records =>
      List<AppBoxKitConsentRecord>.unmodifiable(
          [for (final entry in _log) entry.record]);

  bool _isAfter(_LoggedRecord a, _LoggedRecord b) {
    final byTime = a.record.acceptedAt.compareTo(b.record.acceptedAt);
    return byTime != 0 ? byTime > 0 : a.seq > b.seq;
  }
}

class _LoggedRecord {
  _LoggedRecord(this.record, this.seq);

  final AppBoxKitConsentRecord record;
  final int seq;
}
