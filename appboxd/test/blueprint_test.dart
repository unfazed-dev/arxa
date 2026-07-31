// Tests for blueprint.dart — the Blueprint package assembler (port of blueprint.py).
//
// These tests verify structural correctness (files emitted, content patterns)
// AND cross-language parity: the golden hash must match the Python reference
// for the same breakdown, so a design that produced golden X in Python produces
// the same X in Dart.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:appboxd/blueprint.dart';

// ─── helpers ───

/// Create a temp output dir, return its path.
String _tempOut() =>
    p.join(Directory.systemTemp.path, 'bp_test_${DateTime.now().microsecondsSinceEpoch}');

/// Write a breakdown JSON to a temp file, return its path.
String _writeBreakdown(Map<String, dynamic> breakdown) {
  final f = File(p.join(Directory.systemTemp.path,
      'bp_bd_${DateTime.now().microsecondsSinceEpoch}.json'));
  f.writeAsStringSync(jsonEncode(breakdown));
  return f.path;
}

// ─── fixtures ───

/// Minimal breakdown with an auth-guarded splash → signin → home flow.
Map<String, dynamic> _authFlowBreakdown() => {
      'meta': {
        'source': 'myapp.html',
        'platforms': ['ios', 'android', 'web'],
      },
      'screenFlow': [
        {'id': 'splash', 'guard': {'state': 'auth', 'value': 'loading'}},
        {'id': 'signin'},
        {'id': 'home'},
      ],
    };

/// Breakdown with a primaryNav (bottom tab bar) — should emit a nav shell.
Map<String, dynamic> _navShellBreakdown() => {
      'meta': {'source': 'tabbed.html'},
      'screenFlow': [
        {'id': 'home'},
        {'id': 'search'},
        {'id': 'profile'},
      ],
      'primaryNav': {
        'tabs': [
          {'id': 'home', 'label': 'Home', 'sfSymbol': 'house.fill'},
          {'id': 'search', 'label': 'Search', 'sfSymbol': 'magnifyingglass'},
          {'id': 'profile', 'label': 'Profile', 'sfSymbol': 'person.fill'},
        ],
      },
    };

// ─── tests ───

