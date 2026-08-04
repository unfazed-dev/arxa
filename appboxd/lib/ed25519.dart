/// Verify-only Ed25519 in pure Dart (dart:core only — no packages).
///
/// This is a direct port of the RFC 8032 Section 6 reference implementation
/// (the "Ed25519 Python Illustration"), which is the ref10-style algorithm
/// spelled out with arbitrary-precision integers: field arithmetic mod
/// 2^255-19, point decompression per Section 5.1.3, extended-homogeneous
/// point addition per Section 5.1.4, and the double-scalar verification
/// equation [S]B == R + [k]A per Section 5.1.7.
///
/// Proven against the RFC 8032 Section 7.1 test vectors in
/// test/entitlement_test.dart — those vectors are the acceptance bar.
///
/// Signing is deliberately NOT in this library: the daemon only ever
/// verifies entitlement tokens against the embedded public key. The two
/// helpers at the bottom ([ed25519ScalarMultBase], [sha512]) are exposed for
/// test and token-issuance tooling; the daemon's runtime path uses only
/// [ed25519Verify].
///
/// VM-only: SHA-512 below relies on 64-bit wrapping integer arithmetic,
/// which the Dart VM provides but dart2js does not. appboxd is a VM daemon,
/// so this is fine — do not import this file from Flutter web code.
library;

// ---------------------------------------------------------------------------
// SHA-512 (FIPS 180-4) — needed for the Ed25519 hash; no crypto package
// allowed, so this is the stdlib-only implementation.
// ---------------------------------------------------------------------------

const List<int> _sha512K = [
  0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
  0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
  0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
  0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
  0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
  0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
  0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
  0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
  0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
  0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
  0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
  0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
  0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
  0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
  0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
  0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
  0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
  0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
  0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
  0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
];

int _rotr64(int x, int n) => (x >>> n) | (x << (64 - n));

