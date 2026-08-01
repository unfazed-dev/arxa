import 'dart:convert';
import 'dart:io';

import 'package:appboxd/engine.dart';
import 'package:appboxd/gateway.dart' show TokenMinter;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Walks up from the cwd to the repo root (where config/appbox.config.json
/// lives), same convention as bin/appbox.dart.
String repoRoot() {
  var root = Directory.current.path;
  while (!File(p.join(root, 'config', 'appbox.config.json')).existsSync()) {
    final parent = p.dirname(root);
    if (parent == root) fail('config/appbox.config.json not found above $root');
    root = parent;
  }
  return root;
}

void main() {
  group('stage registry', () {
    test('returns the 11 Dart gates in dependency order', () {
      final stages = loadStages(repoRoot());
      expect(
        stages.map((s) => s.name).toList(),
        [
          'intake',
          'freeze',
          'structure',
          'scaffold',
          'coverage',
          'memory',
          'advertise',
          'review',
          'native_deps',
          'lens',
          'deploy',
        ],
      );
      for (final stage in stages) {
        expect(stage.tier, isNotEmpty);
      }
      // Tiers come from the fabric catalog: intake/review are frontier,
      // scaffold standard, and unlisted gates fall back to standard.
      expect(stages.firstWhere((s) => s.name == 'intake').tier, 'frontier');
      expect(stages.firstWhere((s) => s.name == 'review').tier, 'frontier');
      expect(stages.firstWhere((s) => s.name == 'scaffold').tier, 'standard');
    });
  });

  group('run manifests', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('engine-test-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('write/read round-trip preserves every field', () async {
      final manifest = RunManifest(
        runId: 'intake-1',
        stage: 'intake',
        startedAt: '2026-07-30T00:00:00.000Z',
        finishedAt: '2026-07-30T00:01:00.000Z',
        exitCode: 0,
        retries: 2,
        sessionId: 'session_abc',
      );
      await writeManifest(tmp.path, manifest);
      final back = await readManifest(tmp.path, 'intake-1');
      expect(back.toJson(), manifest.toJson());
      // Null session id survives the round trip too.
      final noSession = RunManifest(
        runId: 'review-2',
        stage: 'review',
        startedAt: 'a',
        finishedAt: 'b',
        exitCode: 1,
        retries: 0,
      );
      await writeManifest(tmp.path, noSession);
      expect((await readManifest(tmp.path, 'review-2')).sessionId, isNull);
    });
  });

  group('scorecard', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('engine-test-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('appends one JSON line per run', () async {
      await appendScorecard(tmp.path, {
        'stage': 'intake',
        'tier': 'frontier',
        'provider': null,
        'model': null,
        'tokens_in': 123,
        'tokens_out': 45,
        'cost': null,
        'gate_pass': true,
        'retries': 0,
      });
      await appendScorecard(tmp.path, {'stage': 'review', 'gate_pass': false});
      final lines = await File(
              p.join(tmp.path, 'pipeline', 'state', 'scorecard.jsonl'))
          .readAsLines();
      expect(lines, hasLength(2));
      final first = jsonDecode(lines[0]) as Map<String, Object?>;
      expect(first['tokens_in'], 123);
      expect(first['gate_pass'], isTrue);
      expect((jsonDecode(lines[1]) as Map)['gate_pass'], isFalse);
    });
  });

  group('headless runner (fake kimi on PATH)', () {
    late Directory tmp;
    late Engine engine;

    Map<String, String> fakeEnv({Map<String, String>? extra}) => {
          'PATH':
              '${p.join(Directory.current.path, 'test', 'fixtures')}:${Platform.environment['PATH']}',
          'FAKE_KIMI_ARGV_FILE': p.join(tmp.path, 'argv.txt'),
          'FAKE_KIMI_CONFIG_CAPTURE': p.join(tmp.path, 'config.toml'),
          ...?extra,
        };

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('engine-test-');
      engine = Engine(
        repoRoot: tmp.path,
        stagesOverride: [
          Stage(
            name: 'intake',
            gate: const ['bash', 'gates/intake/intake.sh'],
            tier: 'frontier',
          ),
        ],
      );
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('runs print mode, writes manifest + scorecard, keeps stderr',
        () async {
      final run = await engine.runStage(
        'intake',
        prompt: 'run the intake skill',
        gatePass: true,
        environment: fakeEnv(),
      );

      // The headless contract: -p <prompt> --output-format=stream-json.
      final argv =
          await File(p.join(tmp.path, 'argv.txt')).readAsLines();
      expect(argv, containsAllInOrder(['-p', 'run the intake skill']));
      expect(argv, contains('--output-format=stream-json'));

      // The CLI was pointed at the loopback gateway via KIMI_CODE_HOME.
      final config =
          await File(p.join(tmp.path, 'config.toml')).readAsString();
      expect(config, contains('base_url = "http://127.0.0.1:8787/llm/v1"'));
      expect(config, contains('api_key = "appbox-stage-token-TODO"'));
      expect(config, contains('default_permission_mode = "auto"'));

      // stream-json parsed: session id + usage; stderr not swallowed.
      expect(run.exitCode, 0);
      expect(run.retryable, isFalse);
      expect(run.manifest.sessionId, 'session_fake-1234');
      expect(run.tokensIn, 123);
      expect(run.tokensOut, 45);
      expect(run.stderr, contains('fake kimi stderr marker'));

      // Manifest on disk round-trips what the run returned.
      final manifest =
          await readManifest(tmp.path, run.manifest.runId);
      expect(manifest.toJson(), run.manifest.toJson());

      // Scorecard got exactly one line with the measured tokens.
      final lines = await File(
              p.join(tmp.path, 'pipeline', 'state', 'scorecard.jsonl'))
          .readAsLines();
      final entry = jsonDecode(lines.single) as Map<String, Object?>;
      expect(entry['stage'], 'intake');
      expect(entry['tier'], 'frontier');
      expect(entry['tokens_in'], 123);
      expect(entry['tokens_out'], 45);
      expect(entry['cost'], isNull);
      expect(entry['gate_pass'], isTrue);
    });

    test('resume passes -r with the recorded session id', () async {
      await engine.runStage('intake',
          prompt: 'first', environment: fakeEnv());
      await engine.runStage('intake',
          prompt: 'second', resume: true, environment: fakeEnv());
      final argv = await File(p.join(tmp.path, 'argv.txt')).readAsLines();
      expect(argv, containsAllInOrder(['-r', 'session_fake-1234']));
    });

    test('exit 75 is retryable, other failures are not', () async {
      final retryable = await engine.runStage('intake',
          prompt: 'x', environment: fakeEnv(extra: {'FAKE_KIMI_EXIT': '75'}));
      expect(retryable.exitCode, 75);
      expect(retryable.retryable, isTrue);

      final failed = await engine.runStage('intake',
          prompt: 'x', environment: fakeEnv(extra: {'FAKE_KIMI_EXIT': '1'}));
      expect(failed.exitCode, 1);
      expect(failed.retryable, isFalse);
      expect(failed.stderr, contains('fake kimi stderr marker'));
    });

    test('absent usage stays null — never fabricated', () async {
      final run = await engine.runStage('intake',
          prompt: 'x',
          environment: fakeEnv(extra: {'FAKE_KIMI_NO_USAGE': '1'}));
      expect(run.tokensIn, isNull);
      expect(run.tokensOut, isNull);
      final lines = await File(
              p.join(tmp.path, 'pipeline', 'state', 'scorecard.jsonl'))
          .readAsLines();
      final entry = jsonDecode(lines.single) as Map<String, Object?>;
      expect(entry['tokens_in'], isNull);
      expect(entry['tokens_out'], isNull);
    });

    group('scorecard cost (E4 fabric pricing)', () {
      void seedFabric({double? priceIn = 2, double? priceOut = 10}) {
        Directory(p.join(tmp.path, 'config')).createSync();
        File(p.join(tmp.path, 'config', 'model-fabric.json'))
            .writeAsStringSync(jsonEncode({
          'schema_version': 1,
          'providers': <Object?>[],
          'tiers': {
            'frontier': [
              {
                'model': 'alpha-1',
                'provider': 'alpha',
                'price_in': priceIn,
                'price_out': priceOut,
              },
            ],
          },
          'stages': {
            'intake': {'tier': 'frontier'},
          },
          'escalation': <String, Object?>{},
        }));
      }

      Future<Map<String, Object?>> scorecardEntry() async {
        final lines = await File(
                p.join(tmp.path, 'pipeline', 'state', 'scorecard.jsonl'))
            .readAsLines();
        return jsonDecode(lines.single) as Map<String, Object?>;
      }

      test('recorded usage is priced at the fabric rate', () async {
        seedFabric();
        await engine.runStage('intake', prompt: 'x', environment: fakeEnv());
        // fake kimi reports 123 in / 45 out; alpha-1 is $2/$10 per 1M.
        expect((await scorecardEntry())['cost'],
            closeTo(123 * 2 / 1e6 + 45 * 10 / 1e6, 1e-12));
      });

      test('null usage keeps cost null even with a priced catalog', () async {
        seedFabric();
        await engine.runStage('intake',
            prompt: 'x',
            environment: fakeEnv(extra: {'FAKE_KIMI_NO_USAGE': '1'}));
        expect((await scorecardEntry())['cost'], isNull);
      });

      test('an unpriced model keeps cost null — never estimated', () async {
        seedFabric(priceIn: null, priceOut: null);
        await engine.runStage('intake', prompt: 'x', environment: fakeEnv());
        expect((await scorecardEntry())['cost'], isNull);
      });
    });

    test('each run appends a stage_run memory event', () async {
      final run = await engine.runStage(
        'intake',
        prompt: 'run the intake skill',
        gatePass: true,
        environment: fakeEnv(),
      );

      final file = File(
          p.join(tmp.path, 'pipeline', 'state', 'memory', 'events.jsonl'));
      final lines = await file.readAsLines();
      expect(lines, hasLength(1));
      final event = jsonDecode(lines.single) as Map<String, Object?>;
      expect(DateTime.tryParse(event['ts'] as String), isNotNull);
      expect(event['kind'], 'stage_run');
      expect(event['actor'], 'engine');
      final payload = (event['payload'] as Map).cast<String, Object?>();
      expect(payload['stage'], 'intake');
      expect(payload['exit_code'], 0);
      expect(payload['retries'], 0);
      expect(payload['session_id'], run.manifest.sessionId);
      expect(payload['gate_pass'], isTrue);
    });

    test('gate_pass is omitted from the event when not yet known', () async {
      await engine.runStage('intake', prompt: 'x', environment: fakeEnv());
      final file = File(
          p.join(tmp.path, 'pipeline', 'state', 'memory', 'events.jsonl'));
      final event =
          jsonDecode((await file.readAsLines()).single) as Map<String, Object?>;
      final payload = (event['payload'] as Map).cast<String, Object?>();
      expect(payload.containsKey('gate_pass'), isFalse);
    });

    test('unknown stage is an argument error, not a fake run', () {
      expect(
        () => engine.runStage('nope',
            prompt: 'x', environment: fakeEnv()),
        throwsArgumentError,
      );
    });

    group('response cache (M2)', () {
      File argvFile() => File(p.join(tmp.path, 'argv.txt'));

      test('an identical second run is a cache hit — the CLI is not spawned',
          () async {
        final first = await engine.runStage('intake',
            prompt: 'cache me', environment: fakeEnv());
        expect(first.manifest.cacheHit, isFalse);
        expect(first.tokensIn, 123);
        argvFile().deleteSync();

        final second = await engine.runStage('intake',
            prompt: 'cache me', environment: fakeEnv());
        expect(argvFile().existsSync(), isFalse,
            reason: 'a cache hit must not re-spawn fake kimi');
        expect(second.manifest.cacheHit, isTrue);
        expect(second.exitCode, 0);
        expect(second.stdout, first.stdout);
        // Tokens are never fabricated for a cached run.
        expect(second.tokensIn, isNull);
        expect(second.tokensOut, isNull);

        final lines = await File(
                p.join(tmp.path, 'pipeline', 'state', 'scorecard.jsonl'))
            .readAsLines();
        expect(lines, hasLength(2));
        final miss = jsonDecode(lines[0]) as Map<String, Object?>;
        final hit = jsonDecode(lines[1]) as Map<String, Object?>;
        expect(miss['cache_hit'], isFalse);
        expect(hit['cache_hit'], isTrue);
        expect(hit['tokens_in'], isNull);
      });

      test('failures are never cached', () async {
        await engine.runStage('intake',
            prompt: 'flaky',
            environment: fakeEnv(extra: {'FAKE_KIMI_EXIT': '1'}));
        argvFile().deleteSync();

        final second = await engine.runStage('intake',
            prompt: 'flaky', environment: fakeEnv());
        expect(argvFile().existsSync(), isTrue,
            reason: 'an exit-1 run must be re-run, not served from cache');
        expect(second.manifest.cacheHit, isFalse);
      });
    });

    group('lesson curation (M1)', () {
      File lessonsFile() =>
          File(p.join(tmp.path, 'memory', 'stages', 'intake.LESSONS.md'));

      void seedLessons() {
        lessonsFile()
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('# intake — lessons\n\n## Lessons\n');
      }

      test('a gate failure appends one lesson line to the stage LESSONS.md',
          () async {
        seedLessons();
        await engine.runStage('intake',
            prompt: 'x',
            gatePass: false,
            environment: fakeEnv(extra: {'FAKE_KIMI_EXIT': '1'}));
        expect(lessonsFile().readAsLinesSync().last,
            '- gate intake failed (exit 1); stderr: fake kimi stderr marker');
      });

      test('a passing gate writes no lesson', () async {
        seedLessons();
        await engine.runStage('intake',
            prompt: 'x', gatePass: true, environment: fakeEnv());
        expect(lessonsFile().readAsLinesSync(), hasLength(3));
      });

      test('a missing LESSONS.md warns but never fails the run', () async {
        final run = await engine.runStage('intake',
            prompt: 'x', gatePass: false, environment: fakeEnv());
        expect(run.exitCode, 0);
      });
    });

    test('with a minter, the injected token is scoped to tier + one up',
        () async {
      final minter = TokenMinter();
      final minting = Engine(
        repoRoot: tmp.path,
        minter: minter,
        stagesOverride: [
          Stage(
            name: 'build',
            gate: const ['bash', 'gates/build/build.sh'],
            tier: 'standard',
          ),
        ],
      );
      await minting.runStage('build', prompt: 'x', environment: fakeEnv());
      final config =
          await File(p.join(tmp.path, 'config.toml')).readAsString();
      final match = RegExp(r'api_key = "(abx_[0-9a-f]+)"').firstMatch(config);
      expect(match, isNotNull, reason: 'config.toml carries a minted token');
      final scope = minter.verify(match!.group(1)!);
      expect(scope, isNotNull);
      expect(scope!.consumer, 'pipeline-stage:build');
      expect(scope.tiers, ['standard', 'frontier']);
    });
  });

  group('escalationTiers', () {
    test('stage tier plus one tier up, clamped at frontier', () {
      expect(escalationTiers('frontier'), ['frontier']);
      expect(escalationTiers('standard'), ['standard', 'frontier']);
      expect(escalationTiers('fast'), ['fast', 'standard']);
    });
  });
}
