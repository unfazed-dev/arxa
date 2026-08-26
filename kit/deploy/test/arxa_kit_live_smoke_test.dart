@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:arxa_kit_deploy/arxa_kit_deploy.dart';
import 'package:test/test.dart';

/// OPT-IN live smoke: proves the CLI + token path against the real providers.
/// Every test skips unless its credentials are in the environment — without
/// tokens this file is a no-op (see README "Live smoke").
///
/// Preview/non-prod only: the vercel smoke omits `--prod`, the pages smoke
/// deploys to a throwaway project on a non-production branch, and a Worker is
/// unrouted until you bind one. Everything created here is a REAL deployment
/// on your account — clean up in the provider dashboard afterwards.
void main() {
  final env = Platform.environment;
  final stamp = DateTime.now().millisecondsSinceEpoch;

  Directory fixtureDir(String prefix, Map<String, String> files) {
    final dir = Directory.systemTemp.createTempSync('${prefix}_$stamp');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final entry in files.entries) {
      File('${dir.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    return dir;
  }

  group('vercel (live)', () {
    final token = env['VERCEL_TOKEN'];

    test('kit.deploy.live-smoke — doctor all-ok, then preview deploy of a static fixture', () async {
      const runner = ArxaKitIoProcessRunner();
      final site = fixtureDir('arxa_smoke_vercel', {
        'index.html': '<!doctype html><title>arxa smoke</title>ok',
      });
      final config = ArxaKitDeployConfig(
        projectName: 'arxa-smoke-$stamp',
        workingDirectory: site.path,
        environment: {
          'VERCEL_TOKEN': token!,
          if (env['VERCEL_ORG_ID'] != null)
            'VERCEL_ORG_ID': env['VERCEL_ORG_ID']!,
          if (env['VERCEL_PROJECT_ID'] != null)
            'VERCEL_PROJECT_ID': env['VERCEL_PROJECT_ID']!,
        },
      );

      final checks = await const ArxaKitVercelTarget(runner).doctor(config);
      expect(checks, everyElement(predicate<ArxaKitDoctorCheck>((c) => c.ok)),
          reason: checks.map((c) => '${c.name}: ${c.detail}').join('\n'));

      // The target's deploy() runs `flutter build web` first — the smoke
      // proves the CLI + token path, not the Flutter toolchain, so it drives
      // the vercel CLI directly. PREVIEW deploy: never --prod here.
      final deploy = await runner.run(
        'vercel',
        ['deploy', '.', '--yes'],
        workingDirectory: site.path,
        environment: config.environment,
      );
      expect(deploy.ok, isTrue,
          reason: 'vercel exited ${deploy.exitCode}: ${deploy.stderr}');
    }, skip: token == null ? 'VERCEL_TOKEN not set' : false);
  });

  group('cloudflare-pages (live)', () {
    final token = env['CLOUDFLARE_API_TOKEN'];
    final account = env['CLOUDFLARE_ACCOUNT_ID'];

    test('kit.deploy.live-smoke — doctor all-ok, then preview deploy of a static fixture', () async {
      const runner = ArxaKitIoProcessRunner();
      final site = fixtureDir('arxa_smoke_pages', {
        'index.html': '<!doctype html><title>arxa smoke</title>ok',
      });
      final config = ArxaKitDeployConfig(
        projectName: 'arxa-smoke-$stamp',
        workingDirectory: site.path,
        environment: {
          'CLOUDFLARE_API_TOKEN': token!,
          'CLOUDFLARE_ACCOUNT_ID': account!,
        },
      );

      final checks = await const ArxaKitCloudflarePagesTarget(runner).doctor(config);
      expect(checks, everyElement(predicate<ArxaKitDoctorCheck>((c) => c.ok)),
          reason: checks.map((c) => '${c.name}: ${c.detail}').join('\n'));

      // Same honest shape as vercel: skip the flutter build step, drive the
      // wrangler CLI directly. --branch makes it a preview deployment on the
      // throwaway project, never the production branch.
      final deploy = await runner.run(
        'wrangler',
        [
          'pages',
          'deploy',
          '.',
          '--project-name=${config.projectName}',
          '--branch=smoke-preview',
        ],
        workingDirectory: site.path,
        environment: config.environment,
      );
      expect(deploy.ok, isTrue,
          reason: 'wrangler exited ${deploy.exitCode}: ${deploy.stderr}');
    },
        skip: (token == null || account == null)
            ? 'CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set'
            : false);
  });

  group('cloudflare-workers (live)', () {
    final token = env['CLOUDFLARE_API_TOKEN'];
    final account = env['CLOUDFLARE_ACCOUNT_ID'];

    test('kit.deploy.live-smoke — doctor all-ok, then wrangler deploy of a minimal worker', () async {
      const runner = ArxaKitIoProcessRunner();
      // Workers ship their own source — no flutter build step, so this smoke
      // can exercise the target's deploy() end to end. Unrouted worker =
      // non-prod until a route is bound.
      final worker = fixtureDir('arxa_smoke_worker', {
        'index.js':
            "export default { fetch() { return new Response('arxa smoke ok'); } };\n",
        'wrangler.toml': 'name = "arxa-smoke-$stamp"\n'
            'main = "index.js"\n'
            'compatibility_date = "2025-01-01"\n',
      });
      final config = ArxaKitDeployConfig(
        projectName: 'arxa-smoke-$stamp',
        workingDirectory: worker.path,
        environment: {
          'CLOUDFLARE_API_TOKEN': token!,
          'CLOUDFLARE_ACCOUNT_ID': account!,
        },
      );

      final checks = await const ArxaKitCloudflareWorkersTarget(runner).doctor(config);
      expect(checks, everyElement(predicate<ArxaKitDoctorCheck>((c) => c.ok)),
          reason: checks.map((c) => '${c.name}: ${c.detail}').join('\n'));

      final result = await const ArxaKitCloudflareWorkersTarget(runner).deploy(config);
      expect(result.ok, isTrue, reason: result.failureReason ?? '');
    },
        skip: (token == null || account == null)
            ? 'CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set'
            : false);
  });
}
