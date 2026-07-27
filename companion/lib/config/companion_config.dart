import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads the companion's bundled runtime config
/// (`assets/config/companion.config.json`).
///
/// R3: every project-varying value — heartbeat cadence, reconnect/dead
/// thresholds, the Bonjour service type, the FAB insets — comes from here,
/// never from a code literal. Mirrors the desktop app's [ConfigService].
class CompanionConfig {
  Map<String, dynamic>? _cfg;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/config/companion.config.json');
    _cfg = jsonDecode(raw) as Map<String, dynamic>;
    _loaded = true;
  }

  /// Test seam — load config from an in-memory map (no asset bundle).
  @visibleForTesting
  void loadMap(Map<String, dynamic> map) {
    _cfg = map;
    _loaded = true;
  }

  Map<String, dynamic> _section(String key) {
    if (!_loaded || _cfg == null) {
      throw StateError('CompanionConfig.load() must be awaited before read');
    }
    return (_cfg![key] as Map<String, dynamic>).cast<String, dynamic>();
  }

  // channel heartbeat
  Duration get heartbeatInterval =>
      Duration(milliseconds: _section('channel')['heartbeatIntervalMs'] as int);
  Duration get heartbeatTimeout =>
      Duration(milliseconds: _section('channel')['heartbeatTimeoutMs'] as int);
  int get deadAfterFailures => _section('channel')['deadAfterFailures'] as int;

  // discovery
  String get bonjourServiceType =>
      _section('discovery')['bonjourServiceType'] as String;
  String get bonjourDomain => _section('discovery')['bonjourDomain'] as String;

  // pairing
  Duration get qrRotation =>
      Duration(seconds: _section('pairing')['qrRotationSeconds'] as int);
  Duration get sessionIdleTimeout =>
      Duration(seconds: _section('pairing')['sessionIdleTimeoutSeconds'] as int);

  // P09 ready-line contract
  String get readyLineTag => _section('readyLine')['tag'] as String;

  // FAB constraints
  double get fabEdgeDockInset => _section('fab')['edgeDockInset'] as double;
  double get fabHomeIndicatorKeepout =>
      _section('fab')['homeIndicatorKeepout'] as double;
  double get fabMinimizedScale => _section('fab')['minimizedScale'] as double;
}
