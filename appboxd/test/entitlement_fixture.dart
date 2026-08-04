// Test-only entitlement fixtures: an Ed25519 signing helper (lib is
// verify-only by design), the DEV keypair whose public half is embedded in
// lib/entitlement.dart, and a compact-JWS minter.
//
// DEV KEYPAIR — the private seed below is a test fixture, never a production
// secret. It matches the DEV public key in lib/entitlement.dart; both are
// replaced together before the first paid release (see Entitlement.publicKey).
// Seed = first 32 bytes of
// sha512('appbox entitlement DEV keypair v1 — replace before first release').

import 'dart:convert';

import 'package:appboxd/ed25519.dart';
import 'package:appboxd/entitlement.dart';

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

class TestKey {
  TestKey(this.seed);

  /// 32-byte seed (RFC 8032 "secret key").
  final List<int> seed;

  late final BigInt _a = () {
    final h = sha512(seed).sublist(0, 32);
    h[0] &= 248;
    h[31] &= 127;
    h[31] |= 64;
    return _leInt(h);
  }();

  late final List<int> publicKey = ed25519ScalarMultBase(_a);

  List<int> sign(List<int> message) {
    final prefix = sha512(seed).sublist(32);
    final r = _leInt(sha512([...prefix, ...message]));
    final rEnc = ed25519ScalarMultBase(r);
    final k = _leInt(sha512([...rEnc, ...publicKey, ...message])) % _l;
    final s = (r + k * _a) % _l;
    return [...rEnc, ..._leBytes(s, 32)];
  }
}

/// DEV keypair — private half of the dev public key embedded in
/// lib/entitlement.dart. TEST FIXTURE ONLY.
final devEntitlementKey = TestKey(_hex(
    '37346f25f6ff375d0901448591d7cb81c4684b25e57d0a1e3882579296873809'));

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];

String _b64json(Map<String, Object?> doc) =>
    base64Url.encode(utf8.encode(jsonEncode(doc)));

/// Mints a compact-JWS entitlement token the way the `/activate` Edge
/// Function will (docs/plans/entitlement-backend-runbook.md): the signature
/// covers the exact `header.payload` bytes.
String makeEntitlementJwt(TestKey key, Map<String, Object?> claims,
    {Map<String, Object?>? header}) {
  final h = _b64json(header ?? const {'alg': 'EdDSA', 'typ': 'JWT'});
  final p = _b64json(claims);
  final sig = base64Url.encode(key.sign(utf8.encode('$h.$p')));
  return '$h.$p.$sig';
}

/// Well-formed claims for [fpr] spanning [nbf]..[exp] (epoch seconds).
Map<String, Object?> entitlementClaims({
  required String fpr,
  required int nbf,
  required int exp,
  List<String> feat = const ['emit.scaffold'],
}) =>
    {
      'sub': 'user_dev_01',
      'fpr': fpr,
      'feat': feat,
      'iat': nbf,
      'nbf': nbf,
      'exp': exp,
    };

/// A stand-in fingerprint for unit tests (verification injects the same
/// value, so the machine binding is exercised without touching the OS).
const testFingerprint =
    'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';

/// This machine's real fingerprint, for tests that exercise the gates (which
/// resolve the fingerprint themselves). Fails loudly when the platform
/// cannot supply one — the binding is unverifiable there, and skipping would
/// hide it.
String localFingerprint() {
  final fpr = Entitlement.machineFingerprint();
  assert(fpr != null, 'machine fingerprint undeterminable on this platform');
  return fpr!;
}
