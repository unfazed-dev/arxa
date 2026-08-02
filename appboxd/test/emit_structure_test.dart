// emit_structure test — ports the Python self-test's 7 discriminating cases.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/emit_structure.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('emit-struct-test-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  void plant(String dir, String registry, String routes, Map<String, String> viewmodels) {
    Directory('$dir/models/screens_model').createSync(recursive: true);
    File('$dir/models/screens_model/registry.json').writeAsStringSync(registry);
    File('$dir/app.routes.js').writeAsStringSync(routes);
    for (final entry in viewmodels.entries) {
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

  test('happy path — join on surfaceId, exclusions preserved, deps captured', () {
    final a = '${tmp.path}/a';
    plant(a, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });

    final rc = emitStructure(a);
    expect(rc, 0, reason: 'registry root emits');

    final d = jsonDecode(File('$a/structure.json').readAsStringSync()) as Map<String, dynamic>;
    final screens = d['screens'] as List;
    expect(screens.length, 3, reason: 'all three screens emitted (null NOT dropped)');

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

  test('--check green in sync, RED on hand-edit', () {
    final a = '${tmp.path}/a';
    plant(a, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });
    emitStructure(a);

    expect(emitStructure(a, check: true), 0, reason: '--check green when in sync');

    // Hand-edit
    final f = File('$a/structure.json');
    f.writeAsStringSync(f.readAsStringSync().replaceFirst('StageShell', 'StageShellX'));
    expect(emitStructure(a, check: true), 1, reason: '--check RED on hand-edit');
  });

  test('missing surfaceId (declared surface, no viewmodel) fails', () {
    final b = '${tmp.path}/b';
    plant(b, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      // Missing: home_viewmodel.js
    });
    expect(emitStructure(b), 1, reason: 'missing surfaceId fails');
  });

  test('orphan viewmodel (unclaimed surfaceId) fails', () {
    final c = '${tmp.path}/c';
    plant(c, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      'ui/views/stage_shell/ghost/ghost_viewmodel.js': "export const surfaceId = 'proj.ghost';\n",
    });
    expect(emitStructure(c), 1, reason: 'orphan viewmodel fails');
  });

  test('empty shellRoots fails', () {
    final e = '${tmp.path}/e';
    plant(e, reg, "export const shellRoots = {};\nexport default [];", {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
    });
    expect(emitStructure(e), 1, reason: 'empty shellRoots fails');
  });

  test('viewmodel with no surfaceId fails', () {
    final g = '${tmp.path}/g';
    plant(g, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': "export const page = () => {};\n",
    });
    expect(emitStructure(g), 1, reason: 'viewmodel with no surfaceId fails');
  });

  test('failed run writes NO structure.json', () {
    final c = '${tmp.path}/c';
    plant(c, reg, routes, {
      'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
      'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      'ui/views/stage_shell/ghost/ghost_viewmodel.js': "export const surfaceId = 'proj.ghost';\n",
    });
    emitStructure(c); // fails (orphan)
    expect(File('$c/structure.json').existsSync(), isFalse,
        reason: 'failed run leaves no structure.json');
  });

  group('kits passthrough', () {
    // A design dir nested under a fake repo root carrying config/kit-registry.json
    // (+ the appbox.config.json marker findRepoRoot walks up for).
    String plantRepo(String name, String registry) {
      final repo = '${tmp.path}/$name';
      Directory('$repo/config').createSync(recursive: true);
      File('$repo/config/appbox.config.json').writeAsStringSync('{}');
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

    test('kits pass through; absent -> key omitted; excluded screens unchanged', () {
      final a = plantRepo('k1', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 'payments']},
        {'id': 'proj.splash', 'shell': 'proj', 'comp': 'ProjSplash', 'surface': null, 'kits': ['maps']},
      ]));
      expect(emitStructure(a), 0);

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

      expect(emitStructure(a, check: true), 0,
          reason: '--check stays a pure regeneration-compare (green)');
    });

    test('unknown kit name -> hard fail naming the screen', () {
      final a = plantRepo('k2', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 'crypto']},
      ]));
      expect(emitStructure(a), 1, reason: 'unknown kit name fails');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    test('non-list kits -> hard fail', () {
      final a = plantRepo('k3', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': 'maps'},
      ]));
      expect(emitStructure(a), 1, reason: 'kits as a bare string fails');
    });

    test('wrong item type in kits -> hard fail', () {
      final a = plantRepo('k4', jsonEncode([
        {'id': 'stage.shell', 'shell': 'stage', 'comp': 'StageShell', 'surface': 'stage_shell_view'},
        {'id': 'proj.home', 'shell': 'proj', 'comp': 'ProjHome', 'surface': 'stage_shell_proj_home_view', 'kits': ['maps', 7]},
      ]));
      expect(emitStructure(a), 1, reason: 'non-string kit entry fails');
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

    test('registry states and statesProvenance thread through to the screen', () {
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
      expect(emitStructure(a), 0);
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

    test('an out-of-vocabulary state is a hard fail naming the allowed set', () {
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
      expect(emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse,
          reason: 'a hard fail writes nothing');
    });

    test('a well-formed edge feedback threads through verbatim', () {
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
      expect(emitStructure(a), 0);
      final d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d['flows'], flows);
    });

    test('a feedback.kind outside the enum is a hard fail', () {
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
      expect(emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse);
    });

    test('feedback on a SCREEN is a hard fail — it is an edge key', () {
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
      expect(emitStructure(a), isNot(0));
      expect(File('$a/structure.json').existsSync(), isFalse);
    });
  });

  group('flows passthrough', () {
    void plantFlows(String dir, Object flows) {
      File('$dir/models/screens_model/flows.json').writeAsStringSync(jsonEncode(flows));
    }

    test('absent flows.json -> no flows key; present -> threaded verbatim', () {
      final a = '${tmp.path}/f1';
      plant(a, reg, routes, {
        'ui/views/stage_shell/stage_shell_viewmodel.js': shellVm,
        'ui/views/stage_shell/proj/home/home_viewmodel.js': homeVm,
      });
      expect(emitStructure(a), 0);
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
      expect(emitStructure(a), 0);
      d = jsonDecode(File('$a/structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(d['flows'], flows,
          reason: 'flows thread through verbatim (surface:null endpoints allowed)');
      expect(emitStructure(a, check: true), 0,
          reason: '--check stays green with flows threaded');
    });

    test('edge endpoint not in the registry -> hard fail, no structure.json', () {
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
      expect(emitStructure(a), 1, reason: 'unresolved edge endpoint fails');
      expect(File('$a/structure.json').existsSync(), isFalse);
    });
  });
}
