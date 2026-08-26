/// Pure-Dart cryptographic primitives for arxa's encryption-at-rest
/// (plan P1: vault material, entitlement file, memory/analytics store).
///
/// `dart:core`/`dart:typed_data`/`dart:math` only — no third-party crypto,
/// matching the daemon's zero-dependency constraint (arxa/README.md).
///
/// Implemented and verified against official test vectors:
/// - SHA-256 (FIPS 180-4 examples) and HMAC-SHA256 (RFC 4231).
/// - PBKDF2-HMAC-SHA256 (RFC 7914 vectors), [pbkdf2Iterations] default.
/// - ChaCha20 block + ChaCha20-Poly1305 AEAD (RFC 8439 §2.3.2, §2.4.2,
///   §2.5.2, §2.8.2).
/// - XChaCha20-Poly1305 via HChaCha20 (draft-irtf-cfrg-xchacha-03 §A.1/A.3.1).
///
/// Nonce discipline: [sealXChaCha20Poly1305] takes a caller-supplied 24-byte
/// nonce; use [randomBytes] (Random.secure) so collisions are cryptographically
/// negligible. A nonce MUST never repeat under the same key — per-file keys or
/// key rotation on rewrite are the caller's job (SecureStore rotates by
/// re-reading the vault; a leaked/reused nonce breaks confidentiality only for
/// messages under that nonce).
library;

import 'dart:math';
import 'dart:typed_data';

/// Thrown when an AEAD tag (or store magic) fails verification — tampered
/// ciphertext, wrong key, or truncated file.
class AuthenticationException implements Exception {
  AuthenticationException(this.message);
  final String message;
  @override
  String toString() => 'AuthenticationException: $message';
}

const int _mask32 = 0xffffffff;

