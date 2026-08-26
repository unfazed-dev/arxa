// Deploy mechanics tests — Dart port of deploy.py's 11 self-test cases.
//
// Two layers, mirroring the Python self-test:
//   - Target ports (fastlane / shorebird / cloudflare / vercel): exercised
//     through a ScriptedRunner that asserts the EXACT external CLI command
//     shape + failure handling, with no toolchain and no credentials.
//   - The deploy() gate: requires the confirmed triple + approval; an automated
//     run that reaches it halts, minting nothing. Every attempt (shipped OR
//     halted) is recorded in the append-only ledger.
//
// The one property that makes a deploy stage self-testable (§17): the scripted
// runner asserts every command shape with NO toolchain, NO credentials, NO
// signing identity.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/deploy.dart';
import 'package:test/test.dart';

/// A fresh temp ledger path for one test (mirrors the Python `tmp_ledger`
/// fixture). Each test gets its own isolated ledger file.
String _tempLedger() {
  final dir = Directory.systemTemp.createTempSync('deploy_test');
  return '${dir.path}/deploy-ledger.json';
}

void main() {
  group('Target ports — command shape', () {
    test('fastlane-ios: build (gym) -> sign (match) -> upload (TestFlight)', () async {
      final runner = ScriptedRunner([
        (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'upload_to_testflight'],
            const RunnerResult(0, 'tf_build_77', '')),
      ]);
      final res = await fastlaneIos(runner, '1.2.3');
      expect(runner.callCount, 3, reason: 'fastlane-ios must issue gym -> match -> upload');
      expect(res.ok, isTrue);
      expect(res.target, 'fastlane-ios');
      expect(res.artefactId, 'tf_build_77');
    });

    test('fastlane-ios: upload failure is surfaced, not swallowed', () async {
      final runner = ScriptedRunner([
        (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'upload_to_testflight'],
            const RunnerResult(1, '', 'api 401')),
      ]);
      final res = await fastlaneIos(runner, '1.2.3');
      expect(res.ok, isFalse);
      expect(res.error, contains('api 401'));
    });

    test('fastlane-android: build aab -> upload to Play (internal track)', () async {
      final runner = ScriptedRunner([
        (['flutter', 'build', 'appbundle'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'upload_to_play_store'],
            const RunnerResult(0, 'play_vc_401', '')),
      ]);
      final res = await fastlaneAndroid(runner, '1.2.3');
      expect(runner.callCount, 2, reason: 'fastlane-android must issue build -> upload');
      expect(res.ok, isTrue);
      expect(res.artefactId, 'play_vc_401');
    });

    test('shorebird-release: full release -> release id', () async {
      final runner = ScriptedRunner([
        (['shorebird', 'release', 'release-version'],
            const RunnerResult(0, 'shorebird_rel_9', '')),
      ]);
      final res = await shorebirdRelease(runner, '1.2.3');
      expect(res.ok, isTrue);
      expect(res.artefactId, 'shorebird_rel_9');
    });

    test('shorebird-patch: OTA Dart patch -> patch id', () async {
      final runner = ScriptedRunner([
        (['shorebird', 'release', 'patch'],
            const RunnerResult(0, 'shorebird_patch_3', '')),
      ]);
      final res = await shorebirdPatch(runner, '1.2.4');
      expect(res.ok, isTrue);
      expect(res.artefactId, 'shorebird_patch_3');
    });

    test('cloudflare-pages: wrangler deploy -> deployment URL', () async {
      final runner = ScriptedRunner([
        (['wrangler', 'pages', 'deploy'],
            const RunnerResult(0, 'https://app.pages.dev', '')),
      ]);
      final res = await cloudflarePages(runner, '1.2.3');
      expect(res.ok, isTrue);
      expect(res.artefactId, 'https://app.pages.dev');
    });

    test('cloudflare-workers: wrangler deploy -> deployment URL', () async {
      final runner = ScriptedRunner([
        (['wrangler', 'deploy'],
            const RunnerResult(0, 'https://app.workers.dev', '')),
      ]);
      final res = await cloudflareWorkers(runner, '1.2.3');
      expect(res.ok, isTrue);
      expect(res.target, 'cloudflare-workers');
      expect(res.artefactId, 'https://app.workers.dev');
    });

    test('vercel: flutter build web -> vercel deploy --prod --yes', () async {
      final runner = ScriptedRunner([
        (['flutter', 'build', 'web', '--release'], const RunnerResult(0, '', '')),
        (['vercel', 'deploy', 'build/web', '--prod', '--yes'],
            const RunnerResult(0, 'https://app.vercel.app', '')),
      ]);
      final res = await vercel(runner, '1.2.3');
      expect(runner.callCount, 2, reason: 'vercel must issue build -> deploy');
      expect(res.ok, isTrue);
      expect(res.target, 'vercel');
      expect(res.artefactId, 'https://app.vercel.app');
    });

    test('vercel: a failed flutter build short-circuits before deploy', () async {
      final runner = ScriptedRunner([
        (['flutter', 'build', 'web', '--release'],
            const RunnerResult(1, '', 'compile error')),
      ]);
      final res = await vercel(runner, '1.2.3');
      expect(runner.callCount, 1, reason: 'must not deploy a broken build');
      expect(res.ok, isFalse);
      expect(res.error, contains('compile error'));
    });
  });

  group('vercel — wired and offered', () {
    test('vercel is in OFFERED and marked wired', () {
      expect(offered, contains('vercel'));
      expect(targetStatus('vercel'), 'wired');
    });
  });

  test('OFFERED is exactly the wired set (sorted)', () {
    expect(
      offered,
      [
        'cloudflare-pages',
        'cloudflare-workers',
        'fastlane-android',
        'fastlane-ios',
        'shorebird-patch',
        'shorebird-release',
        'vercel',
      ],
    );
  });

  group('doctor — preflight report, NOT a gate', () {
    test('doctor returns a report; it never decides whether a deploy may proceed', () {
      final rep = Deployer().doctor();
      expect(rep.offered, offered);
      expect(rep.stubNotOfferered, isEmpty);
      expect(rep.ready, contains('gate'));
    });

    test('doctor reads configured targets from a config file', () {
      final tmpDir = Directory.systemTemp.createTempSync('deploy_doctor');
      final cfg = File('${tmpDir.path}/deploy.json');
      cfg.writeAsStringSync(jsonEncode({
        'targets': ['fastlane-ios', 'cloudflare-pages', 'fastlane-ios'],
      }));
      final rep = Deployer().doctor(configPath: cfg.path);
      // configured targets are de-duplicated + sorted.
      expect(rep.configuredTargets, ['cloudflare-pages', 'fastlane-ios']);
    });

    test('doctor report shape: {offered, stub_not_offered, configured_targets, ready}', () {
      final map = Deployer().doctor().toMap();
      expect(map.keys.toSet(), {
        'offered',
        'stub_not_offered',
        'configured_targets',
        'ready',
      });
    });
  });

  group('deploy — the human gate', () {
    test('halts without approval, records a halted row, mints nothing', () async {
      final ledger = _tempLedger();
      // No approval token -> DeployHalted, no artefact, no recorded approver.
      // Done-when #4.
      await expectLater(
        () => Deployer(runner: ScriptedRunner([]), ledgerPath: ledger).deploy(
          target: 'fastlane-ios',
          version: '1.2.3',
          account: 'totem-labs',
          approval: '',
        ),
        throwsA(predicate<DeployHalted>(
            (DeployHalted e) => e.toString().contains('approval'))),
      );
      final led =
          (jsonDecode(File(ledger).readAsStringSync()) as Map<String, dynamic>)['attempts']
              as List;
      expect(led.length, 1);
      final row = led.first as Map<String, dynamic>;
      expect(row['status'], 'halted');
      expect(row['artefact_id'], isNull);
      expect(row['approver'], isNull);
    });

    test('missing version / account / target each halt too', () async {
      // Each of the other three fields, when empty, halts naming that field.
      final cases = <(String field, String target, String version, String account)>[
        ('version', 'fastlane-ios', '', 'a'),
        ('account', 'fastlane-ios', '1', ''),
        ('target', '', '1', 'a'),
      ];
      for (final c in cases) {
        final ledger = _tempLedger();
        await expectLater(
          () => Deployer(runner: ScriptedRunner([]), ledgerPath: ledger).deploy(
            target: c.$2,
            version: c.$3,
            account: c.$4,
            approval: 'ok',
          ),
          throwsA(predicate<DeployHalted>(
              (DeployHalted e) => e.toString().contains(c.$1))),
        );
      }
    });

    test('a confirmed deploy records a full ledger row with an artefact id', () async {
      // Done-when #5.
      final ledger = _tempLedger();
      final runner = ScriptedRunner([
        (['fastlane', 'run', 'gym'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'match'], const RunnerResult(0, '', '')),
        (['fastlane', 'run', 'upload_to_testflight'],
            const RunnerResult(0, 'tf_build_512', '')),
      ]);
      final res = await Deployer(runner: runner, ledgerPath: ledger).deploy(
        target: 'fastlane-ios',
        version: '1.2.3',
        account: 'totem-labs',
        approval: 'ops@totem',
      );
      expect(res.ok, isTrue);
      expect(res.artefactId, 'tf_build_512');
      final led =
          (jsonDecode(File(ledger).readAsStringSync()) as Map<String, dynamic>)['attempts']
              as List;
      final row = led.last as Map<String, dynamic>;
      expect(row['status'], 'shipped');
      expect(row['artefact_id'], 'tf_build_512');
      expect(row['target'], 'fastlane-ios');
      expect(row['version'], '1.2.3');
      expect(row['account'], 'totem-labs');
      expect(row['approver'], 'ops@totem');
      expect(row['timestamp'] as String, isNotEmpty);
      expect((row['timestamp'] as String).endsWith('Z'), isTrue);
    });

    test('an unknown target halts even with approval', () async {
      final ledger = _tempLedger();
      await expectLater(
        () => Deployer(runner: ScriptedRunner([]), ledgerPath: ledger).deploy(
          target: 'no-such-target',
          version: '1.2.3',
          account: 'totem-labs',
          approval: 'ops@totem',
        ),
        throwsA(predicate<DeployHalted>(
            (DeployHalted e) => e.toString().contains('unknown target'))),
      );
    });

    test('an approved vercel deploy ships through the gate', () async {
      // vercel is wired, but the human gate still applies: the confirmed
      // triple + approval ships and records a full ledger row.
      final ledger = _tempLedger();
      final runner = ScriptedRunner([
        (['flutter', 'build', 'web', '--release'], const RunnerResult(0, '', '')),
        (['vercel', 'deploy', 'build/web', '--prod', '--yes'],
            const RunnerResult(0, 'https://app.vercel.app', '')),
      ]);
      final res = await Deployer(runner: runner, ledgerPath: ledger).deploy(
        target: 'vercel',
        version: '1.2.3',
        account: 'totem-labs',
        approval: 'ops@totem',
      );
      expect(res.ok, isTrue);
      expect(res.artefactId, 'https://app.vercel.app');
      final led =
          (jsonDecode(File(ledger).readAsStringSync()) as Map<String, dynamic>)['attempts']
              as List;
      final row = led.last as Map<String, dynamic>;
      expect(row['status'], 'shipped');
      expect(row['target'], 'vercel');
      expect(row['approver'], 'ops@totem');
    });
  });
}
