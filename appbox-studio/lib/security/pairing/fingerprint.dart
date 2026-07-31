import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The TLS-key fingerprint the companion PINS from the QR payload (12.3).
///
/// It is the SHA-256 of the desktop's ephemeral certificate's
/// SubjectPublicKeyInfo (SPKI) DER — the canonical public-key pin (the same
/// construction as HPKP/TOFU pinning). Pinning the *key*, not the whole cert,
/// lets the desktop rotate the self-signed cert for a new ephemeral session
/// without changing the pin only if the key is stable; in practice the desktop
/// generates one ephemeral keypair per pairing session and pins that key's SPKI.
///
/// Why SPKI and not the full DER: the SPKI is the key itself, independent of the
/// cert's subject/validity/serial — so a MITM presenting a legitimately-issued
/// cert for the same host with a DIFFERENT key fails the pin (the whole point).
/// A relay that terminates TLS on its own key produces a different SPKI hash →
/// the companion rejects it before trusting the channel.
///
/// This is the MITM defense. The QR-relay (phishing) defense is the nonce
/// lifecycle in [PairingSession] + the human confirm dialog — see 12.4.
class Fingerprint {
  /// SHA-256 of the SPKI DER bytes, lowercase hex.
  static String ofSpki(Uint8List spkiDer) {
    final digest = sha256.convert(spkiDer);
    return _toHex(digest.bytes);
  }

  /// Constant-time hex compare of two fingerprints (12.3 pin check).
  ///
  /// A pinned fingerprint is a trust decision: comparing with `==` short-circuits
  /// on the first mismatched byte and leaks timing. Pin checks are infrequent
  /// (once per pairing) so the cost is irrelevant; correctness is not — a timing
  /// oracle on the pin is a real (if narrow) attack surface. Walk every byte.
  static bool matches(String pinned, String presented) {
    final a = pinned.toLowerCase();
    final b = presented.toLowerCase();
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Group a hex fingerprint into colon-separated bytes for human comparison
  /// (`ab:cd:ef:…`) — the form the confirm dialog shows so a human can eyeball a
  /// mismatch if they ever need to. Not parsed back; display only.
  static String grouped(String hexFp) {
    final clean = hexFp.toLowerCase().replaceAll(':', '');
    final out = StringBuffer();
    for (var i = 0; i < clean.length; i += 2) {
      if (i > 0) out.write(':');
      out.write(clean.substring(i, i + 2));
    }
    return out.toString();
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