/// Cryptographically secure random bytes (Random.secure → OS CSPRNG).
Uint8List randomBytes(int length) {
  final rng = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

/// Constant-time equality for tags/keys. Length mismatch is not secret
/// (tag length is fixed by construction), so it short-circuits.
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// ---------------------------------------------------------------------------
// SHA-256 (FIPS 180-4)
// ---------------------------------------------------------------------------

const _k256 = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr32(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask32;

/// SHA-256 digest of [data].
Uint8List sha256(Uint8List data) {
  final h = Uint32List.fromList(const [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ]);

  // Padding: data || 0x80 || zeros || 64-bit big-endian bit length.
  final bitLen = data.length * 8;
  final paddedLen = ((data.length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLen)
    ..setRange(0, data.length, data)
    ..[data.length] = 0x80;
  final bd = ByteData.view(padded.buffer);
  bd.setUint32(paddedLen - 8, (bitLen >> 32) & _mask32);
  bd.setUint32(paddedLen - 4, bitLen & _mask32);

  final w = Uint32List(64);
  for (var off = 0; off < paddedLen; off += 64) {
    for (var t = 0; t < 16; t++) {
      w[t] = bd.getUint32(off + t * 4);
    }
    for (var t = 16; t < 64; t++) {
      final w2 = w[t - 2], w15 = w[t - 15];
      final s1 = _rotr32(w2, 17) ^ _rotr32(w2, 19) ^ (w2 >> 10);
      final s0 = _rotr32(w15, 7) ^ _rotr32(w15, 18) ^ (w15 >> 3);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask32;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var t = 0; t < 64; t++) {
      final bs1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final ch = (e & f) ^ (~e & g & _mask32);
      final t1 = (hh + bs1 + ch + _k256[t] + w[t]) & _mask32;
      final bs0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (bs0 + maj) & _mask32;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask32;
    }
    h[0] = (h[0] + a) & _mask32;
    h[1] = (h[1] + b) & _mask32;
    h[2] = (h[2] + c) & _mask32;
    h[3] = (h[3] + d) & _mask32;
    h[4] = (h[4] + e) & _mask32;
    h[5] = (h[5] + f) & _mask32;
    h[6] = (h[6] + g) & _mask32;
    h[7] = (h[7] + hh) & _mask32;
  }

  final out = Uint8List(32);
  final obd = ByteData.view(out.buffer);
  for (var i = 0; i < 8; i++) {
    obd.setUint32(i * 4, h[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// HMAC-SHA256 (RFC 2104) and PBKDF2-HMAC-SHA256 (RFC 8018)
// ---------------------------------------------------------------------------

/// HMAC-SHA256 of [message] under [key] (any key length).
Uint8List hmacSha256(Uint8List key, Uint8List message) {
  final k = key.length > 64 ? sha256(key) : key;
  final inner = Uint8List(64 + message.length);
  final outer = Uint8List(64 + 32);
  for (var i = 0; i < 64; i++) {
    final kb = i < k.length ? k[i] : 0;
    inner[i] = kb ^ 0x36;
    outer[i] = kb ^ 0x5c;
  }
  inner.setRange(64, inner.length, message);
  outer.setRange(64, outer.length, sha256(inner));
  return sha256(outer);
}

/// Default PBKDF2 iteration count (≥100k per the hard-band requirement).
const int pbkdf2Iterations = 100000;

/// PBKDF2-HMAC-SHA256 (RFC 8018 §5.2). [dkLen] in bytes.
Uint8List pbkdf2HmacSha256(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int dkLen,
) {
  final blockCount = (dkLen + 31) ~/ 32;
  final out = Uint8List(blockCount * 32);
  final blockIndex = Uint8List(4);
  final ibd = ByteData.view(blockIndex.buffer);
  for (var block = 1; block <= blockCount; block++) {
    ibd.setUint32(0, block);
    var u = hmacSha256(password, Uint8List.fromList([...salt, ...blockIndex]));
    final t = Uint8List.fromList(u);
    for (var c = 1; c < iterations; c++) {
      u = hmacSha256(password, u);
      for (var j = 0; j < 32; j++) {
        t[j] ^= u[j];
      }
    }
    out.setRange((block - 1) * 32, block * 32, t);
  }
  return Uint8List.sublistView(out, 0, dkLen);
}

// ---------------------------------------------------------------------------
// ChaCha20 (RFC 8439 §2.3) and HChaCha20 (draft-irtf-cfrg-xchacha)
// ---------------------------------------------------------------------------

int _le32(Uint8List b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

void _quarterRound(Uint32List s, int a, int b, int c, int d) {
  s[a] = (s[a] + s[b]) & _mask32;
  s[d] ^= s[a];
  s[d] = ((s[d] << 16) | (s[d] >> 16)) & _mask32;
  s[c] = (s[c] + s[d]) & _mask32;
  s[b] ^= s[c];
  s[b] = ((s[b] << 12) | (s[b] >> 20)) & _mask32;
  s[a] = (s[a] + s[b]) & _mask32;
  s[d] ^= s[a];
  s[d] = ((s[d] << 8) | (s[d] >> 24)) & _mask32;
  s[c] = (s[c] + s[d]) & _mask32;
  s[b] ^= s[c];
  s[b] = ((s[b] << 7) | (s[b] >> 25)) & _mask32;
}

void _doubleRounds(Uint32List s) {
  for (var i = 0; i < 10; i++) {
    _quarterRound(s, 0, 4, 8, 12);
    _quarterRound(s, 1, 5, 9, 13);
    _quarterRound(s, 2, 6, 10, 14);
    _quarterRound(s, 3, 7, 11, 15);
    _quarterRound(s, 0, 5, 10, 15);
    _quarterRound(s, 1, 6, 11, 12);
    _quarterRound(s, 2, 7, 8, 13);
    _quarterRound(s, 3, 4, 9, 14);
  }
}

/// Raw 64-byte ChaCha20 block (RFC 8439 §2.3.2): 32-byte [key], 12-byte
/// [nonce], 32-bit [counter]. Exposed for vector tests.
Uint8List chacha20Block(Uint8List key, int counter, Uint8List nonce) {
  final state = Uint32List(16)
    ..[0] = 0x61707865
    ..[1] = 0x3320646e
    ..[2] = 0x79622d32
    ..[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = _le32(key, i * 4);
  }
  state[12] = counter;
  for (var i = 0; i < 3; i++) {
    state[13 + i] = _le32(nonce, i * 4);
  }
  final working = Uint32List.fromList(state);
  _doubleRounds(working);
  final out = Uint8List(64);
  final obd = ByteData.view(out.buffer);
  for (var i = 0; i < 16; i++) {
    obd.setUint32(i * 4, (working[i] + state[i]) & _mask32, Endian.little);
  }
  return out;
}

/// HChaCha20 (draft-irtf-cfrg-xchacha-03 §2.2): 32-byte [key], 16-byte
/// [nonce16] → 32-byte subkey. Exposed for vector tests.
Uint8List hchacha20(Uint8List key, Uint8List nonce16) {
  final state = Uint32List(16)
    ..[0] = 0x61707865
    ..[1] = 0x3320646e
    ..[2] = 0x79622d32
    ..[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = _le32(key, i * 4);
  }
  for (var i = 0; i < 4; i++) {
    state[12 + i] = _le32(nonce16, i * 4);
  }
  _doubleRounds(state); // no feed-forward addition in HChaCha20
  final out = Uint8List(32);
  final obd = ByteData.view(out.buffer);
  const words = [0, 1, 2, 3, 12, 13, 14, 15];
  for (var i = 0; i < 8; i++) {
    obd.setUint32(i * 4, state[words[i]], Endian.little);
  }
  return out;
}

Uint8List _chacha20Xor(Uint8List key, int initialCounter, Uint8List nonce12,
    Uint8List input) {
  final out = Uint8List(input.length);
  var counter = initialCounter;
  for (var off = 0; off < input.length; off += 64) {
    final stream = chacha20Block(key, counter, nonce12);
    counter = (counter + 1) & _mask32;
    final n = input.length - off < 64 ? input.length - off : 64;
    for (var i = 0; i < n; i++) {
      out[off + i] = input[off + i] ^ stream[i];
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Poly1305 (RFC 8439 §2.5) — poly1305-donna 26-bit-limb arithmetic on
// Dart's 64-bit ints; intermediate products stay below 2^56.
// ---------------------------------------------------------------------------

/// Poly1305 one-time authenticator over [msg] with 32-byte one-time [key].
Uint8List poly1305Mac(Uint8List msg, Uint8List key) {
  const m26 = 0x3ffffff;
  final t0 = _le32(key, 0), t1 = _le32(key, 4);
  final t2 = _le32(key, 8), t3 = _le32(key, 12);
  final r0 = t0 & m26;
  final r1 = ((t0 >> 26) | (t1 << 6)) & 0x3ffff03;
  final r2 = ((t1 >> 20) | (t2 << 12)) & 0x3ffc0ff;
  final r3 = ((t2 >> 14) | (t3 << 18)) & 0x3f03fff;
  final r4 = (t3 >> 8) & 0x00fffff;
  final s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5;

  var h0 = 0, h1 = 0, h2 = 0, h3 = 0, h4 = 0;
  var off = 0;
  while (off < msg.length) {
    final n = msg.length - off < 16 ? msg.length - off : 16;
    final block = Uint8List(16)..setRange(0, n, msg, off);
    if (n < 16) block[n] = 1; // 0x01 pad byte; full blocks carry hibit below
    final b0 = _le32(block, 0), b1 = _le32(block, 4);
    final b2 = _le32(block, 8), b3 = _le32(block, 12);
    h0 += b0 & m26;
    h1 += ((b0 >> 26) | (b1 << 6)) & m26;
    h2 += ((b1 >> 20) | (b2 << 12)) & m26;
    h3 += ((b2 >> 14) | (b3 << 18)) & m26;
    h4 += (b3 >> 8) | (n == 16 ? 1 << 24 : 0);

    var d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1;
    var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2;
    var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3;
    var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4;
    var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0;

    var c = d0 >> 26;
    h0 = d0 & m26;
    d1 += c;
    c = d1 >> 26;
    h1 = d1 & m26;
    d2 += c;
    c = d2 >> 26;
    h2 = d2 & m26;
    d3 += c;
    c = d3 >> 26;
    h3 = d3 & m26;
    d4 += c;
    c = d4 >> 26;
    h4 = d4 & m26;
    h0 += c * 5;
    c = h0 >> 26;
    h0 &= m26;
    h1 += c;
    off += n;
  }

  // Full carry chain, then conditional subtraction of p = 2^130 - 5.
  var c = h1 >> 26;
  h1 &= m26;
  h2 += c;
  c = h2 >> 26;
  h2 &= m26;
  h3 += c;
  c = h3 >> 26;
  h3 &= m26;
  h4 += c;
  c = h4 >> 26;
  h4 &= m26;
  h0 += c * 5;
  c = h0 >> 26;
  h0 &= m26;
  h1 += c;

  final g0 = h0 + 5;
  c = g0 >> 26;
  var g = g0 & m26;
  final g1 = h1 + c;
  c = g1 >> 26;
  final g1m = g1 & m26;
  final g2 = h2 + c;
  c = g2 >> 26;
  final g2m = g2 & m26;
  final g3 = h3 + c;
  c = g3 >> 26;
  final g3m = g3 & m26;
  final g4 = h4 + c - (1 << 26);
  if (g4 >= 0) {
    // h >= p: keep h - p.
    h0 = g;
    h1 = g1m;
    h2 = g2m;
    h3 = g3m;
    h4 = g4;
  }

  // Pack limbs into 32-bit words and add s (second half of the key).
  final w0 = (h0 | (h1 << 26)) & _mask32;
  final w1 = ((h1 >> 6) | (h2 << 20)) & _mask32;
  final w2 = ((h2 >> 12) | (h3 << 14)) & _mask32;
  final w3 = ((h3 >> 18) | (h4 << 8)) & _mask32;
  var f = w0 + _le32(key, 16);
  final o0 = f & _mask32;
  f = w1 + _le32(key, 20) + (f >> 32);
  final o1 = f & _mask32;
  f = w2 + _le32(key, 24) + (f >> 32);
  final o2 = f & _mask32;
  f = w3 + _le32(key, 28) + (f >> 32);
  final o3 = f & _mask32;

  final out = Uint8List(16);
  final obd = ByteData.view(out.buffer);
  obd.setUint32(0, o0, Endian.little);
  obd.setUint32(4, o1, Endian.little);
  obd.setUint32(8, o2, Endian.little);
  obd.setUint32(12, o3, Endian.little);
  return out;
}

// ---------------------------------------------------------------------------
// ChaCha20-Poly1305 AEAD (RFC 8439 §2.8) and XChaCha20-Poly1305
// (draft-irtf-cfrg-xchacha-03 §2.3). seal returns ciphertext‖tag; open
// verifies the tag in constant time before releasing plaintext.
// ---------------------------------------------------------------------------

const int aeadTagSize = 16;
const int xchachaNonceSize = 24;

Uint8List _macData(Uint8List aad, Uint8List ciphertext) {
  final lenBlock = Uint8List(16);
  final lbd = ByteData.view(lenBlock.buffer);
  lbd.setUint32(0, aad.length & _mask32, Endian.little);
  lbd.setUint32(4, aad.length ~/ 0x100000000, Endian.little);
  lbd.setUint32(8, ciphertext.length & _mask32, Endian.little);
  lbd.setUint32(12, ciphertext.length ~/ 0x100000000, Endian.little);
  Uint8List pad16(int n) => Uint8List(n % 16 == 0 ? 0 : 16 - (n % 16));
  return Uint8List.fromList(
      [...aad, ...pad16(aad.length), ...ciphertext, ...pad16(ciphertext.length), ...lenBlock]);
}

Uint8List _aeadSeal(Uint8List key, Uint8List nonce12, Uint8List plaintext,
    Uint8List aad) {
  final polyKey = Uint8List.sublistView(chacha20Block(key, 0, nonce12), 0, 32);
  final ciphertext = _chacha20Xor(key, 1, nonce12, plaintext);
  final tag = poly1305Mac(_macData(aad, ciphertext), polyKey);
  return Uint8List.fromList([...ciphertext, ...tag]);
}

Uint8List _aeadOpen(Uint8List key, Uint8List nonce12,
    Uint8List ciphertextAndTag, Uint8List aad) {
  if (ciphertextAndTag.length < aeadTagSize) {
    throw AuthenticationException('ciphertext shorter than tag');
  }
  final ct = Uint8List.sublistView(
      ciphertextAndTag, 0, ciphertextAndTag.length - aeadTagSize);
  final tag = Uint8List.sublistView(
      ciphertextAndTag, ciphertextAndTag.length - aeadTagSize);
  final polyKey = Uint8List.sublistView(chacha20Block(key, 0, nonce12), 0, 32);
  final expected = poly1305Mac(_macData(aad, ct), polyKey);
  if (!constantTimeEquals(tag, expected)) {
    throw AuthenticationException('tag mismatch');
  }
  return _chacha20Xor(key, 1, nonce12, ct);
}

/// ChaCha20-Poly1305 seal: 32-byte [key], 12-byte [nonce12].
/// Returns ciphertext‖16-byte tag.
Uint8List sealChaCha20Poly1305(
        Uint8List key, Uint8List nonce12, Uint8List plaintext,
        [Uint8List? aad]) =>
    _aeadSeal(key, nonce12, plaintext, aad ?? Uint8List(0));

/// ChaCha20-Poly1305 open. Throws [AuthenticationException] on tamper or
/// wrong key — plaintext is never released unauthenticated.
Uint8List openChaCha20Poly1305(
        Uint8List key, Uint8List nonce12, Uint8List ciphertextAndTag,
        [Uint8List? aad]) =>
    _aeadOpen(key, nonce12, ciphertextAndTag, aad ?? Uint8List(0));

Uint8List _xchachaParts(Uint8List key, Uint8List nonce24) {
  if (nonce24.length != xchachaNonceSize) {
    throw ArgumentError('XChaCha20 nonce must be 24 bytes');
  }
  final subkey = hchacha20(key, Uint8List.sublistView(nonce24, 0, 16));
  final nonce12 = Uint8List(12)..setRange(4, 12, nonce24, 16);
  return Uint8List.fromList([...subkey, ...nonce12]);
}

/// XChaCha20-Poly1305 seal: 32-byte [key], 24-byte [nonce24] from
/// [randomBytes]. Never reuse (key, nonce) — 192 random bits makes accidental
/// reuse negligible; deliberate key rotation per file is the caller's duty.
Uint8List sealXChaCha20Poly1305(
    Uint8List key, Uint8List nonce24, Uint8List plaintext,
    [Uint8List? aad]) {
  final parts = _xchachaParts(key, nonce24);
  return _aeadSeal(Uint8List.sublistView(parts, 0, 32),
      Uint8List.sublistView(parts, 32, 44), plaintext, aad ?? Uint8List(0));
}

/// XChaCha20-Poly1305 open; throws [AuthenticationException] on tamper.
Uint8List openXChaCha20Poly1305(
    Uint8List key, Uint8List nonce24, Uint8List ciphertextAndTag,
    [Uint8List? aad]) {
  final parts = _xchachaParts(key, nonce24);
  return _aeadOpen(Uint8List.sublistView(parts, 0, 32),
      Uint8List.sublistView(parts, 32, 44), ciphertextAndTag, aad ?? Uint8List(0));
}

// ---------------------------------------------------------------------------
// hex helpers (vault stores the data key as a String)
// ---------------------------------------------------------------------------

/// Lowercase hex encoding.
String hexEncode(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Decodes lowercase/uppercase hex; throws on malformed input.
Uint8List hexDecode(String hex) {
  if (hex.length % 2 != 0) throw ArgumentError('odd-length hex');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) throw ArgumentError('bad hex at byte $i');
    out[i] = v;
  }
  return out;
}
