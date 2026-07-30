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
}
