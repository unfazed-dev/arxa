import 'package:appbox/security/config/companion_config.dart';

/// A fast config for tests: short heartbeat, quick death threshold. Values
/// are inline here (test-only) rather than from the bundled asset so tests
/// don't depend on real wall-clock cadence.
CompanionConfig testConfig({
  int heartbeatIntervalMs = 60,
  int heartbeatTimeoutMs = 300,
  int deadAfterFailures = 2,
}) {
  final cfg = CompanionConfig();
  cfg.loadMap({
    'channel': {
      'heartbeatIntervalMs': heartbeatIntervalMs,
      'heartbeatTimeoutMs': heartbeatTimeoutMs,
      'deadAfterFailures': deadAfterFailures,
    },
    'discovery': {
      'bonjourServiceType': '_appbox._tcp',
      'bonjourDomain': 'local.',
    },
    'pairing': {
      'qrRotationSeconds': 25,
      'sessionIdleTimeoutSeconds': 60,
    },
    'readyLine': {'tag': 'appbox-prototype-ready'},
    'fab': {
      'edgeDockInset': 16.0,
      'homeIndicatorKeepout': 34.0,
      'minimizedScale': 0.6,
    },
  });
  return cfg;
}
