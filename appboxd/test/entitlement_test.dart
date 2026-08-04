// Acceptance bar for the entitlement slice: RFC 8032 Section 7.1 test vectors
// against lib/ed25519.dart, plus the entitlement JWT lifecycle (round-trip,
// grace, expiry, tamper, wrong key, wrong machine, missing feature, nbf,
// missing file) against lib/entitlement.dart.
//
// The signing helper lives in entitlement_fixture.dart (TEST-ONLY — lib is
// verify-only by design). The dev keypair it uses matches the DEV public key
// embedded in lib/entitlement.dart — both are replaced together before the
// first paid release (see the comment on Entitlement.publicKey).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/ed25519.dart';
import 'package:appboxd/entitlement.dart';
import 'package:test/test.dart';

import 'entitlement_fixture.dart';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// A token bound to [testFingerprint], valid across [nbf]..[exp].
String tokenFor({DateTime? nbf, DateTime? exp, List<String>? feat}) =>
    makeEntitlementJwt(
        devEntitlementKey,
        entitlementClaims(
          fpr: testFingerprint,
          nbf: _epoch(nbf ?? DateTime.utc(2026)),
          exp: _epoch(exp ?? DateTime.utc(2030)),
          feat: feat ?? const ['emit.scaffold'],
        ));

