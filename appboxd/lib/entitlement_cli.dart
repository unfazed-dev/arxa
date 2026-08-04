/// Entitlement CLI (`appbox entitlement …`) — the operator surface for the
/// cached entitlement JWT. Mirrors the retired licence_tool's shape.
///
///   `appbox entitlement status [--token <path>]`
///   `appbox entitlement verify <file>`
///   `appbox entitlement mint --dev [--token <path>]`
///
/// `status` prints exactly one JSON line to stdout — the contract other
/// appbox code consumes:
///
///   {"status":"entitled"|"unentitled"|"none","features":...,"expires":...}
///
/// where entitled = valid|grace (expired past grace, tampered/invalid,
/// wrong-machine, and unreadable tokens all report unentitled; a missing
/// token reports none). `reason` always carries the honest verdict text.
/// Exit code: 0 when the entitlement unlocks (valid/grace), 1 otherwise.
///
/// Token path resolution for `status`: `--token <path>` when given, else
/// `~/.appbox/entitlement.jwt` (the one cache location — the entitlement is
/// per-user, never per-repo).
///
/// `verify <file>` is the diagnostic form: prints the raw verdict
/// (valid|grace|expired|invalid|none plus subject/features/expires) for the
/// given file only. Same exit-code rule.
///
/// `mint --dev` is the DEV-ONLY dogfood path: it signs a 7-day entitlement
/// for THIS machine with the dev keypair (the private half of the DEV public
/// key embedded in entitlement.dart — a test fixture, never a production
/// secret) and writes the token to `--token <path>` or the default cache
/// location. It refuses to run the moment the embedded public key is no
/// longer the dev key (i.e. the production keypair has landed).
library;

import 'dart:convert';
import 'dart:io';

import 'ed25519.dart';
import 'entitlement.dart';

/// DEV keypair private seed — matches the DEV public key in
/// entitlement.dart and the fixture in test/entitlement_fixture.dart. Not a
/// production secret; replaced together with the public key before the first
/// paid release.
final _devSeed = _hex(
    '37346f25f6ff375d0901448591d7cb81c4684b25e57d0a1e3882579296873809');

/// Entry point for `appbox entitlement`. Returns the process exit code.
int entitlementMain(List<String> args) {
  if (args.isEmpty) _usage();
  switch (args.first) {
    case 'status':
      return _status(args.sublist(1));
    case 'verify':
      if (args.length != 2) _usage();
      return _verify(args[1]);
    case 'mint':
      return _mint(args.sublist(1));
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln('usage: appbox entitlement status [--token <path>] | '
      'appbox entitlement verify <file> | '
      'appbox entitlement mint --dev [--token <path>]');
  exit(64);
}

int _status(List<String> args) {
  String? explicit;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--token' && i + 1 < args.length) {
      explicit = args[i + 1];
      i++;
    } else {
      _usage();
    }
  }

  final verdict = Entitlement.verifyCurrent(path: explicit);
  if (verdict.status == EntitlementStatus.none) {
    _print({
      'status': 'none',
      'features': null,
      'expires': null,
      'reason': verdict.reason,
    });
    return 1;
  }
  _print({
    'status': verdict.unlocks ? 'entitled' : 'unentitled',
    'features': verdict.features,
    'expires': verdict.expires?.toIso8601String(),
    'reason': verdict.reason,
  });
  return verdict.unlocks ? 0 : 1;
}

int _verify(String path) {
  final verdict = Entitlement.verifyFile(path);
  _print({
    'status': verdict.status.name,
    'subject': verdict.subject,
    'features': verdict.features,
    'expires': verdict.expires?.toIso8601String(),
    'reason': verdict.reason,
    'file': path,
  });
  return verdict.unlocks ? 0 : 1;
}

void _print(Map<String, Object?> json) => stdout.writeln(jsonEncode(json));

