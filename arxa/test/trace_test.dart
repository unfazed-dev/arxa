// trace test — verifies the Dart port matches trace.py's self-test behavior.
// Synthetic target + breakdown.json in a temp parent dir (the .blueprint layout:
// breakdown.json lives beside the target, resolved by derive's default path).

import 'dart:convert';
import 'dart:io';

import 'package:arxa/trace.dart';
import 'package:test/test.dart';

void main() {
  late Directory parent;
  late Directory target;

  setUp(() {
    parent = Directory.systemTemp.createTempSync('trace-test-');
    target = Directory('${parent.path}/target');
  });

  tearDown(() {
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  // 1 ─ correct trace: both screens have view + VM + route → manifest correct,
  //    guard PASS.
  test('correct trace: both screens view+VM+route → manifest correct, guard PASS',
      () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    final s = m.screens;
    expect(s.keys.toSet(), {'signin', 'splash'});
    expect(s['signin']!.route, '/signin-view');
    expect(s['signin']!.viewClass, 'SigninView');
    expect(s['signin']!.viewmodelClass, 'SigninViewModel');
    expect(s['splash']!.initial, isTrue);
    expect(s['signin']!.initial, isFalse);
    expect(check(m).passed, isTrue, reason: check(m).issues.join('\n'));
  });

  // 2 ─ router drift: regenerate router without `splashView = '/'` → splash route
  //    is null, guard FAIL. (The bug the guard exists to catch.)
  test('router drift: splashView dropped → splash route null, guard FAIL', () {
    _buildCorrect(target, parent);
    _file(target, 'lib/app/app.router.dart',
        "  static const homeShellView = '/';\n"
        "  static const signinView = '/signin-view';\n");
    final m = derive(target.path);
    expect(m.screens['splash']!.route, isNull,
        reason: 'a stale router that drops splashView must surface as route=null');
    final r = check(m);
    expect(r.passed, isFalse);
    expect(r.issues.any((i) => i.contains('splash')), isTrue);
  });

  // 3 ─ view class resolution: `signin` → `SigninView`.
  test('view class resolution: signin → SigninView', () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    expect(m.screens['signin']!.viewClass, 'SigninView');
    expect(m.screens['splash']!.viewClass, 'SplashView');
  });

  // 4 ─ viewmodel detection: `SigninViewModel` extends `BaseViewModel`.
  test('viewmodel detection: SigninViewModel extends BaseViewModel', () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    expect(m.screens['signin']!.viewmodelClass, 'SigninViewModel');
    expect(m.screens['signin']!.viewmodelFile, 'lib/presentation/signin_viewmodel.dart');
    expect(m.screens['splash']!.viewmodelClass, 'SplashViewModel');
  });

  // 5 ─ data deps: locator<SupabaseAuthService> and locator<SessionRepository>
  //    captured from the materialized VM.
  test('data deps: locator<...> deps captured', () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    expect(m.screens['signin']!.dataDeps,
        containsAll(['SupabaseAuthService', 'SessionRepository']));
  });

  // 6 ─ primitives: action.button, display.text extracted from breakdown.
  test('primitives: action.button, display.text extracted from breakdown', () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    expect(m.screens['signin']!.primitives, ['action.button', 'display.text']);
  });

  // 7 ─ initial route: splashView = '/' → splash.initial == true.
  test('initial route: splashView = "/" → splash.initial == true', () {
    _buildCorrect(target, parent);
    final m = derive(target.path);
    expect(m.screens['splash']!.initial, isTrue);
    expect(m.screens['signin']!.initial, isFalse);
  });

  // 8 ─ guard: missing view → issue; missing VM → issue; missing route (non-tab)
  //    → issue.
  group('guard', () {
    test('missing view → issue', () {
      _file(target, 'lib/app/app.router.dart',
          "  static const splashView = '/';\n");
      _file(target, 'lib/presentation/splash_view.dart',
          'class SplashView extends StackedView<SplashViewModel> {}\n');
      _file(target, 'lib/presentation/splash_viewmodel.dart',
          'class SplashViewModel extends BaseViewModel {}\n');
      _writeBreakdown(parent, pages: [
        {'id': 'splash', 'name': 'SplashView', 'components': <Map<String, dynamic>>[]},
        {'id': 'ghost', 'name': 'GhostView', 'components': <Map<String, dynamic>>[]},
      ]);
      final r = check(derive(target.path));
      expect(r.passed, isFalse);
      expect(r.issues.any((i) => i.contains("'ghost'") && i.contains('no emitted view file')),
          isTrue);
    });

    test('missing VM → issue', () {
      _file(target, 'lib/app/app.router.dart',
          "  static const splashView = '/';\n"
          "  static const fooView = '/foo-view';\n");
      _file(target, 'lib/presentation/splash_view.dart',
          'class SplashView extends StackedView<SplashViewModel> {}\n');
      _file(target, 'lib/presentation/splash_viewmodel.dart',
          'class SplashViewModel extends BaseViewModel {}\n');
      _file(target, 'lib/presentation/foo_view.dart',
          'class FooView extends StackedView<FooViewModel> {}\n');
      // NOTE: no foo_viewmodel.dart — FooViewModel is referenced but never emitted.
      _writeBreakdown(parent, pages: [
        {'id': 'splash', 'name': 'SplashView', 'components': <Map<String, dynamic>>[]},
        {'id': 'foo', 'name': 'FooView', 'components': <Map<String, dynamic>>[]},
      ]);
      final r = check(derive(target.path));
      expect(r.passed, isFalse);
      expect(r.issues.any((i) => i.contains("'foo'") && i.contains('has no viewmodel')),
          isTrue);
    });

    test('missing route (non-tab) → issue', () {
      _file(target, 'lib/app/app.router.dart',
          "  static const splashView = '/';\n");
      // NOTE: no lonelyView const — lonely's route drifted out of the router.
      _file(target, 'lib/presentation/splash_view.dart',
          'class SplashView extends StackedView<SplashViewModel> {}\n');
      _file(target, 'lib/presentation/splash_viewmodel.dart',
          'class SplashViewModel extends BaseViewModel {}\n');
      _file(target, 'lib/presentation/lonely_view.dart',
          'class LonelyView extends StackedView<LonelyViewModel> {}\n');
      _file(target, 'lib/presentation/lonely_viewmodel.dart',
          'class LonelyViewModel extends BaseViewModel {}\n');
      _writeBreakdown(parent, pages: [
        {'id': 'splash', 'name': 'SplashView', 'components': <Map<String, dynamic>>[]},
        {'id': 'lonely', 'name': 'LonelyView', 'components': <Map<String, dynamic>>[]},
      ]);
      final r = check(derive(target.path));
      expect(r.passed, isFalse);
      expect(r.issues.any((i) => i.contains("'lonely'") && i.contains('route absent')),
          isTrue);
    });
  });

  // extra: a primary-nav tab reached via the shell does NOT need a top-level
  // route — routed_via='shellTab' and no route is not a gap.
  test('primary-nav tab: routed_via=shellTab, missing route is NOT a gap', () {
    _file(target, 'lib/app/app.router.dart',
        "  static const splashView = '/';\n");
    _file(target, 'lib/presentation/splash_view.dart',
        'class SplashView extends StackedView<SplashViewModel> {}\n');
    _file(target, 'lib/presentation/splash_viewmodel.dart',
        'class SplashViewModel extends BaseViewModel {}\n');
    _file(target, 'lib/presentation/home_view.dart',
        'class HomeView extends StackedView<HomeViewModel> {}\n');
    _file(target, 'lib/presentation/home_viewmodel.dart',
        'class HomeViewModel extends BaseViewModel {}\n');
    _writeBreakdown(
      parent,
      pages: [
        {'id': 'splash', 'name': 'SplashView', 'components': <Map<String, dynamic>>[]},
        {'id': 'home', 'name': 'HomeView', 'components': <Map<String, dynamic>>[]},
      ],
      primaryNav: {
        'tabs': [
          {'id': 'home', 'label': 'Home'},
        ],
      },
    );
    final m = derive(target.path);
    expect(m.screens['home']!.routedVia, 'shellTab');
    expect(m.screens['home']!.route, isNull);
    expect(check(m).passed, isTrue, reason: check(m).issues.join('\n'));
  });
}

