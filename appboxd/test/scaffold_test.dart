// scaffold test — ports the Python self-test's ~50 discriminating cases.
//
// Ports skills/appbox-scaffolder/scaffold.py `_self_test` to package:test in a
// temp app root. Asserts the §16 invariant: form factors FOLLOW targets, so a
// macos target never emits an empty .mobile/.tablet.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/scaffold.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String derivationPath;
  late String configPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scaffold-test-');
    derivationPath = '${tmp.path}/targets.derivation.json';
    File(derivationPath).writeAsStringSync(_derivationJson);
    configPath = '${tmp.path}/appbox.config.json';
    File(configPath).writeAsStringSync(_configJson);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // 3 frozen + 1 excluded (surface:null). Mirrors the Python self-test's
  // stage_shell shape; all three frozen surfaces share shellDir 'stage_shell'.
  Map<String, dynamic> baseStruct() => {
        r'$schema': 'appbox/structure@1',
        'registry': 'models/screens_model/registry.json',
        'shellRoots': {'projects': '/', 'settings': '/settings'},
        'screens': [
          {
            'id': 'stage.shell',
            'shell': 'stage',
            'comp': 'StageShell',
            'shellDir': 'stage_shell',
            'surface': 'stage_shell_view',
            'viewmodel': 'ui/views/stage_shell/stage_shell_viewmodel.js',
            'deps': ['services/facades/shell_facade.js'],
          },
          {
            'id': 'projects.home',
            'shell': 'projects',
            'comp': 'ProjectsHome',
            'shellDir': 'stage_shell',
            'surface': 'stage_shell_projects_home_view',
            'viewmodel': 'ui/views/stage_shell/projects/home/home_viewmodel.js',
            'deps': ['services/facades/project_facade.js'],
          },
          {
            'id': 'settings.kits',
            'shell': 'settings',
            'comp': 'SettingsKits',
            'shellDir': 'stage_shell',
            'surface': 'stage_shell_settings_kits_view',
            'viewmodel': 'ui/views/stage_shell/settings/kits/kits_viewmodel.js',
            'deps': ['services/facades/shell_facade.js'],
          },
          {
            'id': 'projects.splash',
            'shell': 'projects',
            'comp': 'ProjectsSplash',
            'shellDir': 'stage_shell',
            'surface': null,
            'viewmodel': null,
            'deps': <String>[],
          },
        ],
      };

  /// Write a design dir with [struct] (+ optional l10n catalogs) under
  /// [parent]/design and return its path.
  String plantDesign(String parent,
      {Map<String, dynamic>? struct, Map<String, String>? l10n}) {
    final dir = '$parent/design';
    Directory(dir).createSync(recursive: true);
    File('$dir/structure.json')
        .writeAsStringSync(jsonEncode(struct ?? baseStruct()));
    if (l10n != null) {
      final ldir = '$dir/l10n';
      Directory(ldir).createSync(recursive: true);
      for (final e in l10n.entries) {
        File('$ldir/${e.key}').writeAsStringSync(e.value);
      }
    }
    return dir;
  }

  Map<String, dynamic> clone(Map<String, dynamic> s) =>
      jsonDecode(jsonEncode(s)) as Map<String, dynamic>;

  group('deriveFactors (P06): targets -> viewports', () {
    test('macos -> [desktop] only', () {
      expect(deriveFactors(['macos'], derivationPath, configPath), ['desktop']);
    });

    test('ios,android -> [mobile, tablet]', () {
      expect(deriveFactors(['ios', 'android'], derivationPath, configPath),
          ['mobile', 'tablet']);
    });

    test('web -> [mobile, tablet, desktop]', () {
      expect(deriveFactors(['web'], derivationPath, configPath),
          ['mobile', 'tablet', 'desktop']);
    });

    test('android alone -> [mobile, tablet], no desktop', () {
      expect(deriveFactors(['android'], derivationPath, configPath),
          ['mobile', 'tablet']);
    });

    test('pwa inherits web -> all three factors', () {
      expect(deriveFactors(['pwa'], derivationPath, configPath),
          ['mobile', 'tablet', 'desktop']);
    });

    test('unknown target -> throws naming it', () {
      expect(
          () => deriveFactors(['zxspectrum'], derivationPath, configPath),
          throwsA(isA<FormatException>()));
    });
  });

  group('macos scaffold -> [desktop] -> 3 files/surface', () {
    test('emits exit 0 with the right file set, no empty factors', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      final rc = scaffold(des, app, ['macos'], derivationPath, configPath);
      expect(rc, 0, reason: 'macos scaffold emits (exit 0)');

      for (final entry in [
        ['stage.shell', 'stage_shell'],
        ['projects.home', 'projects_home'],
        ['settings.kits', 'settings_kits'],
      ]) {
        final d = entry[1];
        final base = '$app/lib/ui/views/stage_shell/$d';
        expect(File('$base/${d}_view.dart').existsSync(), isTrue,
            reason: '$d: base _view.dart exists');
        expect(File('$base/${d}_view.desktop.dart').existsSync(), isTrue,
            reason: '$d: desktop factor exists');
        expect(File('$base/${d}_viewmodel.dart').existsSync(), isTrue,
            reason: '$d: viewmodel exists');
        // §16: NO empty .mobile/.tablet for a macos target
        expect(File('$base/${d}_view.mobile.dart').existsSync(), isFalse,
            reason: '$d: no empty .mobile.dart (§16 stale-green guard)');
        expect(File('$base/${d}_view.tablet.dart').existsSync(), isFalse,
            reason: '$d: no empty .tablet.dart (§16 stale-green guard)');
      }

      // excluded surface (surface:null) is NOT scaffolded
      expect(Directory('$app/lib/ui/views/stage_shell/projects_splash').existsSync(),
          isFalse,
          reason: 'excluded surface (surface:null) not scaffolded');
    });

    test('manifest shape: selfContained, surfaces, factors, targets', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      final mf = jsonDecode(
          File('$app/lib/ui/views/.shell-structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(mf['selfContained'], ['stage_shell']);
      expect(mf['surfaces']['stage_shell']['stage_shell_projects_home_view'],
          'projects_home');
      expect((mf['surfaces']['stage_shell'] as Map).length, 3);
      expect(mf['factors'], ['desktop']);
      expect(mf['targets'], ['macos']);
    });

    test('shell-level design-system.md + *_chrome.dart', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      final sh = '$app/lib/ui/views/stage_shell';
      expect(File('$sh/design-system.md').existsSync(), isTrue,
          reason: 'shell-level design-system.md emitted');
      final ds = File('$sh/design-system.md').readAsStringSync();
      expect(ds.contains('## Palette') && ds.contains('KitColors'), isTrue,
          reason: 'shell design-system.md carries Palette + KitColors (S4)');
      expect(File('$sh/stage_shell_chrome.dart').existsSync(), isTrue,
          reason: 'shell *_chrome.dart emitted (S6)');
    });

    test('class-name contents: StackedView<..ViewModel>, BaseViewModel', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      final base = '$app/lib/ui/views/stage_shell/projects_home';
      final view = File('$base/projects_home_view.dart').readAsStringSync();
      expect(
          view.contains(
              'class ProjectsHomeView extends StackedView<ProjectsHomeViewModel>'),
          isTrue);
      final vm =
          File('$base/projects_home_viewmodel.dart').readAsStringSync();
      expect(vm.contains('class ProjectsHomeViewModel extends BaseViewModel'),
          isTrue);
    });
  });

  group('ios,android -> [mobile, tablet] -> 4 dart files + design-system.md', () {
    test('5 files/surface, mobile+tablet present, no desktop', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app2';
      final rc =
          scaffold(des, app, ['ios', 'android'], derivationPath, configPath);
      expect(rc, 0);
      final base = '$app/lib/ui/views/stage_shell/projects_home';
      expect(File('$base/projects_home_view.mobile.dart').existsSync(), isTrue);
      expect(File('$base/projects_home_view.tablet.dart').existsSync(), isTrue);
      expect(File('$base/projects_home_view.desktop.dart').existsSync(), isFalse);
      final got = Directory(base)
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList()
        ..sort();
      expect(got.length, 5, reason: 'ios,android: 5 files/surface (got $got)');
      expect(File('$base/design-system.md').existsSync(), isTrue);
    });
  });

  group('web -> [mobile, tablet, desktop] -> 6 files/surface', () {
    test('all three factors + base + viewmodel + design-system.md', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app3';
      final rc = scaffold(des, app, ['web'], derivationPath, configPath);
      expect(rc, 0);
      final base = '$app/lib/ui/views/stage_shell/projects_home';
      for (final f in ['mobile', 'tablet', 'desktop']) {
        expect(File('$base/projects_home_view.$f.dart').existsSync(), isTrue,
            reason: 'web: $f factor exists');
      }
      final got = Directory(base)
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList()
        ..sort();
      expect(got.length, 6, reason: 'web: 6 files/surface (got $got)');
      final mf = jsonDecode(File(
              '$app/lib/ui/views/.shell-structure.json')
          .readAsStringSync()) as Map<String, dynamic>;
      expect(mf['factors'], ['mobile', 'tablet', 'desktop']);
    });
  });

  group('negatives (R5)', () {
    test('missing structure.json -> exit 1', () {
      final empty = '${tmp.path}/empty';
      Directory(empty).createSync(recursive: true);
      final rc = scaffold(empty, '${tmp.path}/appE', ['macos'],
          derivationPath, configPath);
      expect(rc, 1);
    });

    test('surface with no viewmodel -> exit 1', () {
      final bad = clone(baseStruct());
      (bad['screens'] as List)[1]['viewmodel'] = null; // projects.home
      final des = plantDesign('${tmp.path}/bd', struct: bad);
      final rc =
          scaffold(des, '${tmp.path}/appB', ['macos'], derivationPath, configPath);
      expect(rc, 1);
    });

    test('unknown target -> exit 1', () {
      final des = plantDesign('${tmp.path}/d');
      final rc = scaffold(des, '${tmp.path}/appU', ['zxspectrum'],
          derivationPath, configPath);
      expect(rc, 1);
    });

    test('dir collision (two surfaces, same <shell>_<short>) -> exit 1', () {
      final coll = clone(baseStruct());
      (coll['screens'] as List).add({
        'id': 'projects.home',
        'shell': 'projects',
        'comp': 'ProjectsHome2',
        'shellDir': 'stage_shell',
        'surface': 'stage_shell_projects_home_2_view',
        'viewmodel': 'ui/views/x.js',
        'deps': <String>[],
      });
      final des = plantDesign('${tmp.path}/cd', struct: coll);
      final rc =
          scaffold(des, '${tmp.path}/appC', ['macos'], derivationPath, configPath);
      expect(rc, 1);
    });
  });

  group('--check drift mode', () {
    test('wrong file count -> --check exit 1, restore -> green', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      scaffold(des, app, ['macos'], derivationPath, configPath);

      final missing =
          '$app/lib/ui/views/stage_shell/projects_home/projects_home_view.desktop.dart';
      File(missing).deleteSync();
      expect(
          scaffold(des, app, ['macos'], derivationPath, configPath,
              check: true),
          1,
          reason: 'wrong file count -> --check exit 1');

      File(missing).writeAsStringSync('// restored');
      expect(
          scaffold(des, app, ['macos'], derivationPath, configPath,
              check: true),
          0,
          reason: '--check green again after restoring the file');
    });
  });

  group('l10n backward compat', () {
    test('no l10n/ in design -> no lib/l10n, no l10n.yaml, manifest has no key', () {
      final des = plantDesign('${tmp.path}/d');
      final app = '${tmp.path}/app1';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      expect(Directory('$app/lib/l10n').existsSync(), isFalse);
      expect(File('$app/l10n.yaml').existsSync(), isFalse);
      final mf = jsonDecode(
          File('$app/lib/ui/views/.shell-structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(mf.containsKey('l10n'), isFalse);
    });
  });

  group('l10n layer', () {
    test('design with l10n/ -> catalogs copied, l10n.yaml, manifest records', () {
      final des = plantDesign('${tmp.path}/ld', l10n: {
        'app_en.arb': '{"appTitle": "Demo"}',
        'app_pl.arb': '{"appTitle": "Demo pl"}',
      });
      final app = '${tmp.path}/appL';
      final rc = scaffold(des, app, ['macos'], derivationPath, configPath);
      expect(rc, 0);
      expect(File('$app/lib/l10n/app_en.arb').readAsStringSync(),
          '{"appTitle": "Demo"}',
          reason: 'app_en.arb copied verbatim');
      expect(File('$app/lib/l10n/app_pl.arb').existsSync(), isTrue);
      expect(File('$app/l10n.yaml').readAsStringSync(), l10nYaml,
          reason: 'l10n.yaml matches the fixed contract verbatim');
      final mf = jsonDecode(
              File('$app/lib/ui/views/.shell-structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(mf['l10n'], {'arbDir': 'lib/l10n', 'locales': ['en', 'pl']});
      expect(
          scaffold(des, app, ['macos'], derivationPath, configPath, check: true),
          0,
          reason: 'l10n design --check green');
    });

    test('deleted catalog -> --check exit 1', () {
      final des = plantDesign('${tmp.path}/ld', l10n: {
        'app_en.arb': '{"appTitle": "Demo"}',
        'app_pl.arb': '{"appTitle": "Demo pl"}',
      });
      final app = '${tmp.path}/appL2';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      File('$app/lib/l10n/app_pl.arb').deleteSync();
      expect(
          scaffold(des, app, ['macos'], derivationPath, configPath, check: true),
          1,
          reason: 'deleted lib/l10n/app_pl.arb -> --check exit 1');
    });

    test('l10n/ without app_en.arb -> exit 1', () {
      final des = plantDesign('${tmp.path}/bdl', l10n: {
        'app_pl.arb': '{}',
      });
      final rc =
          scaffold(des, '${tmp.path}/appBL', ['macos'], derivationPath, configPath);
      expect(rc, 1);
    });
  });

  group('kits', () {
    Map<String, dynamic> kitsStruct() {
      final s = clone(baseStruct());
      (s['screens'] as List)[1]['kits'] = ['maps', 'payments']; // projects.home
      return s;
    }

    test('stub headers carry the kits line; surfaces without kits do not', () {
      final des = plantDesign('${tmp.path}/kd', struct: kitsStruct());
      final app = '${tmp.path}/appK';
      expect(scaffold(des, app, ['macos'], derivationPath, configPath), 0);
      final base = '$app/lib/ui/views/stage_shell/projects_home';
      expect(File('$base/projects_home_view.dart').readAsStringSync(),
          contains('//   kits (builder wires): maps, payments'));
      expect(File('$base/projects_home_viewmodel.dart').readAsStringSync(),
          contains('//   kits (builder wires): maps, payments'));
      final other = File('$app/lib/ui/views/stage_shell/settings_kits/'
              'settings_kits_view.dart')
          .readAsStringSync();
      expect(other.contains('kits (builder wires)'), isFalse,
          reason: 'no kits declared -> no kits line');
    });

    test('manifest kits section present only when a surface declares kits', () {
      final des = plantDesign('${tmp.path}/kd2', struct: kitsStruct());
      final app = '${tmp.path}/appK2';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      final mf = jsonDecode(
          File('$app/lib/ui/views/.shell-structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(mf['kits'],
          {'stage_shell_projects_home_view': ['maps', 'payments']});

      final des2 = plantDesign('${tmp.path}/kd3'); // baseStruct: no kits
      final app2 = '${tmp.path}/appK3';
      scaffold(des2, app2, ['macos'], derivationPath, configPath);
      final mf2 = jsonDecode(
          File('$app2/lib/ui/views/.shell-structure.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(mf2.containsKey('kits'), isFalse,
          reason: 'no kits anywhere -> section omitted (no manifest drift)');
    });

    test('malformed kits in frozen structure -> exit 1', () {
      final bad = kitsStruct();
      (bad['screens'] as List)[1]['kits'] = 'maps';
      var des = plantDesign('${tmp.path}/kd4', struct: bad);
      expect(scaffold(des, '${tmp.path}/appK4', ['macos'], derivationPath, configPath),
          1,
          reason: 'kits as a bare string -> exit 1');

      final bad2 = kitsStruct();
      (bad2['screens'] as List)[1]['kits'] = ['maps', 7];
      des = plantDesign('${tmp.path}/kd5', struct: bad2);
      expect(scaffold(des, '${tmp.path}/appK5', ['macos'], derivationPath, configPath),
          1,
          reason: 'non-string kit entry -> exit 1');
    });

    test('--check catches kits drift', () {
      final des = plantDesign('${tmp.path}/kd6', struct: kitsStruct());
      final app = '${tmp.path}/appK6';
      scaffold(des, app, ['macos'], derivationPath, configPath);
      expect(scaffold(des, app, ['macos'], derivationPath, configPath, check: true),
          0,
          reason: '--check green when in sync');

      final mfFile = File('$app/lib/ui/views/.shell-structure.json');
      final mf = jsonDecode(mfFile.readAsStringSync()) as Map<String, dynamic>;
      mf['kits'] = {'stage_shell_projects_home_view': ['nope']};
      mfFile.writeAsStringSync(jsonEncode(mf));
      expect(scaffold(des, app, ['macos'], derivationPath, configPath, check: true),
          1,
          reason: 'hand-edited kits section -> --check exit 1');
    });
  });

  group('self-test', () {
    test('runSelfTest passes', () {
      expect(runSelfTest(), 0);
    });
  });
}

const _derivationJson = r'''
{
  "targets": {
    "ios":     { "viewports": ["mobile", "tablet"], "ceremonies": [] },
    "android": { "viewports": ["mobile", "tablet"], "ceremonies": [] },
    "web":     { "viewports": ["mobile", "tablet", "desktop"], "ceremonies": [] },
    "pwa":     { "inherits": "web", "viewports": [], "ceremonies": [] },
    "macos":   { "viewports": ["desktop"], "ceremonies": [] },
    "linux":   { "viewports": ["desktop"], "ceremonies": [] },
    "windows": { "viewports": ["desktop"], "ceremonies": [] }
  }
}
''';

const _configJson = r'''
{
  "version": "1.0.0",
  "targets": ["macos"],
  "viewports": {
    "mobile":  { "width": 390,  "height": 844 },
    "tablet":  { "width": 744,  "height": 1133 },
    "desktop": { "width": 1280, "height": 800 }
  }
}
''';
