/// Offline entitlement verification for arxa
/// (docs/plans/monetization-and-entitlements.md, D17/D18: the paywall moves
/// from deploy to scaffold; a Supabase-issued entitlement JWT, verified fully
/// offline by arxa against a pinned public key, machine-bound).
///
/// ## Token format
///
/// The entitlement is a compact JWS (`header.payload.signature`, base64url)
/// signed with Ed25519 (`{"alg":"EdDSA","typ":"JWT"}`), cached at
/// `~/.arxa/entitlement.jwt`. Claims (the exact contract the `/activate`
/// Edge Function issues — see docs/plans/entitlement-backend-runbook.md):
///
/// ```json
/// {
///   "sub":  "<user id>",
///   "fpr":  "<sha256 hex of the machine fingerprint>",
///   "feat": ["emit.scaffold"],
///   "iat":  1780000000,
///   "nbf":  1780000000,
///   "exp":  1780604800
/// }
/// ```
///
/// The signature covers the exact compact `header.payload` bytes — the
/// verifier never re-encodes, so no canonicalization game can forge a token.
/// `alg` must be `EdDSA`; anything else (including `none`) is `invalid`.
///
/// ## Verdict semantics (mirrors licence.dart's 5-state shape)
///
/// - `valid`: signature verifies, claims well-formed, `nbf <= now <= exp`,
///   and `fpr` matches this machine. Unlocks.
/// - `grace`: authentic and machine-bound but `exp < now <= exp + gracePeriod`
///   (offline continuation — Supabase downtime never blocks a paying user).
///   Unlocks.
/// - `expired`: authentic and machine-bound but past grace. Does not unlock;
///   subject/features are still reported, unlike `invalid`.
/// - `invalid`: forged, tampered, wrong key, malformed, not-yet-valid (`nbf`),
///   missing the `emit.scaffold` feature, or bound to a different machine.
/// - `none`: no token file exists.
///
/// Never fails open: unreadable/missing/invalid/expired/fingerprint-mismatch
/// all map to a non-unlocking verdict with an honest [EntitlementVerdict.reason].
///
/// kimitail: expiry/nbf trust the local clock — a user who sets their clock
/// back extends their own entitlement. Accepted ceiling (same as licence.dart:
/// embed grace, expect clock manipulation, accept it); the upgrade path is the
/// silent refresh in the plan, not more local cleverness.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto_aead.dart';
import 'ed25519.dart';

enum EntitlementStatus { valid, grace, expired, invalid, none }

class EntitlementVerdict {
  const EntitlementVerdict({
    required this.status,
    required this.reason,
    this.subject,
    this.features,
    this.expires,
  });

  final EntitlementStatus status;

  /// Human-honest explanation of the verdict — shown verbatim by the gate and
  /// the CLI. Never empty.
  final String reason;

  /// `sub` claim; null unless the signature verified.
  final String? subject;

  /// `feat` claim; null unless the signature verified.
  final List<String>? features;

  /// `exp` claim; null unless the signature verified.
  final DateTime? expires;

  /// Whether this verdict unlocks entitled features (drives the scaffold
  /// gate and the CLI's exit code).
  bool get unlocks =>
      status == EntitlementStatus.valid || status == EntitlementStatus.grace;
}

class Entitlement {
  /// Offline-continuation grace after `exp` during which the token still
  /// unlocks (reuses licence.dart's grace math per workstream 4: Supabase
  /// downtime must never block a paying user).
  static const gracePeriod = Duration(days: 30);

  /// The feature the scaffold boundary requires (D17).
  static const requiredFeature = 'emit.scaffold';