// ── fixtures ──────────────────────────────────────────────────────────────────

/// Create a file (with parent dirs) under [root] at [relPath] and write [content].
File _file(Directory root, String relPath, String content) {
  final f = File('${root.path}/$relPath');
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
  return f;
}

/// The canonical CORRECT target from the trace.py self-test: two screens
/// (signin + splash) each with view + VM + route, splash is initial ('/'),
/// signin pulls two locator deps.
void _buildCorrect(Directory target, Directory parent) {
  _file(target, 'lib/app/app.router.dart',
      "  static const splashView = '/';\n"
      "  static const signinView = '/signin-view';\n");
  _file(target, 'lib/presentation/signin_view.dart',
      'class SigninView extends StackedView<SigninViewModel> {}\n');
  _file(target, 'lib/presentation/signin_viewmodel.dart',
      'class SigninViewModel extends BaseViewModel {\n'
      '  final _auth = locator<SupabaseAuthService>();\n'
      '  final _repo = locator<SessionRepository>();\n'
      '}\n');
  _file(target, 'lib/presentation/splash_view.dart',
      'class SplashView extends StackedView<SplashViewModel> {}\n');
  _file(target, 'lib/presentation/splash_viewmodel.dart',
      'class SplashViewModel extends BaseViewModel {}\n');
  _writeBreakdown(parent);
}

/// Write breakdown.json beside the target (the .blueprint layout derive defaults
/// to). [pages] / [primaryNav] default to the canonical correct decomposition.
void _writeBreakdown(
  Directory parent, {
  List<Map<String, dynamic>>? pages,
  Map<String, dynamic>? primaryNav,
}) {
  File('${parent.path}/breakdown.json').writeAsStringSync(
    jsonEncode({
      'pages': pages ??
          [
            {
              'id': 'signin',
              'name': 'SignInView',
              'route': '/signin',
              'guard': {'state': 'authStage', 'value': 'signin'},
              'sourceRef': 'body>SignInView',
              'components': [
                {
                  'id': 'signin',
                  'name': 'SignInView',
                  'primitives': [
                    {'id': 'action.button'},
                    {'id': 'display.text'},
                  ],
                },
              ],
            },
            {
              'id': 'splash',
              'name': 'SplashView',
              'route': '/splash',
              'guard': {'state': 'authStage', 'value': 'splash'},
              'components': [
                {
                  'id': 'splash',
                  'primitives': [
                    {'id': 'display.icon'},
                  ],
                },
              ],
            },
          ],
      'screenFlow': <Object?>[],
      'primaryNav': primaryNav ?? <String, dynamic>{},
      'meta': {'appName': 'test'},
    }),
  );
}
