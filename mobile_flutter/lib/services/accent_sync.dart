// AccentSync (D68 follow-up): the desktop's accent choice is the source of
// truth; the phone follows. The engine persists the choice (theme-accent
// host half, ~/.arxa/theme-accent.json) and every webview converges on it —
// this service brings the NATIVE chrome along: on transport connect (and
// while connected, on a slow poll) it pulls the accent, validates it against
// the studio's fixed swatch set, and publishes it for the MaterialApp theme.
// The last synced value is cached so a cold start offline still shows the
// last known accent instead of the kit default.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'transport_service.dart';

/// The exact swatches the studio's Accent row offers (theme-accent
/// client.js SWATCHES — keep in lockstep; anything else is rejected).
const studioAccentSwatches = <String>{'#0EBAE4', '#0EE4E0', '#12D49A'};

/// Cache key for the last synced accent (lowercase hex, no #).
const accentCacheKey = 'ui.accentHex';

class AccentSync {
  AccentSync(this._transport, {this._prefs, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const _cacheKey = accentCacheKey;

  final TransportService _transport;
  final SharedPreferences? _prefs;
  final HttpClient _httpClient;

  /// The synced accent, null until known — the app theme falls back to the
  /// kit default when null.
  final ValueNotifier<Color?> accent = ValueNotifier(null);

  StreamSubscription<ArxaConnectionStatus>? _statusSub;
  Timer? _poll;

  /// Valid swatch hex -> Color. Exposed for tests.
  static Color? parse(String? raw) {
    final hex = raw?.toUpperCase();
    if (hex == null || !studioAccentSwatches.contains(hex)) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  /// Seed from the last synced value (no I/O beyond prefs) — call once at
  /// boot before the first frame so a cold start keeps the known accent.
  Future<void> loadCached() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    accent.value = parse(prefs.getString(_cacheKey));
  }

  /// Subscribe: pull on connect, keep a slow poll while connected (the
  /// webview re-pulls every 5s; native chrome changes are rare — 15s is
  /// plenty), and re-pull on foreground resume via the transport's own
  /// connected re-announcements.
  void listen() {
    _statusSub ??= _transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected && s.studioUrl != null) {
        pull();
        _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => pull());
      } else {
        _poll?.cancel();
        _poll = null;
      }
    });
  }

  /// Fetch once from the engine over the tunnel; validate, publish, cache.
  Future<void> pull() async {
    final base = _transport.current.studioUrl;
    if (base == null) return;
    try {
      final req = await _httpClient.getUrl(base.resolve('__arxa/theme-accent'));
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = jsonDecode(await res.transform(utf8.decoder).join());
      final color = parse(body?.accent as String?);
      if (color == null) return;
      if (color != accent.value) {
        accent.value = color;
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, body.accent as String);
      }
    } on Object {
      // Unreachable engine or junk body: keep the current accent.
    }
  }

  void dispose() {
    _statusSub?.cancel();
    _poll?.cancel();
    _httpClient.close();
  }
}
