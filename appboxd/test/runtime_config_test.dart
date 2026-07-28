import 'dart:convert';
import 'dart:io';

import 'package:appboxd/runtime_config.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeConfig.mergeMaps', () {
    test('keeps app sections verbatim and nests companion under one section', () {
      final merged = RuntimeConfig.mergeMaps(
        {
          'credential': {'keyPrefix': 'app_box.'},
          'pipeline': {'command': 'bash'},
        },
        {
          '_comment': 'drop me',
          'channel': {'heartbeatIntervalMs': 1500},
          'pairing': {'qrRotationSeconds': 25},
        },
      );
      expect(merged['credential'], {'keyPrefix': 'app_box.'});
      expect(merged['pipeline'], {'command': 'bash'});
      final companion = merged['companion'] as Map;
      expect(companion['channel'], {'heartbeatIntervalMs': 1500});
      expect(companion['pairing'], {'qrRotationSeconds': 25});
      expect(companion.containsKey('_comment'), isFalse);
    });

    test('omits the companion section when no companion config exists', () {
      final merged = RuntimeConfig.mergeMaps({'credential': {}}, null);
      expect(merged.containsKey('companion'), isFalse);
    });
  });

  group('RuntimeConfig.load', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cfg_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('loads the merged single-config shape from the two legacy files', () {
      final appPath = '${dir.path}/app_box.config.json';
      final companionPath = '${dir.path}/companion.config.json';
      File(appPath).writeAsStringSync(jsonEncode({
        'credential': {
          'storageTierLabel': 'macOS Keychain',
          'keyPrefix': 'app_box.',
        },
        'pipeline': {
          'command': 'bash',
          'args': ['pipeline/pipeline.sh'],
          'stateDir': 'pipeline/state',
          'repoConfigPath': 'config/app-box.config.json',
        },
        'harness': {'command': 'app-box-harness', 'envHint': 'APP_BOX_HARNESS_PATH'},
        'intake': {'command': 'python3', 'script': 'skills/app-box-intake/intake.py'},
        'licence': {'preconditionMessage': 'A licence is required.'},
        'launch': {'autoLaunchDemo': true, 'firstRunKey': 'app_box.first_run_done'},
        'prototype': {'host': '127.0.0.1', 'port': 0},
        'mcp': {
          'servers': [
            {'id': 'local', 'transport': 'stdio', 'enabled': false},
          ],
        },
      }));
      File(companionPath).writeAsStringSync(jsonEncode({
        'channel': {
          'heartbeatIntervalMs': 1500,
          'heartbeatTimeoutMs': 1200,
          'deadAfterFailures': 3,
        },
        'discovery': {'bonjourServiceType': '_appbox._tcp', 'bonjourDomain': 'local.'},
        'pairing': {'qrRotationSeconds': 25, 'sessionIdleTimeoutSeconds': 60},
        'readyLine': {'tag': 'app-box-prototype-ready'},
      }));

      final cfg = RuntimeConfig.load(appPath, companionPath: companionPath);

      expect(cfg.credentialKeyPrefix, 'app_box.');
      expect(cfg.pipelineCommand, 'bash');
      expect(cfg.pipelineArgs, ['pipeline/pipeline.sh']);
      expect(cfg.harnessCommand, 'app-box-harness');
      expect(cfg.intakeScript, 'skills/app-box-intake/intake.py');
      expect(cfg.licencePreconditionMessage, 'A licence is required.');
      expect(cfg.autoLaunchDemo, isTrue);
      expect(cfg.mcpServers.single['id'], 'local');
      // companion section
      expect(cfg.channelHeartbeatIntervalMs, 1500);
      expect(cfg.channelDeadAfterFailures, 3);
      expect(cfg.bonjourServiceType, '_appbox._tcp');
      expect(cfg.qrRotationSeconds, 25);
      expect(cfg.readyLineTag, 'app-box-prototype-ready');
    });

    test('hasSection reports the companion section honestly', () {
      final appPath = '${dir.path}/app_box.config.json';
      File(appPath).writeAsStringSync(jsonEncode({'credential': {}}));
      final cfg = RuntimeConfig.load(appPath);
      expect(cfg.hasSection('companion'), isFalse);
      expect(cfg.hasSection('credential'), isTrue);
    });

    test('missing section throws a StateError, not a cast error', () {
      final cfg = RuntimeConfig.fromMap({});
      expect(() => cfg.pipelineCommand, throwsStateError);
    });
  });
}