void main() {
  late String outDir;

  setUp(() {
    outDir = _tempOut();
  });

  tearDown(() {
    final d = Directory(outDir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  });

  test('golden hash matches Python reference for auth-flow breakdown', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    final rc = buildBlueprint(bdPath, outDir);
    expect(rc, 0, reason: 'buildBlueprint should succeed');

    final golden =
        File(p.join(outDir, 'golden.sha256')).readAsStringSync().trim();
    // Parity with tools/vendor/stages/blueprint.py _golden() for the same input.
    expect(golden,
        '9386eb1b9f6051dfbca73e7f35236c15c639de3a59cdc6809ecad9983dd8af90');
    expect(golden.length, 64);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(golden), isTrue);
  });

  test('golden hash matches Python reference for nav-shell breakdown', () {
    final bdPath = _writeBreakdown(_navShellBreakdown());
    final rc = buildBlueprint(bdPath, outDir);
    expect(rc, 0);

    final golden =
        File(p.join(outDir, 'golden.sha256')).readAsStringSync().trim();
    expect(golden,
        '3225079d7b9c895b4e1529d78aae0c54aaa0db5a958c0de417e3fcbe71e23304');
  });

  test('manifest has correct appName, displayName, and screen list', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    buildBlueprint(bdPath, outDir);

    final manifest = jsonDecode(
        File(p.join(outDir, 'manifest.json')).readAsStringSync()) as Map;

    expect(manifest['appName'], 'myapp');
    expect(manifest['displayName'], 'Myapp');
    expect(manifest['platforms'], ['ios', 'android', 'web']);
    expect(manifest['templatesVersion'], '36');
    expect(manifest['factoryVersion'], '0.1.0');

    final screens = manifest['screens'] as List;
    expect(screens.length, 3);
    expect(screens[0]['id'], 'splash');
    expect(screens[0]['class'], 'Splash');
    expect(screens[0]['route'], 'splash');
    expect(screens[2]['id'], 'home');
    expect(screens[2]['class'], 'Home');
  });

  test('extension-point View + ViewModel emitted per screen with markers', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    buildBlueprint(bdPath, outDir);

    final tdir = p.join(outDir, 'templates');

    // Each screen should get a _view.dart and _viewmodel.dart
    for (final screen in ['splash', 'signin', 'home']) {
      final viewFile = File(p.join(tdir, 'lib', 'presentation', '${screen}_view.dart'));
      final vmFile =
          File(p.join(tdir, 'lib', 'presentation', '${screen}_viewmodel.dart'));

      expect(viewFile.existsSync(), isTrue, reason: '$screen view missing');
      expect(vmFile.existsSync(), isTrue, reason: '$screen viewmodel missing');

      final viewContent = viewFile.readAsStringSync();
      expect(viewContent, contains('FACTORY EXTENSION POINT'));
      expect(viewContent,
          contains('@appbox-extension-point: presentation/${screen}_view'));

      final cls = screen[0].toUpperCase() + screen.substring(1);
      expect(viewContent, contains('class ${cls}View extends StackedView'));
      final vmContent = vmFile.readAsStringSync();
      expect(vmContent, contains('class ${cls}ViewModel extends BaseViewModel'));
    }
  });

  test('primaryNav triggers home_shell_view.dart and root_navigation_viewmodel.dart', () {
    final bdPath = _writeBreakdown(_navShellBreakdown());
    buildBlueprint(bdPath, outDir);

    final tdir = p.join(outDir, 'templates');

    final shellFile =
        File(p.join(tdir, 'lib', 'presentation', 'home_shell_view.dart'));
    final shellVmFile = File(
        p.join(tdir, 'lib', 'presentation', 'root_navigation_viewmodel.dart'));

    expect(shellFile.existsSync(), isTrue, reason: 'home_shell_view.dart missing');
    expect(shellVmFile.existsSync(), isTrue,
        reason: 'root_navigation_viewmodel.dart missing');

    final shellContent = shellFile.readAsStringSync();
    expect(shellContent, contains('AUTO-GENERATED'));
    expect(shellContent, contains('class HomeShellView'));
    expect(shellContent, contains('IndexedStack'));

    // The 3 tab screens should be imported and composed
    expect(shellContent, contains('HomeView()'));
    expect(shellContent, contains('SearchView()'));
    expect(shellContent, contains('ProfileView()'));

    // app.dart should include HomeShellView as a route, and tab screens should
    // NOT be top-level routes (they're hosted in the shell's IndexedStack)
    final appFile = File(p.join(tdir, 'lib', 'app', 'app.dart'));
    final appContent = appFile.readAsStringSync();
    expect(appContent, contains('HomeShellView'));
  });

  test('generated layer includes core skeleton files', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    buildBlueprint(bdPath, outDir);

    final tdir = p.join(outDir, 'templates');

    // Core generated files
    final expected = [
      'lib/main.dart',
      'lib/app/app.dart',
      'lib/ui/render_strategy.dart',
      'lib/ui/primitives.dart',
      'lib/ui/feedback_service.dart',
      'lib/ui/app_theme.dart',
      'lib/domain/ports/repository.dart',
      'lib/infrastructure/supabase_client.dart',
      'lib/infrastructure/supabase_auth_service.dart',
      'lib/infrastructure/base_supabase_repository.dart',
      'lib/app_tokens.dart',
      'pubspec.yaml',
      'analysis_options.yaml',
    ];

    for (final rel in expected) {
      expect(File(p.join(tdir, rel)).existsSync(), isTrue,
          reason: 'Expected generated file missing: $rel');
    }

    // main.dart should contain the app display name
    final mainContent = File(p.join(tdir, 'lib', 'main.dart')).readAsStringSync();
    expect(mainContent, contains("title: 'Myapp'"));

    // render_strategy.dart should define the three strategies
    final rsContent =
        File(p.join(tdir, 'lib', 'ui', 'render_strategy.dart')).readAsStringSync();
    expect(rsContent, contains('enum RenderStrategy { glass, expressive, shadcn }'));

    // primitives.dart should have the mono brand providers set (apple, github, x)
    final primContent =
        File(p.join(tdir, 'lib', 'ui', 'primitives.dart')).readAsStringSync();
    expect(primContent, contains("_kMonoBrandProviders"));
    expect(primContent, contains("'apple'"));
    expect(primContent, contains("'github'"));
    expect(primContent, contains("'x'"));

    // primitives.dart should have provider platforms (apple: ios only)
    expect(primContent, contains("_kProviderPlatforms"));
    expect(primContent, contains("'apple'"));
    expect(primContent, contains("'ios'"));
  });

  test('pubspec.yaml contains all declared dependencies', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    buildBlueprint(bdPath, outDir);

    final pubspec = File(p.join(outDir, 'templates', 'pubspec.yaml'))
        .readAsStringSync();

    // Core deps that must always be present
    for (final dep in [
      'stacked:',
      'stacked_services:',
      'supabase_flutter:',
      'shadcn_ui:',
      'flutter_svg:',
      'drift:',
      'mocktail:',
      'flutter_lints:',
    ]) {
      expect(pubspec, contains(dep), reason: 'Missing pubspec dep: $dep');
    }

    // flutter_localizations should be a nested sdk entry
    expect(pubspec, contains('flutter_localizations:\n    sdk: flutter'));

    // generate: true for gen-l10n
    expect(pubspec, contains('generate: true'));
  });

  test('playbook.md contains app name and screen table', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());
    buildBlueprint(bdPath, outDir);

    final playbook =
        File(p.join(outDir, 'playbook.md')).readAsStringSync();

    expect(playbook, contains('# Build Playbook'));
    expect(playbook, contains('`myapp`'));
    expect(playbook, contains('| route | view | status | guard |'));
    expect(playbook, contains('splash'));
    expect(playbook, contains('SplashView'));
    expect(playbook, contains('home'));
    expect(playbook, contains('HomeView'));
  });

  test('golden is deterministic — identical input produces identical hash', () {
    final bdPath = _writeBreakdown(_authFlowBreakdown());

    final out1 = _tempOut();
    final out2 = _tempOut();
    buildBlueprint(bdPath, out1);
    buildBlueprint(bdPath, out2);

    final g1 = File(p.join(out1, 'golden.sha256')).readAsStringSync().trim();
    final g2 = File(p.join(out2, 'golden.sha256')).readAsStringSync().trim();

    expect(g1, g2, reason: 'Same input must produce identical golden');

    Directory(out1).deleteSync(recursive: true);
    Directory(out2).deleteSync(recursive: true);
  });

  test('returns 1 on malformed breakdown JSON', () {
    final badPath = p.join(Directory.systemTemp.path,
        'bp_bad_${DateTime.now().microsecondsSinceEpoch}.json');
    File(badPath).writeAsStringSync('{not valid json');
    expect(buildBlueprint(badPath, outDir), 1);
  });
}