int _mint(List<String> args) {
  var dev = false;
  String? explicit;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--dev') {
      dev = true;
    } else if (args[i] == '--token' && i + 1 < args.length) {
      explicit = args[i + 1];
      i++;
    } else {
      _usage();
    }
  }
  if (!dev) {
    stderr.writeln('appbox entitlement mint: --dev is required — there is no '
        'production mint path in this repo (tokens are issued by the '
        '/activate Edge Function).');
    return 64;
  }

  // Dev-only guard: if the embedded public key no longer matches the dev
  // seed, the production keypair has landed and this command must die loudly.
  final derivedPub = _devPublicKey();
  if (!_listEquals(derivedPub, Entitlement.publicKey)) {
    stderr.writeln('REFUSING TO MINT: the public key embedded in '
        'lib/entitlement.dart is NOT the dev keypair — `mint --dev` is '
        'disabled against a production key. Get a real entitlement via '
        'activation instead.');
    return 1;
  }

  final fpr = Entitlement.machineFingerprint();
  if (fpr == null) {
    stderr.writeln('appbox entitlement mint: cannot determine this machine’s '
        'fingerprint — nothing to bind the token to.');
    return 1;
  }

  final path = explicit ?? Entitlement.defaultPath();
  if (path == null) {
    stderr.writeln(
        'appbox entitlement mint: no home directory — nowhere to write.');
    return 1;
  }

  final now = DateTime.now();
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;
  final expSec =
      nowSec + const Duration(days: 7).inSeconds; // dev tokens: 7 days
  final claims = <String, Object?>{
    'sub': 'appbox-dev',
    'fpr': fpr,
    'feat': const [Entitlement.requiredFeature],
    'iat': nowSec,
    'nbf': nowSec,
    'exp': expSec,
  };
  final header = _b64url(utf8.encode(jsonEncode({'alg': 'EdDSA', 'typ': 'JWT'})));
  final payload = _b64url(utf8.encode(jsonEncode(claims)));
  final sig = _b64url(_devSign(utf8.encode('$header.$payload')));
  final token = '$header.$payload.$sig';

  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(token);

  stderr.writeln('WARNING: DEV entitlement minted — signed with the embedded '
      'DEV keypair (not a production secret), bound to this machine only, '
      'expires ${DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true).toIso8601String()}.');
  _print({
    'status': 'minted',
    'dev': true,
    'subject': claims['sub'],
    'features': claims['feat'],
    'expires': DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true)
        .toIso8601String(),
    'file': path,
  });
  return 0;
}

// ── DEV-only Ed25519 signer ─────────────────────────────────────────
// kimitail: duplicates the RFC 8032 math in test/entitlement_fixture.dart —
// lib cannot import test, and entitlement.dart is verify-only and owned by
// another workstream. Upgrade path: move TestKey into lib when the real
// issuer lands and delete both copies.

final _l = BigInt.two.pow(252) +
    BigInt.parse('27742317777372353535851937790883648493');

BigInt _leInt(List<int> bytes) {
  var v = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(bytes[i]);
  }
  return v;
}

List<int> _leBytes(BigInt v, int length) {
  final out = List<int>.filled(length, 0);
  var n = v;
  for (var i = 0; i < length; i++) {
    out[i] = (n & BigInt.from(0xff)).toInt();
    n = n >> 8;
  }
  return out;
}

List<int> _devPublicKey() {
  final h = sha512(_devSeed).sublist(0, 32);
  h[0] &= 248;
  h[31] &= 127;
  h[31] |= 64;
  return ed25519ScalarMultBase(_leInt(h));
}

List<int> _devSign(List<int> message) {
  final pub = _devPublicKey();
  final h = sha512(_devSeed);
  final aBytes = h.sublist(0, 32);
  aBytes[0] &= 248;
  aBytes[31] &= 127;
  aBytes[31] |= 64;
  final a = _leInt(aBytes);
  final prefix = h.sublist(32);
  final r = _leInt(sha512([...prefix, ...message]));
  final rEnc = ed25519ScalarMultBase(r);
  final k = _leInt(sha512([...rEnc, ...pub, ...message])) % _l;
  final s = (r + k * a) % _l;
  return [...rEnc, ..._leBytes(s, 32)];
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _b64url(List<int> bytes) => base64Url.encode(bytes);

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];