EntitlementVerdict verifyAt(String token, DateTime now) =>
    Entitlement.verify(token, now: now, fingerprint: testFingerprint);

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

  group('entitlement', () {
    test('round-trip: signed token verifies as valid', () {
      final verdict = verifyAt(tokenFor(), DateTime.utc(2029, 6, 1));
      expect(verdict.status, EntitlementStatus.valid);
      expect(verdict.subject, 'user_dev_01');
      expect(verdict.features, ['emit.scaffold']);
      expect(verdict.expires, DateTime.utc(2030));
      expect(verdict.unlocks, isTrue);
    });

    test('expired token is grace within 30 days (offline continuation)', () {
      final verdict = verifyAt(tokenFor(), DateTime.utc(2030, 1, 15));
      expect(verdict.status, EntitlementStatus.grace);
      expect(verdict.unlocks, isTrue);
    });

    test('past the 30-day grace the token is expired (no unlock)', () {
      final verdict = verifyAt(tokenFor(), DateTime.utc(2030, 2, 15));
      expect(verdict.status, EntitlementStatus.expired);
      expect(verdict.unlocks, isFalse);
      // Authentic but dead: subject is still reported, unlike invalid.
      expect(verdict.subject, 'user_dev_01');
    });

    test('tampered claims are invalid', () {
      final doc = tokenFor().split('.');
      final claims = entitlementClaims(
          fpr: testFingerprint,
          nbf: _epoch(DateTime.utc(2026)),
          exp: _epoch(DateTime.utc(2030)))
        ..['sub'] = 'pirate@example.com';
      final tampered =
          '${doc[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.${doc[2]}';
      final verdict = verifyAt(tampered, DateTime.utc(2029, 6, 1));
      expect(verdict.status, EntitlementStatus.invalid);
      expect(verdict.unlocks, isFalse);
    });

    test('signed by a wrong key is invalid', () {
      final wrongKey = TestKey(List<int>.filled(32, 7));
      final token = makeEntitlementJwt(
          wrongKey,
          entitlementClaims(
              fpr: testFingerprint,
              nbf: _epoch(DateTime.utc(2026)),
              exp: _epoch(DateTime.utc(2030))));
      expect(verifyAt(token, DateTime.utc(2029, 6, 1)).status,
          EntitlementStatus.invalid);
    });

    test('malformed tokens are invalid', () {
      expect(verifyAt('not-a-jwt', DateTime.utc(2029)).status,
          EntitlementStatus.invalid);
      expect(verifyAt('a.b', DateTime.utc(2029)).status,
          EntitlementStatus.invalid);
      expect(
          verifyAt('${base64Url.encode(utf8.encode('{"alg":"EdDSA"}'))}.@@!!.x',
                  DateTime.utc(2029))
              .status,
          EntitlementStatus.invalid);
    });

    test('alg other than EdDSA is invalid (algorithm confusion)', () {
      final token = makeEntitlementJwt(
          devEntitlementKey,
          entitlementClaims(
              fpr: testFingerprint,
              nbf: _epoch(DateTime.utc(2026)),
              exp: _epoch(DateTime.utc(2030))),
          header: const {'alg': 'none', 'typ': 'JWT'});
      expect(verifyAt(token, DateTime.utc(2029, 6, 1)).status,
          EntitlementStatus.invalid);
    });

    test('missing the emit.scaffold feature is invalid', () {
      final verdict = verifyAt(
          tokenFor(feat: const ['emit.htmx']), DateTime.utc(2029, 6, 1));
      expect(verdict.status, EntitlementStatus.invalid);
      expect(verdict.reason, contains('emit.scaffold'));
      expect(verdict.unlocks, isFalse);
    });

    test('nbf in the future is invalid', () {
      final verdict = verifyAt(
          tokenFor(nbf: DateTime.utc(2031), exp: DateTime.utc(2032)),
          DateTime.utc(2029, 6, 1));
      expect(verdict.status, EntitlementStatus.invalid);
      expect(verdict.reason, contains('nbf'));
      expect(verdict.unlocks, isFalse);
    });

    test('bound to a different machine is invalid (fingerprint mismatch)', () {
      final verdict = Entitlement.verify(tokenFor(),
          now: DateTime.utc(2029, 6, 1),
          fingerprint:
              '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff');
      expect(verdict.status, EntitlementStatus.invalid);
      expect(verdict.reason, contains('different machine'));
      expect(verdict.unlocks, isFalse);
    });

    test('malformed claims (exp as string, bad fpr) are invalid', () {
      String withClaims(Map<String, Object?> claims) =>
          makeEntitlementJwt(devEntitlementKey, claims);
      final base = entitlementClaims(
          fpr: testFingerprint,
          nbf: _epoch(DateTime.utc(2026)),
          exp: _epoch(DateTime.utc(2030)));
      expect(
          verifyAt(withClaims({...base, 'exp': '2030-01-01'}),
                  DateTime.utc(2029, 6, 1))
              .status,
          EntitlementStatus.invalid);
      expect(
          verifyAt(withClaims({...base, 'fpr': 'not-hex'}),
                  DateTime.utc(2029, 6, 1))
              .status,
          EntitlementStatus.invalid);
    });

    test('missing file is none', () {
      final verdict = Entitlement.verifyFile(
          'test/fixtures/definitely-no-entitlement-here.jwt');
      expect(verdict.status, EntitlementStatus.none);
      expect(verdict.unlocks, isFalse);
    });

    test('machine fingerprint is a 64-char sha256 hex on this platform', () {
      final fpr = localFingerprint();
      expect(fpr, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('entitlement CLI contract', () {
    test('status prints entitled JSON and exits 0 for a valid token', () async {
      final token = makeEntitlementJwt(
          devEntitlementKey,
          entitlementClaims(
            fpr: localFingerprint(),
            nbf: _epoch(DateTime.now().subtract(const Duration(days: 1))),
            exp: _epoch(DateTime.now().add(const Duration(days: 7))),
          ));
      final tmp = await File(
              '${Directory.systemTemp.path}/entitlement_cli_test_${DateTime.now().microsecondsSinceEpoch}.jwt')
          .writeAsString(token);
      try {
        final res = await Process.run('dart',
            ['run', 'bin/appbox.dart', 'entitlement', 'status', '--token', tmp.path]);
        expect(res.exitCode, 0, reason: '${res.stderr}');
        final out = jsonDecode((res.stdout as String).trim());
        expect(out['status'], 'entitled');
        expect(out['features'], ['emit.scaffold']);
      } finally {
        await tmp.delete();
      }
    });

    test('status prints none and exits 1 for a missing token', () async {
      final res = await Process.run('dart', [
        'run',
        'bin/appbox.dart',
        'entitlement',
        'status',
        '--token',
        'test/fixtures/definitely-no-entitlement-here.jwt',
      ]);
      expect(res.exitCode, 1, reason: '${res.stderr}');
      expect(jsonDecode((res.stdout as String).trim())['status'], 'none');
    });

    test('verify reports the raw verdict and exits 1 for a wrong-machine token',
        () async {
      final token = tokenFor(); // bound to testFingerprint, not this machine
      final tmp = await File(
              '${Directory.systemTemp.path}/entitlement_cli_test_${DateTime.now().microsecondsSinceEpoch}.jwt')
          .writeAsString(token);
      try {
        final res = await Process.run('dart',
            ['run', 'bin/appbox.dart', 'entitlement', 'verify', tmp.path]);
        expect(res.exitCode, 1, reason: '${res.stderr}');
        final out = jsonDecode((res.stdout as String).trim());
        expect(out['status'], 'invalid');
        expect(out['reason'], contains('different machine'));
      } finally {
        await tmp.delete();
      }
    });
  });

  group('scaffold boundary (D17, fail-closed)', () {
    test('emit scaffold halts before any write without an entitlement',
        () async {
      final home = await Directory.systemTemp
          .createTemp('entitlement_scaffold_test_');
      try {
        final res = await Process.run(
          'dart',
          ['run', 'bin/appbox.dart', 'emit', 'scaffold', '--targets', 'macos'],
          environment: {'HOME': home.path},
        );
        expect(res.exitCode, 1, reason: '${res.stderr}');
        expect(res.stderr as String, contains('PRECONDITION NOT MET'));
        expect(res.stderr as String, contains('no entitlement token'));
      } finally {
        await home.delete(recursive: true);
      }
    });

    test('emit scaffold --self-test stays free (diagnostic, no app writes)',
        () async {
      final home = await Directory.systemTemp
          .createTemp('entitlement_scaffold_test_');
      try {
        final res = await Process.run(
          'dart',
          ['run', 'bin/appbox.dart', 'emit', 'scaffold', '--self-test'],
          environment: {'HOME': home.path},
        );
        expect(res.exitCode, 0, reason: '${res.stderr}');
      } finally {
        await home.delete(recursive: true);
      }
    });
  });
}

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];

String _hexOf(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
