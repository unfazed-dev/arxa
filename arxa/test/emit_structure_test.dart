// emit_structure test — ports the Python self-test's 7 discriminating cases.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/emit_structure.dart';
import 'package:arxa/project.dart' show arxaHomeOverride;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('emit-struct-test-');
    // The skew read must never reach a real credential store from a test:
    // empty env + an empty machine home = unconfigured = silent.
    paletteSkewEnvOverride = const {};
    arxaHomeOverride = '${tmp.path}/.arxa';
  });

  tearDown(() {
    paletteSkewEnvOverride = null;
    arxaHomeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  // The app-shell roster every compliant fixture design declares (the
  // freeze-time law): surfaced entries + their viewmodels. `plant` merges
  // these in by default; pass `roster: false` to test the law itself.
  final appShellEntries = [
    {'id': 'app.splash', 'shell': 'app', 'comp': 'AppSplash', 'surface': 'app_shell_app_splash_view'},
    {'id': 'app.startup', 'shell': 'app', 'comp': 'AppStartup', 'surface': 'app_shell_app_startup_view'},
    {'id': 'app.unknown', 'shell': 'app', 'comp': 'AppUnknown', 'surface': 'app_shell_app_unknown_view'},
  ];
  final appShellVms = {
    'ui/views/app_shell/splash/splash_viewmodel.js': "export const surfaceId = 'app.splash';\n",
    'ui/views/app_shell/startup/startup_viewmodel.js': "export const surfaceId = 'app.startup';\n",
    'ui/views/app_shell/unknown/unknown_viewmodel.js': "export const surfaceId = 'app.unknown';\n",
  };

  void plant(String dir, String registry, String routes, Map<String, String> viewmodels,
      {bool roster = true}) {
    Directory('$dir/models/screens_model').createSync(recursive: true);
    final reg = jsonDecode(registry) as List;
    if (roster) {
      reg.addAll(appShellEntries.map((e) => jsonDecode(jsonEncode(e))));
    }
    File('$dir/models/screens_model/registry.json').writeAsStringSync(jsonEncode(reg));
    File('$dir/app.routes.js').writeAsStringSync(routes);
    final vms = {...viewmodels, if (roster) ...appShellVms};
    for (final entry in vms.entries) {
      final p = '$dir/${entry.key}';
      File(p).parent.createSync(recursive: true);
      File(p).writeAsStringSync(entry.value);
    }
  }

  // Shared fixtures
  final reg = jsonEncode([
    {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
    {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view'},
    {'id': 'proj.splash', 'shell': 'proj', 'comp': 'ProjSplash', 'surface': null},
  ]);
  const routes = "export default [['GET','/',home.page]];\n"
      "export const shellRoots = { proj: '/', stage: '/' };\n";
  const shellVm = "export const surfaceId = 'stage.shell';\n"
      "import {chrome} from '../../../services/facades/shell_facade.js';\n";
  const homeVm = "export const surfaceId = 'proj.home';\n"
      "import {list} from '../../../../../services/facades/project_facade.js';\n";

  test('happy path — join on surfaceId, exclusions preserved, deps captured', () async {
    final a = '${tmp.path}/a';
    plant(a, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });

    final rc = await emitStructure(a);
    expect(rc, 0, reason: 'registry root emits');

    final d = jsonDecode(File('$a/structure.json').readAsStringSync()) as Map<String, dynamic>;
    final screens = d['screens'] as List;
    expect(screens.length, 6, reason: 'all screens emitted, roster included (null NOT dropped)');

    final splash = screens.firstWhere((s) => (s as Map)['id'] == 'proj.splash') as Map<String, dynamic>;
    expect(splash['surface'], isNull, reason: 'surface:null preserved as the exclusion');
    expect(splash['viewmodel'], isNull);
    expect(splash['shellDir'], 'stage_shell', reason: 'excluded screen derives shellDir from group');

    final home = screens.firstWhere((s) => (s as Map)['id'] == 'proj.home') as Map<String, dynamic>;
    expect((home['viewmodel'] as String).endsWith('home_viewmodel.js'), isTrue);
    expect(home['deps'], contains('services/facades/project_facade.js'));

    expect(d['shellRoots'], {'proj': '/', 'stage': '/'});
    expect(d['registry'], 'models/screens_model/registry.json');
  });

  test('--check green in sync, RED on hand-edit', () async {
    final a = '${tmp.path}/a';
    plant(a, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });
    await emitStructure(a);

    expect(await emitStructure(a, check: true), 0, reason: '--check green when in sync');

    // Hand-edit
    final f = File('$a/structure.json');
    f.writeAsStringSync(f.readAsStringSync().replaceFirst('StageShell', 'StageShellX'));
    expect(await emitStructure(a, check: true), 1, reason: '--check RED on hand-edit');
  });

  test('missing surfaceId (declared surface, no viewmodel) fails', () async {
    final b = '${tmp.path}/b';
    plant(b, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      // Missing: home_viewmodel.js
    });
    expect(await emitStructure(b), 1, reason: 'missing surfaceId fails');
  });

  test('orphan viewmodel (unclaimed surfaceId) fails', () async {
    final c = '${tmp.path}/c';
    plant(c, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      'ui/views/stage_shell/ghost/ghost_viewmodel.js': "export const surfaceId = 'proj.ghost';\n",
    });
    expect(await emitStructure(c), 1, reason: 'orphan viewmodel fails');
  });

  test('empty shellRoots fails', () async {
    final e = '${tmp.path}/e';
    plant(e, reg, "export const shellRoots = {};\nexport default [];", {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });
    expect(await emitStructure(e), 1, reason: 'empty shellRoots fails');
  });

  test('viewmodel with no surfaceId fails', () async {
    final g = '${tmp.path}/g';
    plant(g, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': "export const page = () => {};\n",
    });
    expect(await emitStructure(g), 1, reason: 'viewmodel with no surfaceId fails');
  });

  test('v2 Map registry (stages/shells) derives screens from the authoring SSOT', () async {
    final a = '${tmp.path}/v2';
    Directory('$a/models/screens_model').createSync(recursive: true);
    File('$a/models/screens_model/registry.json').writeAsStringSync(jsonEncode({
      'app': 'studio',
      'stages': [
        {'id': 'startup', 'shell': 'studio_startup_shell', 'href': '/startup', 'enabled': true},
      ],
      'shells': [
        {'id': 'studio_startup_shell', 'kind': 'ceremony', 'views': ['studio_startup_view']},
      ],
    }));
    Directory('$a/intake').createSync(recursive: true);
    File('$a/intake/registry.json').writeAsStringSync(jsonEncode({
      'registryVersion': '1.0.0',
      'app': 'studio',
      'entries': [
        {
          'id': 'studio_startup_shell.startup',
          'shell': 'studio_startup_shell',
          'shellKind': 'ceremony',
          'role': 'startup',
          'label': 'Startup',
          'surface': 'studio_startup_view',
          'route': '/startup',
          'requiresAuth': false,
        },
        {
          'id': 'studio_startup_shell.splash',
          'shell': 'studio_startup_shell',
          'shellKind': 'ceremony',
          'role': 'splash',
          'label': 'Splash',
          'surface': 'studio_splash_view',
          'route': '/splash',
          'requiresAuth': false,
        },
        {
          'id': 'studio_unknown_shell.unknown',
          'shell': 'studio_unknown_shell',
          'shellKind': 'ceremony',
          'role': 'unknown',
          'label': 'Unknown',
          'surface': 'studio_unknown_view',
          'route': '/unknown',
          'requiresAuth': false,
        },
        {
          'id': 'studio_auth_shell.auth',
          'shell': 'studio_auth_shell',
          'shellKind': 'ceremony',
          'role': 'access',
          'label': 'Auth',
          'surface': 'studio_auth_view',
          'route': '/auth',
          'requiresAuth': false,
        },
        {
          'id': 'studio_intake_shell.intake',
          'shell': 'studio_intake_shell',
          'shellKind': 'working',
          'label': 'Intake',
          'surface': 'studio_intake_view',
          'route': '/intake',
          'requiresAuth': true,
        },
      ],
    }));
    File('$a/app.routes.js').writeAsStringSync(
        "export const shellRoots = { studio_startup_shell: '/startup', studio_intake_shell: '/intake' };\n"
        "export default [['GET','/startup',startup.view],['GET','/intake',intake.view]];\n");
    for (final vm in [
      'ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js|studio_startup',
      'ui/views/studio_startup_shell/splash/studio_splash_viewmodel.js|studio_splash',
      'ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js|studio_unknown',
      'ui/views/studio_auth_shell/studio_auth/studio_auth_viewmodel.js|studio_auth',
    ]) {
      final parts = vm.split('|');
      File('$a/${parts[0]}')
        ..createSync(recursive: true)
        ..writeAsStringSync("export const surfaceId = '${parts[1]}';\n");
    }
    File('$a/ui/views/studio_intake_shell/studio_intake/studio_intake_viewmodel.js')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          "export const surfaceId = 'studio_intake';\nimport {ctx} from '../../../../../services/studio_intake_services/facades/studio_intake_facade_service.js';\n");

    final rc = await emitStructure(a);
    expect(rc, 0, reason: 'v2 Map projection emits via the authoring SSOT');

    final d = jsonDecode(File('$a/structure.json').readAsStringSync()) as Map<String, dynamic>;
    final screens = d['screens'] as List;
    expect(screens.length, 5, reason: 'one screen per authoring entry');
    final startup = screens.firstWhere((s) => (s as Map)['id'] == 'studio_startup_shell.startup') as Map<String, dynamic>;
    expect(startup['surface'], 'studio_startup_view');
    expect(startup['viewmodel'], isNotNull, reason: 'joined on surfaceId');
    expect(startup['comp'], 'StudioStartup', reason: 'comp derived PascalCase from the surface');
    expect(d['shellRoots']['studio_startup_shell'], '/startup');
    // flows for a v2 design live at intake/flows.json, not models/screens_model/
    expect(d['flows'], isNull, reason: 'no flows authored -> key omitted');
  });

  test('failed run writes NO structure.json', () async {
    final c = '${tmp.path}/c';
    plant(c, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      'ui/views/stage_shell/ghost/ghost_viewmodel.js': "export const surfaceId = 'proj.ghost';\n",
    });
    await emitStructure(c); // fails (orphan)
    expect(File('$c/structure.json').existsSync(), isFalse,
        reason: 'failed run leaves no structure.json');
  });

  group('kits passthrough', () {
    // A design dir nested under a fake repo root carrying config/kit-registry.json
    // (+ the arxa.config.json marker findRepoRoot walks up for).
    String plantRepo(String name, String registry) {
      final repo = '${tmp.path}/$name';
      Directory('$repo/config').createSync(recursive: true);
      File('$repo/config/arxa.config.json').writeAsStringSync('{}');
      File('$repo/config/kit-registry.json').writeAsStringSync(jsonEncode({
        'kits': [
          {'dir': 'maps'},
          {'dir': 'payments'},
        ],
      }));
      final a = '$repo/design';
      plant(a, registry, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      return a;
    }

    Map<String, dynamic> screenOf(Map<String, dynamic> d, String id) =>
        (d['screens'] as List).firstWhere((s) => (s as Map)['id'] == id)
            as Map<String, dynamic>;

    test('kits pass through; absent -> key omitted; excluded screens unchanged', () async {
      final a = plantRepo('k1', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 'payments']},
        {'id': 'proj.splash', 'shell': 'proj', 'comp': 'ProjSplash', 'surface': null, 'kits': ['maps']},
      ]));
      expect(await emitStructure(a), 0);

      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(screenOf(d, 'proj.home')['kits'], ['maps', 'payments'],
          reason: 'declared kits pass through');
      expect(screenOf(d, 'stage.shell').containsKey('kits'), isFalse,
          reason: 'no kits declared -> key omitted (no empty arrays)');
      final splash = screenOf(d, 'proj.splash');
      expect(splash.containsKey('kits'), isFalse,
          reason: 'excluded screen keeps its shape (no kits emitted)');
      expect(splash['surface'], isNull);
      expect(splash['viewmodel'], isNull);

      expect(await emitStructure(a, check: true), 0,
          reason: '--check stays a pure regeneration-compare (green)');
    });

    test('unknown kit name -> hard fail naming the screen', () async {
      final a = plantRepo('k2', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 'crypto']},
      ]));
      expect(await emitStructure(a), 1, reason: 'unknown kit name fails');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    test('non-list kits -> hard fail', () async {
      final a = plantRepo('k3', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': 'maps'},
      ]));
      expect(await emitStructure(a), 1, reason: 'kits as a bare string fails');
    });

    test('wrong item type in kits -> hard fail', () async {
      final a = plantRepo('k4', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 7]},
      ]));
      expect(await emitStructure(a), 1, reason: 'non-string kit entry fails');
    });
  });

  // ---------------------------------------------- Slice 3: the two axes
  //
  // `states` is screen-level and CLOSED; `feedback` is edge-level. structure.json
  // is the contract the viewer reads, so both are validated HERE too — the
  // authored layer can be hand-edited without ever going through intake.
  group('states + feedback pass through to structure.json', () {
    void plantFlows(String dir, Object flows) {
      File('$dir/models/screens_model/flows.json').writeAsStringSync(jsonEncode(flows));
    }

    test('registry states and statesProvenance thread through to the screen', () async {
      final a = '${tmp.path}/s1';
      plant(
          a,
          jsonEncode([
            {
              'id': 'stage.shell',
              'shell': 'stage',
              'comp': 'StageShell',
              'surface': 'stage_shell_view',
            },
            {
              'id': 'proj.home',
              'shell': 'proj',
              'comp': 'ProjHome',
              'surface': 'stage_shell_proj_home_view',
              'states': ['loading', 'empty'],
              'statesProvenance': 'inferred',
            },
          ]),
          routes,
          {
            'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
            'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
          });
      expect(await emitStructure(a), 0);
      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      final screens = d['screens'] as List;
      final home = screens.firstWhere((s) => (s as Map)['id'] == 'proj.home') as Map;
      expect(home['states'], ['loading', 'empty']);
      expect(home['statesProvenance'], 'inferred');
      final shell =
          screens.firstWhere((s) => (s as Map)['id'] == 'stage.shell') as Map;
      expect(shell.containsKey('states'), isFalse,
          reason: 'no states declared -> no key (additive only)');
    });

    test('an out-of-vocabulary state is a hard fail naming the allowed set', () async {
      final a = '${tmp.path}/s2';
      plant(
          a,
          jsonEncode([
            {
              'id': 'stage.shell',
              'shell': 'stage',
              'comp': 'StageShell',
              'surface': 'stage_shell_view',
              'states': ['skeleton'],
            },
          ]),
          routes,
          {'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm});
      expect(await emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse,
          reason: 'a hard fail writes nothing');
    });

    test('a well-formed edge feedback threads through verbatim', () async {
      final a = '${tmp.path}/s3';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      final flows = [
        {
          'id': 'flow-main',
          'edges': [
            {
              'from': 'proj.home',
              'to': 'stage.shell',
              'trigger': 'Place order',
              'feedback': {'kind': 'success', 'text': 'Order placed'},
            },
          ],
        },
      ];
      plantFlows(a, flows);
      expect(await emitStructure(a), 0);
      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d['flows'], flows);
    });

    test('a feedback.kind outside the enum is a hard fail', () async {
      final a = '${tmp.path}/s4';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      plantFlows(a, [
        {
          'id': 'flow-main',
          'edges': [
            {
              'from': 'proj.home',
              'to': 'stage.shell',
              'trigger': 'Place order',
              'feedback': {'kind': 'warning', 'text': 'Hmm'},
            },
          ],
        },
      ]);
      expect(await emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    test('feedback on a SCREEN is a hard fail — it is an edge key', () async {
      final a = '${tmp.path}/s5';
      plant(
          a,
          jsonEncode([
            {
              'id': 'stage.shell',
              'shell': 'stage',
              'comp': 'StageShell',
              'surface': 'stage_shell_view',
              'feedback': {'kind': 'success', 'text': 'Saved'},
            },
          ]),
          routes,
          {'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm});
      expect(await emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse);
    });
  });

  group('flows passthrough', () {
    void plantFlows(String dir, Object flows) {
      File('$dir/models/screens_model/flows.json').writeAsStringSync(jsonEncode(flows));
    }

    test('absent flows.json -> no flows key; present -> threaded verbatim', () async {
      final a = '${tmp.path}/f1';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      expect(await emitStructure(a), 0);
      var d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d.containsKey('flows'), isFalse,
          reason: 'no flows.json -> no flows lens (key omitted, not empty)');

      final flows = [
        {
          'id': 'flow-main',
          'name': 'Main journey',
          'edges': [
            {'from': 'proj.home', 'to': 'stage.shell', 'trigger': 'Open'},
            {'from': 'stage.shell', 'to': 'proj.splash', 'trigger': 'Leave'},
          ],
        },
      ];
      plantFlows(a, flows);
      expect(await emitStructure(a), 0);
      d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d['flows'], flows,
          reason: 'flows thread through verbatim (surface:null endpoints allowed)');
      expect(await emitStructure(a, check: true), 0,
          reason: '--check stays green with flows threaded');
    });

    test('edge endpoint not in the registry -> hard fail, no structure.json', () async {
      final a = '${tmp.path}/f2';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      plantFlows(a, [
        {
          'id': 'flow-ghost',
          'edges': [
            {'from': 'proj.home', 'to': 'proj.ghost', 'trigger': 'Boom'},
          ],
        },
      ]);
      expect(await emitStructure(a), 1, reason: 'unresolved edge endpoint fails');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });
  });

  // ---------------------------------------------- the app-shell roster law
  //
  // Every frozen design declares app.splash / app.startup / app.unknown in its
  // app-level shell; app.access joins the roster iff any surface carries
  // requiresAuth. These plants carry ONLY the app shell (roster: false) so a
  // failure is attributable to the roster and nothing else.
  group('app-shell roster law', () {
    Map<String, Object?> rosterEntry(String id, {bool nullSurface = false}) {
      final short = id.split('.').last;
      return {
        'id': id,
        'shell': 'app',
        'comp': 'App${short[0].toUpperCase()}${short.substring(1)}',
        'surface': nullSurface ? null : 'app_shell_${id.replaceAll('.', '_')}_view',
      };
    }

    void plantAppShell(String dir, List<Map<String, Object?>> entries) {
      plant(
        dir,
        jsonEncode(entries),
        routes,
        {
          for (final e in entries)
            if (e['surface'] != null)
              'ui/views/app_shell/${e['id']}/${(e['id'] as String).split('.').last}_viewmodel.js':
                  "export const surfaceId = '${e['id']}';\n",
        },
        roster: false,
      );
    }

    const trio = ['app.splash', 'app.startup', 'app.unknown'];

    test('a compliant roster passes (requiresAuth: false pulls nothing)', () async {
      final a = '${tmp.path}/r0';
      plantAppShell(a, [
        for (final id in trio) rosterEntry(id),
        {...rosterEntry('app.home'), 'requiresAuth': false},
      ]);
      expect(await emitStructure(a), 0, reason: 'full roster, no requiresAuth -> green');
    });

    for (final missing in trio) {
      test('missing $missing fails the freeze, writes nothing', () async {
        final a = '${tmp.path}/r-no-${missing.split('.').last}';
        plantAppShell(a, [
          for (final id in trio)
            if (id != missing) rosterEntry(id),
        ]);
        expect(await emitStructure(a), 1, reason: 'roster is hard-required');
        expect(File('$a/structure.json').existsSync(), isFalse);
      });
    }

    test('requiresAuth pulls app.access into the roster — both directions', () async {
      final dash = {...rosterEntry('app.dashboard'), 'requiresAuth': true};

      final noAccess = '${tmp.path}/r-auth-noaccess';
      plantAppShell(noAccess, [for (final id in trio) rosterEntry(id), dash]);
      expect(await emitStructure(noAccess), 1,
          reason: 'requiresAuth with no app.access fails');
      expect(File('$noAccess/structure.json').existsSync(), isFalse);

      final withAccess = '${tmp.path}/r-auth-access';
      plantAppShell(withAccess,
          [for (final id in trio) rosterEntry(id), dash, rosterEntry('app.access')]);
      expect(await emitStructure(withAccess), 0,
          reason: 'app.access satisfies the conditional roster');
    });

    test('a surface:null roster entry does not satisfy the law', () async {
      final a = '${tmp.path}/r-null';
      plantAppShell(a, [
        rosterEntry('app.splash'),
        rosterEntry('app.startup'),
        rosterEntry('app.unknown', nullSurface: true),
      ]);
      expect(await emitStructure(a), 1,
          reason: 'an excluded app.unknown routes to nothing');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    // Role mapping (canon amended 2026-08-12, grill D2): a non-app.* shell
    // fills roster roles with per-entry `role` fields — studio-v2's shape.
    Map<String, Object?> roleEntry(String id, String role,
        {bool nullSurface = false}) {
      final short = id.split('.').last;
      return {
        'id': id,
        'role': role,
        'shell': id.split('.').first,
        'comp': 'Studio${short[0].toUpperCase()}${short.substring(1)}',
        'surface':
            nullSurface ? null : 'studio_shell_${id.replaceAll('.', '_')}_view',
      };
    }

    test('per-entry role fields fill the roster without app.* ids', () async {
      final a = '${tmp.path}/r-roles';
      plantAppShell(a, [
        roleEntry('studio_startup.splash', 'splash'),
        roleEntry('studio_startup.home', 'startup'),
        roleEntry('studio_unknown.lost', 'unknown'),
      ]);
      expect(await emitStructure(a), 0,
          reason: 'role declarations satisfy the roster law via mapping');
    });

    test('a surface:null entry does not fill its declared role', () async {
      final a = '${tmp.path}/r-roles-null';
      plantAppShell(a, [
        roleEntry('studio_startup.splash', 'splash', nullSurface: true),
        roleEntry('studio_startup.home', 'startup'),
        roleEntry('studio_unknown.lost', 'unknown'),
      ]);
      expect(await emitStructure(a), 1,
          reason: 'an excluded splash routes to nothing, role or not');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    test('requiresAuth pulls the access role; a role field satisfies it', () async {
      final a = '${tmp.path}/r-roles-access';
      plantAppShell(a, [
        roleEntry('studio_startup.splash', 'splash'),
        roleEntry('studio_startup.home', 'startup'),
        roleEntry('studio_unknown.lost', 'unknown'),
        {
          ...roleEntry('studio_auth.signin', 'access'),
          'requiresAuth': false,
        },
        {...roleEntry('studio_design.canvas', ''), 'requiresAuth': true}
          ..remove('role'),
      ]);
      expect(await emitStructure(a), 0,
          reason: 'role: access fills the conditional roster slot');
    });
  });

  // ------------------------------------------- palette plane (Q8)
  group('palette plane (Q8)', () {
    const palettesJson = '{\n'
        '  "version": 1,\n'
        '  "comment": "Palette plane declaration (VERIFY ADDENDUM 17).",\n'
        '  "default": "marine",\n'
        '  "palettes": [\n'
        '    {"id": "marine", "name": "Marine Blue", "swatch": ["#ccdbdc", "#9ad1d4", "#80ced7", "#007ea7", "#003249"], "themeColor": "#007EA7", "seeded": true},\n'
        '    {"id": "c-6f58c9", "name": "Lavender Iris", "swatch": ["#bdede0", "#bbdbd1", "#b6b8d6", "#7e78d2", "#6f58c9"], "themeColor": "#7e78d2", "seeded": true, "provenance": "fixture-extra"}\n'
        '  ]\n'
        '}\n';

    String plantPlane(String name, {String? palettes, bool marker = false}) {
      final a = '${tmp.path}/$name';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      if (palettes != null) {
        File('$a/palettes.json').writeAsStringSync(palettes);
      }
      if (marker) {
        File('$a/arxa.json').writeAsStringSync(
            jsonEncode({'name': 'fixture-project', 'kind': 'app'}));
      }
      return a;
    }

    test('a valid palettes.json threads VERBATIM into structure.json', () async {
      final a = plantPlane('p1', palettes: palettesJson);
      expect(await emitStructure(a), 0);

      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      final block = d['palettes'] as Map<String, dynamic>;
      expect(block['default'], 'marine');
      final entries = block['palettes'] as List;
      expect(entries.length, 2);
      final marine = entries[0] as Map<String, dynamic>;
      expect(marine['swatch'],
          ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249']);
      expect((entries[1] as Map)['provenance'], 'fixture-extra',
          reason: 'unknown entry keys ride through — verbatim, not re-serialized');
      expect(block.containsKey('version'), isFalse,
          reason: 'the block is {default, palettes} — manifest bookkeeping stays in the design dir');
      expect(block.containsKey('comment'), isFalse);
      expect(await emitStructure(a, check: true), 0,
          reason: '--check stays a pure regeneration-compare with the plane aboard');
    });

    test('no palettes.json -> no palettes key (pre-law artifact)', () async {
      final a = plantPlane('p2');
      expect(await emitStructure(a), 0);
      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d.containsKey('palettes'), isFalse,
          reason: 'absent = no plane; valid for pre-law artifacts');
    });

    test('an unparsable palettes.json threads nothing and never fails the freeze', () async {
      final a = plantPlane('p3', palettes: '{"default": 7, "palettes": []}');
      expect(await emitStructure(a), 0,
          reason: 'a broken declaration disables the axis, never guesses');
      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d.containsKey('palettes'), isFalse,
          reason: 'gate_design_palettes (P1) owns naming the malformed file');
    });

    test('paletteSkewLine is quiet on agreement or the unknown', () {
      expect(paletteSkewLine(published: null, manifestDefault: 'marine'), isNull);
      expect(paletteSkewLine(published: '', manifestDefault: 'marine'), isNull);
      expect(paletteSkewLine(published: 'marine', manifestDefault: 'marine'), isNull);
      expect(paletteSkewLine(published: 'c-6f58c9', manifestDefault: 'marine'),
          'published is c-6f58c9, manifest default is marine — the scaffold '
          'ships marine; update palettes.json or publish marine to change that.');
    });

    test('fires the advisory when the published pick disagrees', () async {
      final a = plantPlane('p4', palettes: palettesJson, marker: true);
      final lines = <String>[];
      await warnPaletteSkew(a,
          env: const {
            'ARXA_SUPABASE_URL': 'https://fixture.supabase.co',
            'ARXA_SUPABASE_SERVICE_KEY': 'service-key',
          },
          readPublished: (url, key, project, artifact) async {
            expect(project, 'fixture-project',
                reason: 'the arxa.json marker names the project dimension');
            expect(artifact, 'p4',
                reason: 'artifact = the design dir basename (design_server)');
            return 'c-6f58c9';
          },
          out: lines.add);
      expect(lines, [
        'published is c-6f58c9, manifest default is marine — the scaffold '
            'ships marine; update palettes.json or publish marine to change that.',
      ]);
    });

    test('suppressed when unconfigured — no credentials, no read attempted', () async {
      final a = plantPlane('p5', palettes: palettesJson, marker: true);
      final lines = <String>[];
      var attempted = false;
      await warnPaletteSkew(a,
          env: const {},
          readPublished: (url, key, project, artifact) async {
            attempted = true;
            return 'c-6f58c9';
          },
          out: lines.add);
      expect(attempted, isFalse, reason: 'unconfigured = no store read at all');
      expect(lines, isEmpty);
    });

    test('suppressed without an arxa.json marker — no store identity', () async {
      final a = plantPlane('p6', palettes: palettesJson);
      var attempted = false;
      await warnPaletteSkew(a,
          env: const {
            'ARXA_SUPABASE_URL': 'https://fixture.supabase.co',
            'ARXA_SUPABASE_SERVICE_KEY': 'service-key',
          },
          readPublished: (url, key, project, artifact) async {
            attempted = true;
            return 'c-6f58c9';
          },
          out: (_) {});
      expect(attempted, isFalse);
    });

    test('the credentials file fills when the env is absent', () async {
      final a = plantPlane('p7', palettes: palettesJson, marker: true);
      Directory('${tmp.path}/.arxa').createSync(recursive: true);
      File('${tmp.path}/.arxa/supabase').writeAsStringSync(
          '# machine credentials\nurl=https://file.supabase.co\nservice_key=file-key\n');
      final lines = <String>[];
      await warnPaletteSkew(a,
          env: const {},
          readPublished: (url, key, project, artifact) async {
            expect(url, 'https://file.supabase.co');
            expect(key, 'file-key');
            return 'c-6f58c9';
          },
          out: lines.add);
      expect(lines.length, 1, reason: 'file credentials configured -> the read runs');
    });

    test('a failing store read is swallowed — advisory never blocks', () async {
      final a = plantPlane('p8', palettes: palettesJson, marker: true);
      final lines = <String>[];
      await warnPaletteSkew(a,
          env: const {
            'ARXA_SUPABASE_URL': 'https://fixture.supabase.co',
            'ARXA_SUPABASE_SERVICE_KEY': 'service-key',
          },
          readPublished: (url, key, project, artifact) async =>
              throw const HttpException('offline'),
          out: lines.add);
      expect(lines, isEmpty);
    });

    test('the freeze write path runs the skew read; --check never touches the store', () async {
      final a = plantPlane('p9', palettes: palettesJson, marker: true);
      var reads = 0;
      paletteSkewEnvOverride = const {
        'ARXA_SUPABASE_URL': 'https://fixture.supabase.co',
        'ARXA_SUPABASE_SERVICE_KEY': 'service-key',
      };
      paletteSkewReaderOverride = (url, key, project, artifact) async {
        reads++;
        return 'c-6f58c9';
      };
      try {
        expect(await emitStructure(a), 0,
            reason: 'the advisory never blocks the freeze');
        expect(reads, 1, reason: 'the write path performs one best-effort read');
        expect(await emitStructure(a, check: true), 0);
        expect(reads, 1, reason: '--check stays hermetic — no network');
      } finally {
        paletteSkewReaderOverride = null;
      }
    });
  });
}
