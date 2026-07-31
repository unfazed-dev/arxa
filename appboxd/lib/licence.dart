/// Offline licence verification for appbox (docs/plans/appbox-memory-and-payment.md,
/// P1/P2: Ed25519-signed licence file, verified fully offline by appboxd;
/// flat annual + perpetual fallback).
///
/// ## Licence file format
///
/// A single JSON document:
///
/// ```json
/// {
///   "payload": {
///     "email": "user@example.com",
///     "tier": "annual",              // "annual" | "perpetual"
///     "issued": "2026-07-30T00:00:00.000Z",
///     "expires": "2027-07-30T00:00:00.000Z",
///     "licence_id": "abx_01J..."
///   },
///   "signature": "<base64url of the 64-byte Ed25519 signature>"
/// }
/// ```
///
/// The canonical signing bytes are the payload re-encoded as JSON with
/// **sorted keys, no whitespace, UTF-8** (see [canonicalPayloadBytes]).
/// Because verification re-canonicalizes the parsed payload, insignificant
/// whitespace or key ordering in the file itself cannot break (or forge) a
/// signature. `signature` accepts padded or unpadded base64url.
///
/// - `annual`: unlocks while `now <= expires`; 30-day grace after expiry
///   ([Licence.gracePeriod], status `grace`, still unlocks); past grace the
///   status is `expired` (authentic licence, no longer unlocks).
/// - `perpetual`: never expires for running the app; `expires` marks the
///   end of the 12-month update window and is reported as
///   [LicenceVerdict.updatesUntil] so the daemon can later refuse
///   newer-version updates while the app keeps working.
/// - `invalid` means the file is present but forged, tampered, signed by a
///   wrong key, or malformed. `none` means no licence file exists.
///
/// kimitail: expiry trusts the local clock — a user who sets their clock
/// back extends their own licence. Accepted ceiling (Keygen's own guidance:
/// embed grace, expect clock manipulation, accept it); the upgrade path is
/// the optional online refresh in the plan, not more local cleverness.
library;

import 'dart:convert';
import 'dart:io';

import 'ed25519.dart';

enum LicenceStatus { valid, expired, grace, invalid, none }

class LicenceVerdict {
  const LicenceVerdict({
    required this.status,
    this.tier,
    this.email,
    this.expires,
    this.updatesUntil,
  });

  final LicenceStatus status;

  /// `annual` or `perpetual`; null unless the signature verified.
  final String? tier;
  final String? email;

  /// End of the paid term (annual) or of the update window (perpetual).
  final DateTime? expires;

  /// Perpetual licences only: last day of entitled updates (== [expires]).
  final DateTime? updatesUntil;

  /// Whether this verdict unlocks paid features (drives the CLI's
  /// paid/free mapping and exit code).
  bool get unlocks =>
      status == LicenceStatus.valid || status == LicenceStatus.grace;
}

class Licence {
  /// Grace period after expiry during which the licence still unlocks
  /// (research §2: offline grace runs days to months; 30 days per the plan).
  static const gracePeriod = Duration(days: 30);

  /// The appbox licence PUBLIC key (Ed25519, 32 bytes).
  ///
  /// DEV KEYPAIR — the matching private key lives in test/licence_test.dart
  /// so the whole flow is exercisable today. Replace this constant (and the
  /// issuer-side private key, which must never ship in this repo) with the
  /// production Totem keypair before the first paid release; nothing else
  /// in the verification path changes.
  static final List<int> publicKey = _hex(
      '518c1079955a7b617cbc99f77a13bf2261ca2eaecfa00acfaa790360a814f9ac');

  /// Verifies raw licence file bytes. [now] is injectable for tests.
  ///
  /// Never throws: every failure mode is a [LicenceStatus].
  static LicenceVerdict verify(List<int> fileBytes, {DateTime? now}) {
    final Object? doc;
    try {
      doc = jsonDecode(utf8.decode(fileBytes));
    } on FormatException {
      return const LicenceVerdict(status: LicenceStatus.invalid);
    }
    if (doc is! Map) return const LicenceVerdict(status: LicenceStatus.invalid);
    final payload = doc['payload'];
    final sigField = doc['signature'];
    if (payload is! Map || sigField is! String) {
      return const LicenceVerdict(status: LicenceStatus.invalid);
    }

    final List<int> signature;
    try {
      signature = base64Url.decode(base64Url.normalize(sigField));
    } on FormatException {
      return const LicenceVerdict(status: LicenceStatus.invalid);
    }
    final canonical = canonicalPayloadBytes(
        payload.map((k, v) => MapEntry(k.toString(), v)));
    if (!ed25519Verify(publicKey, canonical, signature)) {
      return const LicenceVerdict(status: LicenceStatus.invalid);
    }

    // Signature valid — payload is authentic. Shape-check the fields.
    final email = payload['email'];
    final tier = payload['tier'];
    final expiresRaw = payload['expires'];
    final expires =
        expiresRaw is String ? DateTime.tryParse(expiresRaw) : null;
    if (email is! String ||
        (tier != 'annual' && tier != 'perpetual') ||
        expires == null ||
        payload['issued'] is! String ||
        payload['licence_id'] is! String) {
      return const LicenceVerdict(status: LicenceStatus.invalid);
    }

    if (tier == 'perpetual') {
      // Perpetual fallback: the app keeps working forever; expires is the
      // end of the 12-month update window, surfaced as updatesUntil.
      return LicenceVerdict(
        status: LicenceStatus.valid,
        tier: tier,
        email: email,
        expires: expires,
        updatesUntil: expires,
      );
    }

    final clock = now ?? DateTime.now();
    if (!clock.isAfter(expires)) {
      return LicenceVerdict(
          status: LicenceStatus.valid,
          tier: tier,
          email: email,
          expires: expires);
    }
    if (!clock.isAfter(expires.add(gracePeriod))) {
      return LicenceVerdict(
          status: LicenceStatus.grace,
          tier: tier,
          email: email,
          expires: expires);
    }
    return LicenceVerdict(
        status: LicenceStatus.expired,
        tier: tier,
        email: email,
        expires: expires);
  }

  /// Verifies the licence file at [path]; [LicenceStatus.none] when the
  /// file does not exist.
  static LicenceVerdict verifyFile(String path, {DateTime? now}) {
    final file = File(path);
    if (!file.existsSync()) {
      return const LicenceVerdict(status: LicenceStatus.none);
    }
    return verify(file.readAsBytesSync(), now: now);
  }
}

/// Canonical signing bytes: payload JSON with sorted keys, no whitespace,
/// UTF-8. Values must be JSON scalars (the payload is flat by format).
List<int> canonicalPayloadBytes(Map<String, Object?> payload) {
  final keys = payload.keys.toList()..sort();
  final buf = StringBuffer('{');
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) buf.write(',');
    buf
      ..write(jsonEncode(keys[i]))
      ..write(':')
      ..write(jsonEncode(payload[keys[i]]));
  }
  buf.write('}');
  return utf8.encode(buf.toString());
}

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];