/// SHA-512 digest of [data] (FIPS 180-4). Exposed for token tooling/tests.
List<int> sha512(List<int> data) {
  var h0 = 0x6a09e667f3bcc908, h1 = 0xbb67ae8584caa73b;
  var h2 = 0x3c6ef372fe94f82b, h3 = 0xa54ff53a5f1d36f1;
  var h4 = 0x510e527fade682d1, h5 = 0x9b05688c2b3e6c1f;
  var h6 = 0x1f83d9abfb41bd6b, h7 = 0x5be0cd19137e2179;

  // Padding: message || 0x80 || zeros || 128-bit big-endian bit length.
  // Entitlement payloads are tiny; the high 64 length bits are always zero.
  final bytes = List<int>.of(data)..add(0x80);
  while (bytes.length % 128 != 112) {
    bytes.add(0);
  }
  final bitLen = data.length * 8;
  for (var i = 0; i < 8; i++) {
    bytes.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    bytes.add((bitLen >>> (8 * i)) & 0xff);
  }

  final w = List<int>.filled(80, 0);
  for (var off = 0; off < bytes.length; off += 128) {
    for (var t = 0; t < 16; t++) {
      var v = 0;
      for (var i = 0; i < 8; i++) {
        v = (v << 8) | bytes[off + t * 8 + i];
      }
      w[t] = v;
    }
    for (var t = 16; t < 80; t++) {
      final x = w[t - 15], y = w[t - 2];
      final s0 = _rotr64(x, 1) ^ _rotr64(x, 8) ^ (x >>> 7);
      final s1 = _rotr64(y, 19) ^ _rotr64(y, 61) ^ (y >>> 6);
      w[t] = w[t - 16] + s0 + w[t - 7] + s1; // wraps mod 2^64 on the VM
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, hh = h7;
    for (var t = 0; t < 80; t++) {
      final s1 = _rotr64(e, 14) ^ _rotr64(e, 18) ^ _rotr64(e, 41);
      final ch = (e & f) ^ (~e & g);
      final t1 = hh + s1 + ch + _sha512K[t] + w[t];
      final s0 = _rotr64(a, 28) ^ _rotr64(a, 34) ^ _rotr64(a, 39);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = s0 + maj;
      hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h0 += a; h1 += b; h2 += c; h3 += d; h4 += e; h5 += f; h6 += g; h7 += hh;
  }

  final out = List<int>.filled(64, 0);
  final hs = [h0, h1, h2, h3, h4, h5, h6, h7];
  for (var i = 0; i < 8; i++) {
    for (var j = 0; j < 8; j++) {
      out[i * 8 + j] = (hs[i] >>> (56 - 8 * j)) & 0xff;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Ed25519 (RFC 8032 Section 6 port). Field: GF(2^255 - 19), group order L.
// Points are extended homogeneous coordinates (X, Y, Z, T), x = X/Z,
// y = Y/Z, x*y = T/Z.
// ---------------------------------------------------------------------------

final BigInt _p = BigInt.two.pow(255) - BigInt.from(19);
final BigInt _l = BigInt.two.pow(252) +
    BigInt.parse('27742317777372353535851937790883648493');

BigInt _inv(BigInt x) => x.modPow(_p - BigInt.two, _p);

final BigInt _d = (-BigInt.from(121665) * _inv(BigInt.from(121666))) % _p;
final BigInt _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);

class _Point {
  _Point(this.x, this.y, this.z, this.t);
  BigInt x, y, z, t;
}

final _Point _identity = _Point(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);

/// Complete addition formula, RFC 8032 Section 5.1.4.
_Point _pointAdd(_Point P, _Point Q) {
  final A = (P.y - P.x) * (Q.y - Q.x) % _p;
  final B = (P.y + P.x) * (Q.y + Q.x) % _p;
  final C = BigInt.two * P.t * Q.t * _d % _p;
  final D = BigInt.two * P.z * Q.z % _p;
  final E = B - A, F = D - C, G = D + C, H = B + A;
  return _Point(E * F % _p, G * H % _p, F * G % _p, E * H % _p);
}

/// [s]P by plain double-and-add (verify is not a hot path; the reference
/// implementation does exactly this).
_Point _pointMul(BigInt s, _Point P) {
  var Q = _Point(_identity.x, _identity.y, _identity.z, _identity.t);
  var n = s;
  var addend = P;
  while (n > BigInt.zero) {
    if (!n.isEven) Q = _pointAdd(Q, addend);
    addend = _pointAdd(addend, addend);
    n = n >> 1;
  }
  return Q;
}

bool _pointEqual(_Point P, _Point Q) {
  if ((P.x * Q.z - Q.x * P.z) % _p != BigInt.zero) return false;
  if ((P.y * Q.z - Q.y * P.z) % _p != BigInt.zero) return false;
  return true;
}

/// Recover x from y per RFC 8032 Section 5.1.3, or null when no square root
/// exists (decoding fails).
BigInt? _recoverX(BigInt y, int sign) {
  if (y >= _p) return null;
  final x2 = (y * y - BigInt.one) * _inv(_d * y * y + BigInt.one) % _p;
  if (x2 == BigInt.zero) return sign == 0 ? BigInt.zero : null;
  var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if ((x * x - x2) % _p != BigInt.zero) x = x * _sqrtM1 % _p;
  if ((x * x - x2) % _p != BigInt.zero) return null;
  if ((x.isOdd ? 1 : 0) != sign) x = _p - x;
  return x;
}

final _Point _basePoint = () {
  final gy = BigInt.from(4) * _inv(BigInt.from(5)) % _p;
  final gx = _recoverX(gy, 0)!;
  return _Point(gx, gy, BigInt.one, gx * gy % _p);
}();

BigInt _leBytesToInt(List<int> bytes) {
  var v = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(bytes[i]);
  }
  return v;
}

List<int> _intToLeBytes(BigInt v, int length) {
  final out = List<int>.filled(length, 0);
  var n = v;
  for (var i = 0; i < length; i++) {
    out[i] = (n & BigInt.from(0xff)).toInt();
    n = n >> 8;
  }
  return out;
}

/// Point decompression per RFC 8032 Section 5.1.3; null on failure.
_Point? _pointDecompress(List<int> s) {
  if (s.length != 32) return null;
  var y = _leBytesToInt(s);
  final sign = (y >> 255).toInt();
  y = y & (BigInt.one << 255) - BigInt.one;
  final x = _recoverX(y, sign);
  if (x == null) return null;
  return _Point(x, y, BigInt.one, x * y % _p);
}

List<int> _pointCompress(_Point P) {
  final zinv = _inv(P.z);
  final x = P.x * zinv % _p;
  final y = P.y * zinv % _p;
  return _intToLeBytes(y | (BigInt.from(x.isOdd ? 1 : 0) << 255), 32);
}

BigInt _sha512ModL(List<int> data) => _leBytesToInt(sha512(data)) % _l;

/// Verifies an Ed25519 [signature] (64 bytes) on [message] under
/// [publicKey] (32 bytes), per RFC 8032 Section 5.1.7. PureEdDSA
/// (dom2 is empty), matching the RFC Section 7.1 test vectors.
///
/// Checks the equation [S]B == R + [k]A — the non-cofactored form,
/// which Section 5.1.7 states is sufficient. S >= L is rejected.
bool ed25519Verify(
    List<int> publicKey, List<int> message, List<int> signature) {
  if (publicKey.length != 32 || signature.length != 64) return false;
  final A = _pointDecompress(publicKey);
  if (A == null) return false;
  final rEnc = signature.sublist(0, 32);
  final R = _pointDecompress(rEnc);
  if (R == null) return false;
  final S = _leBytesToInt(signature.sublist(32, 64));
  if (S >= _l) return false;
  final k = _sha512ModL([...rEnc, ...publicKey, ...message]);
  final sB = _pointMul(S, _basePoint);
  final kA = _pointMul(k, A);
  return _pointEqual(sB, _pointAdd(R, kA));
}

/// Encoded point [scalar]B. Exposed for the test-only signing helper and
/// token-issuance tooling — the daemon itself never signs.
List<int> ed25519ScalarMultBase(BigInt scalar) =>
    _pointCompress(_pointMul(scalar % _l, _basePoint));
