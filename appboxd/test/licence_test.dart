// Acceptance bar for the licence slice: RFC 8032 Section 7.1 test vectors
// against lib/ed25519.dart, plus the licence lifecycle (round-trip, grace,
// expiry, tamper, wrong key, missing file) against lib/licence.dart.
//
// The signing helper here is TEST-ONLY (lib is verify-only by design).
// The dev keypair it uses matches the DEV public key embedded in
// lib/licence.dart — both are replaced together before the first paid
// release (see the comment on Licence.publicKey).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/ed25519.dart';
import 'package:appboxd/licence.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test-only Ed25519 keygen + sign (RFC 8032 §5.1.5/§5.1.6).
// ---------------------------------------------------------------------------

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
/// lib/licence.dart. Seed = first 32 bytes of
/// sha512('appbox licence DEV keypair v1 — replace before first release').
/// Never a production secret; replace with the real issuer keypair at launch.
final devKey = TestKey(_hex(
    '53d3edc57ad5ef51a42e5e8b19f0d9f3a1f527d7e2faea86a81e68352fee45e4'));

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];

String makeLicence(TestKey key, Map<String, Object?> payload) => jsonEncode({
      'payload': payload,
      'signature': base64Url.encode(key.sign(canonicalPayloadBytes(payload))),
    });

Map<String, Object?> annualPayload(String expires) => {
      'email': 'dev@example.com',
      'tier': 'annual',
      'issued': '2026-01-01T00:00:00.000Z',
      'expires': expires,
      'licence_id': 'abx_test_01',
    };