  /// Default cache location: `~/.arxa/entitlement.jwt`.
  static String? defaultPath() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? null : '$home/.arxa/entitlement.jwt';
  }

  /// The arxa entitlement PUBLIC key (Ed25519, 32 bytes).
  ///
  /// DEV KEYPAIR — the matching private key lives in
  /// test/entitlement_fixture.dart so the whole flow is exercisable today.
  /// Replace this constant (and the issuer-side private key, which must never
  /// ship in this repo) with the production Totem keypair before the first
  /// paid release; nothing else in the verification path changes.
  static final List<int> publicKey = _hex(
      'f3251c81da2ad5932308ec72886a19ea0c0309ef115417fffb41e746522fdd07');

  /// Verifies a compact-JWS entitlement [token]. [now] and [fingerprint]
  /// (the sha256-hex machine fingerprint) are injectable for tests; a null
  /// [fingerprint] resolves to this machine's.
  ///
  /// Never throws: every failure mode is an [EntitlementStatus].
  static EntitlementVerdict verify(String token,
      {DateTime? now, String? fingerprint}) {
    const invalid = EntitlementVerdict(
        status: EntitlementStatus.invalid, reason: 'malformed token');

    final parts = token.trim().split('.');
    if (parts.length != 3) return invalid;

    final Object? header;
    final Object? payload;
    final List<int> signature;
    try {
      header = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
      payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      signature = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      return invalid;
    }
    if (header is! Map || payload is! Map || signature.length != 64) {
      return invalid;
    }
    if (header['alg'] != 'EdDSA') {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'unsupported alg (EdDSA only)');
    }

    // The signature covers the exact compact bytes — never re-encoded.
    final signingInput = utf8.encode('${parts[0]}.${parts[1]}');
    if (!ed25519Verify(publicKey, signingInput, signature)) {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid, reason: 'bad signature');
    }

    // Signature valid — claims are authentic. Shape-check them.
    final sub = payload['sub'];
    final fpr = payload['fpr'];
    final feat = payload['feat'];
    final exp = payload['exp'];
    final nbf = payload['nbf'];
    final features =
        feat is List ? feat.whereType<String>().toList() : const <String>[];
    if (sub is! String ||
        sub.isEmpty ||
        fpr is! String ||
        !_isSha256Hex(fpr) ||
        feat is! List ||
        feat.length != features.length ||
        exp is! int ||
        nbf is! int) {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid, reason: 'malformed claims');
    }
    // Range-check BEFORE constructing DateTimes (the contract above is
    // "never throws"): DateTime accepts ±8640000000000000 ms. Compare in
    // seconds, before multiplying, so a huge exp/nbf can neither overflow
    // DateTime nor wrap `* 1000` into a plausible 1969/1970 instant.
    const maxEpochSeconds = 8640000000000; // 8640000000000000 ms
    if (exp > maxEpochSeconds ||
        exp < -maxEpochSeconds ||
        nbf > maxEpochSeconds ||
        nbf < -maxEpochSeconds) {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'malformed claims (exp/nbf out of range)');
    }
    final expires =
        DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);

    if (!features.contains(requiredFeature)) {
      return EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'token lacks the $requiredFeature feature',
          subject: sub,
          features: features,
          expires: expires);
    }

    final clock = now ?? DateTime.now();
    final nowSec = clock.millisecondsSinceEpoch ~/ 1000;
    if (nowSec < nbf) {
      return EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'token not yet valid (nbf)',
          subject: sub,
          features: features,
          expires: expires);
    }

    // Machine binding: the token is for exactly one fingerprint.
    final local = fingerprint ?? machineFingerprint();
    if (local == null) {
      return EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'cannot determine this machine’s fingerprint',
          subject: sub,
          features: features,
          expires: expires);
    }
    if (local.toLowerCase() != fpr.toLowerCase()) {
      return EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'token is bound to a different machine',
          subject: sub,
          features: features,
          expires: expires);
    }

    if (nowSec <= exp) {
      return EntitlementVerdict(
          status: EntitlementStatus.valid,
          reason: 'entitled',
          subject: sub,
          features: features,
          expires: expires);
    }
    if (!clock.isAfter(expires.add(gracePeriod))) {
      return EntitlementVerdict(
          status: EntitlementStatus.grace,
          reason: 'expired, inside the offline-continuation grace',
          subject: sub,
          features: features,
          expires: expires);
    }
    return EntitlementVerdict(
        status: EntitlementStatus.expired,
        reason: 'expired past the offline-continuation grace',
        subject: sub,
        features: features,
        expires: expires);
  }

  /// Verifies the token file at [path]; [EntitlementStatus.none] when the
  /// file does not exist, `invalid` when it cannot be read or is not a
  /// regular file (a directory is a tampered/operator-error path, not a
  /// missing token).
  static EntitlementVerdict verifyFile(String path,
      {DateTime? now, String? fingerprint}) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      return const EntitlementVerdict(
          status: EntitlementStatus.none, reason: 'no entitlement token');
    }
    if (type != FileSystemEntityType.file) {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'entitlement path is not a file');
    }
    final String token;
    try {
      token = File(path).readAsStringSync();
    } catch (_) {
      return const EntitlementVerdict(
          status: EntitlementStatus.invalid,
          reason: 'entitlement token unreadable');
    }
    return verify(token, now: now, fingerprint: fingerprint);
  }

  /// Verifies the cached token at [path] (default [defaultPath]) against this
  /// machine. The one call the gates and CLI make.
  static EntitlementVerdict verifyCurrent({String? path, DateTime? now}) {
    final resolved = path ?? defaultPath();
    if (resolved == null) {
      return const EntitlementVerdict(
          status: EntitlementStatus.none,
          reason: 'no home directory — nowhere to cache an entitlement');
    }
    return verifyFile(resolved, now: now);
  }

  /// This machine's fingerprint: sha256 hex of the raw per-OS machine id
  /// (macOS `IOPlatformUUID`, Windows `MachineGuid`, Linux machine-id), never
  /// the raw id itself. Null when the id cannot be determined — callers must
  /// treat null as NOT entitled (fail closed). Never throws.
  static String? machineFingerprint() {
    final raw = _rawMachineId();
    if (raw == null || raw.isEmpty) return null;
    return hexEncode(sha256(Uint8List.fromList(utf8.encode(raw))));
  }

  static String? _rawMachineId() {
    try {
      if (Platform.isMacOS) {
        // Absolute path: resolving `ioreg` through PATH lets a spoofed
        // earlier PATH entry supply a fake IOPlatformUUID and unlock tokens
        // bound to another machine.
        final res = Process.runSync(
            '/usr/sbin/ioreg', const ['-rd1', '-c', 'IOPlatformExpertDevice']);
        final m = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"')
            .firstMatch(res.stdout as String);
        return m?.group(1);
      }
      if (Platform.isWindows) {
        final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        final res = Process.runSync('$sysRoot\\System32\\reg.exe', const [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ]);
        final m = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)')
            .firstMatch(res.stdout as String);
        return m?.group(1);
      }
      if (Platform.isLinux) {
        for (final p in const ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
          final f = File(p);
          if (f.existsSync()) return f.readAsStringSync().trim();
        }
      }
    } catch (_) {
      // fall through: undeterminable
    }
    return null;
  }
}

