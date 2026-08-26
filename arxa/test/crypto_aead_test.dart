import 'dart:typed_data';

import 'package:arxa/crypto_aead.dart';
import 'package:test/test.dart';

Uint8List hx(String s) => hexDecode(s);
Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);
Uint8List fill(int n, int v) => Uint8List(n)..fillRange(0, n, v);
Uint8List seq(int n) => Uint8List.fromList(List.generate(n, (i) => i));

void main() {
  group('SHA-256 (FIPS 180-4 examples)', () {
    test('empty string', () {
      expect(
          hexEncode(sha256(Uint8List(0))),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
    test('"abc"', () {
      expect(
          hexEncode(sha256(ascii('abc'))),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
    test('56-byte multi-block message', () {
      expect(
          hexEncode(sha256(ascii(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });
  });

  group('HMAC-SHA256 (RFC 4231)', () {
    test('case 1: 20x 0x0b key, "Hi There"', () {
      expect(hexEncode(hmacSha256(fill(20, 0x0b), ascii('Hi There'))),
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
    });
    test('case 2: "Jefe"', () {
      expect(
          hexEncode(hmacSha256(
              ascii('Jefe'), ascii('what do ya want for nothing?'))),
          '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
    });
    test('case 3: 20x 0xaa key, 50x 0xdd data', () {
      expect(hexEncode(hmacSha256(fill(20, 0xaa), fill(50, 0xdd))),
          '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe');
    });
    test('case 6: 131-byte key (hashed first)', () {
      expect(
          hexEncode(hmacSha256(fill(131, 0xaa),
              ascii('Test Using Larger Than Block-Size Key - Hash Key First'))),
          '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');
    });
    test('case 7: 131-byte key, larger data', () {
      // Note: RFC 4231's printed value for case 7 carries a one-nibble typo
      // (errata); this is the value OpenSSL computes.
      expect(
          hexEncode(hmacSha256(
              fill(131, 0xaa),
              ascii('This is a test using a larger than block-size key and a '
                  'larger than block-size data. The key needs to be hashed '
                  'before being used by the HMAC algorithm.'))),
          '9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2');
    });
  });

  group('PBKDF2-HMAC-SHA256 (RFC 7914)', () {
    test('c=1, dkLen=64', () {
      expect(hexEncode(pbkdf2HmacSha256(ascii('password'), ascii('salt'), 1, 64)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'
          '4dbf3a2f3dad3377264bb7b8e8330d4efc7451418617dabef683735361cdc18c');
    });
    test('c=2, dkLen=64', () {
      expect(hexEncode(pbkdf2HmacSha256(ascii('password'), ascii('salt'), 2, 64)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'
          '830651afcb5c862f0b249bd031f7a67520d136470f5ec271ece91c07773253d9');
    });
    test('c=4096, dkLen=40 (spans a block boundary)', () {
      expect(
          hexEncode(pbkdf2HmacSha256(ascii('password'), ascii('salt'), 4096, 40)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a'
          'f7ad98c1b458ce3f');
    });
    test('default iteration count is at least 100k', () {
      expect(pbkdf2Iterations, greaterThanOrEqualTo(100000));
    });
  });

  group('ChaCha20 (RFC 8439)', () {
    test('§2.3.2 block function', () {
      expect(
          hexEncode(chacha20Block(seq(32), 1, hx('000000090000004a00000000'))),
          '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e'
          'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e');
    });

    test('§2.5.2 Poly1305 one-time auth', () {
      expect(
          hexEncode(poly1305Mac(
              ascii('Cryptographic Forum Research Group'),
              hx('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b'))),
          'a8061dc1305136c6c22b8baf0c0127a9');
    });

    test('§2.8.2 AEAD seal vector', () {
      final key = hx(
          '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
      final nonce = hx('070000004041424344454647');
      final aad = hx('50515253c0c1c2c3c4c5c6c7');
      final pt = ascii("Ladies and Gentlemen of the class of '99: If I could "
          'offer you only one tip for the future, sunscreen would be it.');
      expect(
          hexEncode(sealChaCha20Poly1305(key, nonce, pt, aad)),
          'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6'
          '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36'
          '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc'
          '3ff4def08e4b7a9de576d26586cec64b6116'
          '1ae10b594f09e26a7e902ecbd0600691');
    });
  });

  group('XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha-03)', () {
    final key = hx(
        '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
    final aad = hx('50515253c0c1c2c3c4c5c6c7');
    final pt = ascii("Ladies and Gentlemen of the class of '99: If I could "
        'offer you only one tip for the future, sunscreen would be it.');

    test('§A.1 HChaCha20 vector', () {
      expect(
          hexEncode(hchacha20(seq(32), hx('000000090000004a0000000031415927'))),
          '82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc');
    });

    test('§A.3.1 AEAD seal vector', () {
      expect(
          hexEncode(sealXChaCha20Poly1305(
              key, hx('404142434445464748494a4b4c4d4e4f5051525354555657'), pt, aad)),
          'bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb'
          '731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452'
          '2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9'
          '21f9664c97637da9768812f615c68b13b52e'
          'c0875924c1c7987947deafd8780acf49');
    });
  });

  group('AEAD round-trip and tamper detection', () {
    final key = randomBytes(32);
    final nonce24 = randomBytes(24);
    final nonce12 = randomBytes(12);
    final pt = ascii('{"licence":"arxa","tier":"paid"}');
    final aad = ascii('v1');

    test('xchacha seal → open returns the plaintext', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      expect(sealed.length, pt.length + aeadTagSize);
      expect(openXChaCha20Poly1305(key, nonce24, sealed, aad), pt);
    });

    test('chacha seal → open returns the plaintext (no aad)', () {
      final sealed = sealChaCha20Poly1305(key, nonce12, pt);
      expect(openChaCha20Poly1305(key, nonce12, sealed), pt);
    });

    test('empty plaintext round-trips', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, Uint8List(0));
      expect(openXChaCha20Poly1305(key, nonce24, sealed), isEmpty);
    });

    test('flipping one ciphertext byte makes open throw', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      final tampered = Uint8List.fromList(sealed)..[3] ^= 0x01;
      expect(() => openXChaCha20Poly1305(key, nonce24, tampered, aad),
          throwsA(isA<AuthenticationException>()));
    });

    test('flipping one tag byte makes open throw', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      final tampered = Uint8List.fromList(sealed)
        ..[sealed.length - 1] ^= 0x80;
      expect(() => openXChaCha20Poly1305(key, nonce24, tampered, aad),
          throwsA(isA<AuthenticationException>()));
    });

    test('wrong key makes open throw', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      expect(() => openXChaCha20Poly1305(randomBytes(32), nonce24, sealed, aad),
          throwsA(isA<AuthenticationException>()));
    });

    test('wrong aad makes open throw', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      expect(() => openXChaCha20Poly1305(key, nonce24, sealed, ascii('v2')),
          throwsA(isA<AuthenticationException>()));
    });

    test('wrong nonce makes open throw', () {
      final sealed = sealXChaCha20Poly1305(key, nonce24, pt, aad);
      expect(
          () => openXChaCha20Poly1305(key, randomBytes(24), sealed, aad),
          throwsA(isA<AuthenticationException>()));
    });

    test('truncated ciphertext (shorter than tag) throws', () {
      expect(() => openXChaCha20Poly1305(key, nonce24, Uint8List(8)),
          throwsA(isA<AuthenticationException>()));
    });

    test('bad nonce length throws ArgumentError', () {
      expect(() => sealXChaCha20Poly1305(key, Uint8List(12), pt),
          throwsArgumentError);
    });
  });

  group('constantTimeEquals', () {
    test('equal / unequal / different length', () {
      expect(constantTimeEquals(seq(16), seq(16)), isTrue);
      expect(constantTimeEquals(seq(16), seq(16)..[0] = 99), isFalse);
      expect(constantTimeEquals(seq(16), seq(15)), isFalse);
    });
  });

  group('randomBytes', () {
    test('two draws differ and have the requested length', () {
      final a = randomBytes(24);
      final b = randomBytes(24);
      expect(a.length, 24);
      expect(constantTimeEquals(a, b), isFalse);
    });
  });

  group('hex', () {
    test('round-trips and rejects malformed input', () {
      expect(hexDecode(hexEncode(seq(32))), seq(32));
      expect(() => hexDecode('abc'), throwsArgumentError);
      expect(() => hexDecode('zz'), throwsArgumentError);
    });
  });
}