void main() {
  group('sha512 (FIPS 180-4 known answers)', () {
    test('empty message', () {
      expect(_hexOf(sha512([])),
          'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce'
          '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e');
    });
    test('"abc"', () {
      expect(_hexOf(sha512(utf8.encode('abc'))),
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
          '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
    });
  });

  group('ed25519 — RFC 8032 Section 7.1 test vectors', () {
    final vectors = [
      (
        pub: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        msg: '',
        sig: 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
            '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
      (
        pub: '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        msg: '72',
        sig: '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
            '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      ),
      (
        pub: 'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
        msg: 'af82',
        sig: '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac'
            '18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a',
      ),
    ];
    for (var i = 0; i < vectors.length; i++) {
      test('TEST ${i + 1} verifies', () {
        final v = vectors[i];
        expect(ed25519Verify(_hex(v.pub), _hex(v.msg), _hex(v.sig)), isTrue);
      });
    }
    test('bit-flipped signature rejected', () {
      final v = vectors[0];
      final sig = _hex(v.sig);
      sig[10] ^= 1;
      expect(ed25519Verify(_hex(v.pub), _hex(v.msg), sig), isFalse);
    });
    test('wrong message rejected', () {
      final v = vectors[1];
      expect(ed25519Verify(_hex(v.pub), _hex('73'), _hex(v.sig)), isFalse);
    });
  });

  group('licence', () {
    test('round-trip: signed annual licence verifies as valid', () {
      final file = makeLicence(devKey, annualPayload('2030-01-01T00:00:00.000Z'));
      final verdict = Licence.verify(utf8.encode(file),
          now: DateTime.utc(2029, 6, 1));
      expect(verdict.status, LicenceStatus.valid);
      expect(verdict.tier, 'annual');
      expect(verdict.email, 'dev@example.com');
      expect(verdict.expires, DateTime.utc(2030));
      expect(verdict.unlocks, isTrue);
    });

    test('expired annual is grace within 30 days', () {
      final file = makeLicence(devKey, annualPayload('2030-01-01T00:00:00.000Z'));
      final verdict = Licence.verify(utf8.encode(file),
          now: DateTime.utc(2030, 1, 15));
      expect(verdict.status, LicenceStatus.grace);
      expect(verdict.unlocks, isTrue);
    });

    test('past the 30-day grace the licence is expired (no unlock)', () {
      final file = makeLicence(devKey, annualPayload('2030-01-01T00:00:00.000Z'));
      final verdict = Licence.verify(utf8.encode(file),
          now: DateTime.utc(2030, 2, 15));
      expect(verdict.status, LicenceStatus.expired);
      expect(verdict.unlocks, isFalse);
      // Authentic but dead: tier/email are still reported, unlike invalid.
      expect(verdict.tier, 'annual');
    });

    test('tampered payload is invalid', () {
      final doc =
          jsonDecode(makeLicence(devKey, annualPayload('2030-01-01T00:00:00.000Z')))
              as Map<String, Object?>;
      (doc['payload'] as Map<String, Object?>)['email'] = 'pirate@example.com';
      final verdict = Licence.verify(utf8.encode(jsonEncode(doc)),
          now: DateTime.utc(2029, 6, 1));
      expect(verdict.status, LicenceStatus.invalid);
      expect(verdict.unlocks, isFalse);
    });

    test('signed by a wrong key is invalid', () {
      final wrongKey = TestKey(List<int>.filled(32, 7));
      final file = makeLicence(wrongKey, annualPayload('2030-01-01T00:00:00.000Z'));
      final verdict = Licence.verify(utf8.encode(file),
          now: DateTime.utc(2029, 6, 1));
      expect(verdict.status, LicenceStatus.invalid);
    });

    test('malformed file is invalid', () {
      expect(Licence.verify(utf8.encode('not json')).status,
          LicenceStatus.invalid);
      expect(Licence.verify(utf8.encode('{"payload":{}}')).status,
          LicenceStatus.invalid);
    });

    test('missing file is none', () {
      final verdict = Licence.verifyFile(
          'test/fixtures/definitely-no-licence-here.json');
      expect(verdict.status, LicenceStatus.none);
      expect(verdict.unlocks, isFalse);
    });

    test('whitespace/key-order churn in the file still verifies '
        '(canonical signing bytes)', () {
      final payload = annualPayload('2030-01-01T00:00:00.000Z');
      final sig =
          base64Url.encode(devKey.sign(canonicalPayloadBytes(payload)));
      // Same payload, keys in a different order, pretty-printed.
      final reordered = const JsonEncoder.withIndent('  ').convert({
        'signature': sig,
        'payload': {
          'licence_id': payload['licence_id'],
          'expires': payload['expires'],
          'issued': payload['issued'],
          'tier': payload['tier'],
          'email': payload['email'],
        },
      });
      final verdict = Licence.verify(utf8.encode(reordered),
          now: DateTime.utc(2029, 6, 1));
      expect(verdict.status, LicenceStatus.valid);
    });

    test('perpetual: valid forever, expires carried as updates_until', () {
      final payload = annualPayload('2020-01-01T00:00:00.000Z')
        ..['tier'] = 'perpetual';
      final file = makeLicence(devKey, payload);
      // Long past the update window: the app still works.
      final verdict = Licence.verify(utf8.encode(file),
          now: DateTime.utc(2026, 7, 30));
      expect(verdict.status, LicenceStatus.valid);
      expect(verdict.tier, 'perpetual');
      expect(verdict.unlocks, isTrue);
      expect(verdict.updatesUntil, DateTime.utc(2020));
      expect(verdict.expires, DateTime.utc(2020));
    });
  });

  group('licence_tool CLI contract', () {
    test('status prints paid JSON and exits 0 for a valid licence', () async {
      final tmp = await File(
              '${Directory.systemTemp.path}/licence_tool_test_${DateTime.now().microsecondsSinceEpoch}.json')
          .writeAsString(
              makeLicence(devKey, annualPayload('2030-01-01T00:00:00.000Z')));
      try {
        final res = await Process.run('dart',
            ['run', 'bin/licence_tool.dart', 'status', '--licence', tmp.path]);
        expect(res.exitCode, 0, reason: '${res.stderr}');
        final out = jsonDecode((res.stdout as String).trim());
        expect(out, {
          'status': 'paid',
          'tier': 'annual',
          'expires': '2030-01-01T00:00:00.000Z',
        });
      } finally {
        await tmp.delete();
      }
    });

    test('status prints none and exits 1 for a missing licence', () async {
      final res = await Process.run('dart', [
        'run',
        'bin/licence_tool.dart',
        'status',
        '--licence',
        'test/fixtures/definitely-no-licence-here.json',
      ]);
      expect(res.exitCode, 1, reason: '${res.stderr}');
      expect(jsonDecode((res.stdout as String).trim()),
          {'status': 'none', 'tier': null, 'expires': null});
    });
  });
}

String _hexOf(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