/// Fail-closed scaffold-boundary assertion (D17/D18: the paywall sits at
/// scaffold). Shared by `scaffoldMain` (primary hook, in the emitter's
/// execution path) and `scaffoldGate` (redundant second layer). Never throws;
/// every failure is a red verdict carrying an activation message — an
/// entitlement failure is never a sarif finding (a gate that goes red for
/// payment teaches people to distrust red).
({bool passed, String okLine, List<String> failLines}) entitlementAssertion(
    {String? path}) {
  final verdict = Entitlement.verifyCurrent(path: path);
  if (verdict.unlocks) {
    final grace =
        verdict.status == EntitlementStatus.grace ? ' (offline grace)' : '';
    final exp = verdict.expires != null
        ? ', expires: ${verdict.expires!.toIso8601String()}'
        : '';
    return (
      passed: true,
      okLine: 'entitlement: ${Entitlement.requiredFeature}$grace$exp — '
          'scaffold permitted',
      failLines: const <String>[],
    );
  }
  return (
    passed: false,
    okLine: '',
    failLines: [
      'PRECONDITION NOT MET: entitlement — ${verdict.reason}.',
      'Scaffold is the paid boundary (D17/D18): the automated design→Flutter '
          'conversion requires a Pro entitlement; design + eject stay free '
          'forever.',
      'Inspect the cached entitlement with `arxa entitlement status` '
          '(~/.arxa/entitlement.jwt), then re-run.',
    ],
  );
}

bool _isSha256Hex(String s) =>
    s.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s);

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];
