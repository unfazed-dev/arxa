import 'dart:convert';
import 'dart:typed_data';

import 'package:appbox_studio/security/pairing/cert_pin.dart';
import 'package:appbox_studio/security/pairing/fingerprint.dart';
import 'package:appbox_studio/security/pairing/pairing_session.dart';
import 'package:appbox_studio/security/pairing/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Known SHA-256 vectors (NIST/RFC) — proves ofSpki IS sha256, not a circular
  // "hash then assert it equals itself".
  const sha256Empty =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  const sha256Abc =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  group('Fingerprint', () {
    test('ofSpki matches the SHA-256 of the SPKI DER (NIST vectors)', () {
      expect(Fingerprint.ofSpki(Uint8List(0)), sha256Empty);
      expect(Fingerprint.ofSpki(Uint8List.fromList(utf8.encode('abc'))), sha256Abc);
    });

    test('matches: identical fingerprints (constant-time path)', () {
      expect(Fingerprint.matches(sha256Abc, sha256Abc), isTrue);
    });

    test('grouped: colon-separated lowercase bytes for human display', () {
      expect(
        Fingerprint.grouped('abcd01'),
        'ab:cd:01',
      );
      expect(Fingerprint.grouped('AB:CD:01'), 'ab:cd:01');
    });

    // R5 NEGATIVE: a mismatched fingerprint must fail (the whole point of the pin).
    test('matches: a one-byte difference fails', () {
      final tampered = sha256Abc.replaceFirst('b', 'a'); // 2nd hex char flipped
      expect(Fingerprint.matches(sha256Abc, tampered), isFalse);
      expect(Fingerprint.matches(sha256Abc, sha256Empty), isFalse);
    });

    // R5 NEGATIVE: a different-length fingerprint fails (no short-circuit false-positive).
    test('matches: different lengths fail', () {
      expect(Fingerprint.matches(sha256Abc, 'ab'), isFalse);
    });
  });

  group('QrPayload', () {
    const payload = QrPayload(
      host: '192.168.1.42',
      port: 4321,
      nonce: 'aabbccdd',
      fingerprint: 'deadbeef',
    );

    test('encode → tryParse round-trips all four fields', () {
      final parsed = QrPayload.tryParse(payload.encode());
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.42');
      expect(parsed.port, 4321);
      expect(parsed.nonce, 'aabbccdd');
      expect(parsed.fingerprint, 'deadbeef');
    });

    // R5 NEGATIVE: a non-appbox QR is rejected at the scheme step, before JSON.
    test('tryParse: a foreign scheme is null', () {
      expect(QrPayload.tryParse('https://evil.example/pair'), isNull);
      expect(QrPayload.tryParse('not a qr'), isNull);
    });

    // R5 NEGATIVE: an unknown version is rejected (future/past shape).
    test('tryParse: wrong version is null', () {
      final body = base64Url.encode(utf8.encode(jsonEncode({
        'v': 99,
        'host': 'h',
        'port': 1,
        'n': 'x',
        'fp': 'y',
      }))).replaceAll('=', '');
      final bad = 'appbox-pair:$body';
      expect(QrPayload.tryParse(bad), isNull);
    });

    // R5 NEGATIVE: malformed base64 must not throw — it returns null (scanner
    // hands this attacker data; throwing would crash the scan flow).
    test('tryParse: malformed payload is null (never throws)', () {
      expect(QrPayload.tryParse('appbox-pair:!!!not-base64!!!'), isNull);
      expect(QrPayload.tryParse('appbox-pair:'), isNull);
    });

    // R5 NEGATIVE: bad port range / missing fields rejected.
    String qrWith({Object? port = 1, String? fp = 'fp', Object? host = 'h'}) {
      final json = jsonEncode({'v': 1, 'host': host, 'port': port, 'n': 'x', 'fp': fp});
      return 'appbox-pair:${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
    }

    test('tryParse: out-of-range port is null', () {
      expect(QrPayload.tryParse(qrWith(port: 70000)), isNull); // > 65535
    });

    test('tryParse: empty/missing fields are null', () {
      expect(QrPayload.tryParse(qrWith(fp: '')), isNull); // empty fp
      expect(QrPayload.tryParse(qrWith(host: '')), isNull); // empty host
    });
  });

  group('PairingSession', () {
    // A deterministic session: fixed clock + a nonce source that ticks 'n1','n2'…
    PairingSession makeSession({required DateTime start}) {
      var n = 0;
      return PairingSession(
        qrRotation: const Duration(seconds: 25),
        sessionIdleTimeout: const Duration(seconds: 60),
        now: () => start,
        nonceSource: () => 'n${++n}',
      );
    }

    test('consume: the current nonce creates a pending request', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      final req = s.consume('n1', 'Evan-iPhone', DateTime(2026, 1, 1, 0, 0, 5));
      expect(req, isNotNull);
      expect(req!.deviceName, 'Evan-iPhone');
    });

    test('confirm: moves a pending device to paired', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      final req = s.consume('n1', 'iPhone', DateTime(2026, 1, 1, 0, 0, 5))!;
      s.confirm(req.id);
      expect(s.pairedDevices.single.name, 'iPhone');
    });

    // R5 NEGATIVE: a replayed nonce (same QR scanned twice / relayed) is the
    // single-use defense — the SECOND consume must fail.
    test('consume: a replayed nonce is rejected (single-use)', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      final first = s.consume('n1', 'A', DateTime(2026, 1, 1, 0, 0, 5));
      expect(first, isNotNull);
      final replay = s.consume('n1', 'A', DateTime(2026, 1, 1, 0, 0, 6));
      expect(replay, isNull);
    });

    // R5 NEGATIVE: an expired nonce (after rotation) is rejected.
    test('consume: a stale nonce (post-rotation) is rejected', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      // advance past the 25s rotation window
      final at = DateTime(2026, 1, 1, 0, 0, 30);
      s.rotate(at); // n2
      // the OLD nonce (n1) is no longer current
      expect(s.consume('n1', 'A', at), isNull);
      // the NEW nonce (n2) is accepted
      expect(s.consume('n2', 'A', at), isNotNull);
    });

    test('isNonceStale: true past the rotation window', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      expect(s.isNonceStale(DateTime(2026, 1, 1, 0, 0, 10)), isFalse);
      expect(s.isNonceStale(DateTime(2026, 1, 1, 0, 0, 26)), isTrue);
    });

    test('revoke: drops a paired device', () {
      final s = makeSession(start: DateTime(2026, 1, 1, 0, 0, 0));
      final req = s.consume('n1', 'iPhone', DateTime(2026, 1, 1, 0, 0, 5))!;
      s.confirm(req.id);
      expect(s.pairedDevices, hasLength(1));
      expect(s.revoke(req.id), isTrue);
      expect(s.pairedDevices, isEmpty);
      expect(s.revoke(req.id), isFalse); // already gone — idempotent
    });

    test('sweepIdle: drops devices idle past the timeout, keeps active ones', () {
      var clock = DateTime(2026, 1, 1, 0, 0, 0);
      final s = PairingSession(
        qrRotation: const Duration(seconds: 25),
        sessionIdleTimeout: const Duration(seconds: 60),
        now: () => clock,
        nonceSource: () => 'n1',
      );
      final req = s.consume('n1', 'A', DateTime(2026, 1, 1, 0, 0, 5))!;
      s.confirm(req.id);
      // 30s later: still within the 60s idle window
      expect(s.sweepIdle(DateTime(2026, 1, 1, 0, 0, 35)), isEmpty);
      expect(s.pairedDevices, hasLength(1));
      // 61s later: past the idle window → dropped
      expect(s.sweepIdle(DateTime(2026, 1, 1, 0, 1, 6)), [req.id]);
      expect(s.pairedDevices, isEmpty);
    });
  });

  group('CertPin', () {
    // Pin = SHA-256 of the SPKI bytes "abc" (the NIST vector above). The
    // companion pins this from the QR; the live handshake presents the DER.
    final abcSpki = Uint8List.fromList(utf8.encode('abc'));
    final pin = CertPin(sha256Abc);

    test('validate: a presented cert whose SPKI matches the pin is accepted', () {
      expect(pin.validate(abcSpki).accepted, isTrue);
    });

    // R5 NEGATIVE: a relay/MITM presenting a different key → mismatch → reject.
    // This is the MITM defense; it MUST fail for the security model to hold.
    test('validate: a different key (MITM/relay) is rejected with both fps', () {
      final result =
          pin.validate(Uint8List.fromList(utf8.encode('attacker-key')));
      expect(result.accepted, isFalse);
      expect(result.isMismatch, isTrue);
      expect(result.pinned, sha256Abc);
      // the presented fp is sha256('attacker-key') — the UI can show the diff
      expect(result.presented, isNot(equals(sha256Abc)));
    });
  });
}
