// gate_scaffold S6 scope-truth tests — the placement law on the build side.
//
// A widget lives at the narrowest scope that covers all its consumers, and the
// import graph is the only authority. Every case below is discriminating: the
// canonical tree passes, and each single mutation fails with the fix named.

import 'dart:io';

import 'package:appboxd/gate_scaffold.dart';
import 'package:appboxd/gates.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String app;

  void write(String rel, String body) {
    final f = File('$app/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
  }

  void rm(String rel) => File('$app/$rel').deleteSync();

  /// A shell that satisfies S1/S4 on its own; widgets are added per test.
  void plantShell(String shell, List<String> views) {
    write('lib/ui/views/$shell/design-system.md', '## Palette\n\nkcPrimary\n');
    write('lib/ui/views/$shell/${shell}_chrome.dart', 'class Chrome {}\n');
    for (final v in views) {
      write('lib/ui/views/$shell/$v/${v}_view.dart', 'class View {}\n');
      write('lib/ui/views/$shell/$v/${v}_viewmodel.dart', 'class ViewModel {}\n');
    }
  }

  void manifest(List<String> shells) => write('lib/ui/views/.shell-structure.json',
      '{"selfContained":[${shells.map((s) => '"$s"').join(',')}]}');

  GateResult run() => scaffoldGate(GateContext(repoRoot: app, appRoot: app));
  String detailsOf(GateResult r) => r.details.join('\n');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate-scaffold-test-');
    app = tmp.path;
    write('pubspec.yaml', 'name: demo\n');
    manifest(['main_shell']);
    plantShell('main_shell', ['home', 'detail']);
    // Canonical: one shared widget, imported by two surfaces of one shell.
    write('lib/ui/views/main_shell/shared/widgets/badge.dart', 'class Badge {}\n');
    for (final v in ['home', 'detail']) {
      write('lib/ui/views/main_shell/$v/${v}_view.dart',
          "import '../shared/widgets/badge.dart';\n\nclass View {}\n");
    }
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('S6 scope truth: <shell>/shared/widgets/', () {
    test('canonical tree passes — two surfaces share one widget', () {
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r),
          contains('main_shell: shared/widgets/: 1 widget(s) at the right scope (S6)'));
    });

    test('sole-consumer widget in shared/widgets/ fails, demotion named', () {
      // detail stops importing it: home is now the only consumer.
      write('lib/ui/views/main_shell/detail/detail_view.dart', 'class View {}\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('sole-consumer widget in shared/widgets/ (S6)'));
      expect(detailsOf(r), contains('move it to lib/ui/views/main_shell/home/widgets/'));
    });

    test('a widget reached only through a barrel is still judged (non-vacuous)', () {
      write('lib/ui/views/main_shell/shared/widgets/widgets.dart',
          "library;\n\nexport 'badge.dart';\n");
      write('lib/ui/views/main_shell/home/home_view.dart',
          "import '../shared/widgets/widgets.dart';\n\nclass View {}\n");
      write('lib/ui/views/main_shell/detail/detail_view.dart', 'class View {}\n');
      final r = run();
      expect(r.passed, isFalse, reason: 'the barrel hop must not hide the consumer');
      expect(detailsOf(r), contains('move it to lib/ui/views/main_shell/home/widgets/'));
      // The barrel is an edge, not a subject: exactly one failure, not two.
      expect(
          r.details.where((d) => d.contains('(S6)') && d.startsWith('FAIL')).length, 1);
    });

    test('two surfaces reaching a widget through a barrel pass', () {
      write('lib/ui/views/main_shell/shared/widgets/widgets.dart',
          "library;\n\nexport 'badge.dart';\n");
      for (final v in ['home', 'detail']) {
        write('lib/ui/views/main_shell/$v/${v}_view.dart',
            "import '../shared/widgets/widgets.dart';\n\nclass View {}\n");
      }
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('unconsumed shared widget warns, never fails', () {
      write('lib/ui/views/main_shell/shared/widgets/orphan.dart', 'class Orphan {}\n');
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('unconsumed widget (S6)'));
    });
  });

  group('S6 scope truth: cross-shell home lib/ui/widgets/', () {
    test('shared widget imported by another shell fails, promotion named', () {
      // alt_shell is outside the manifest, so S2 never sees the import: S6 is
      // the only reporter and must speak.
      plantShell('alt_shell', ['gallery']);
      write('lib/ui/views/alt_shell/gallery/gallery_view.dart',
          "import 'package:demo/ui/views/main_shell/shared/widgets/badge.dart';\n\n"
          'class View {}\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('cross-shell widget in shared/widgets/ (S6)'));
      expect(detailsOf(r), contains('alt_shell'));
      expect(detailsOf(r), contains('lib/ui/widgets/'));
    });

    test('the same widget at lib/ui/widgets/ passes', () {
      plantShell('alt_shell', ['gallery']);
      rm('lib/ui/views/main_shell/shared/widgets/badge.dart');
      write('lib/ui/widgets/badge.dart', 'class Badge {}\n');
      for (final v in ['home', 'detail']) {
        write('lib/ui/views/main_shell/$v/${v}_view.dart',
            "import 'package:demo/ui/widgets/badge.dart';\n\nclass View {}\n");
      }
      write('lib/ui/views/alt_shell/gallery/gallery_view.dart',
          "import 'package:demo/ui/widgets/badge.dart';\n\nclass View {}\n");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r),
          contains('lib/ui/widgets/: 1 cross-shell widget(s)'));
    });

    test('lib/ui/widgets/ file with one-shell consumers fails, demotion named', () {
      write('lib/ui/widgets/badge.dart', 'class Badge {}\n');
      for (final v in ['home', 'detail']) {
        write('lib/ui/views/main_shell/$v/${v}_view.dart',
            "import 'package:demo/ui/widgets/badge.dart';\n\nclass View {}\n");
      }
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('imported by one shell only (main_shell)'));
      expect(detailsOf(r),
          contains('move it to lib/ui/views/main_shell/shared/widgets/'));
    });

    test('lib/ui/widgets/ file with one-surface consumers demotes to that surface',
        () {
      write('lib/ui/widgets/badge.dart', 'class Badge {}\n');
      write('lib/ui/views/main_shell/home/home_view.dart',
          "import 'package:demo/ui/widgets/badge.dart';\n\nclass View {}\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r),
          contains('move it to lib/ui/views/main_shell/home/widgets/'));
    });

    test('an app-level consumer keeps a widget app-wide (exemption is load-bearing)',
        () {
      rm('lib/ui/views/main_shell/shared/widgets/badge.dart');
      write('lib/ui/widgets/hover_badge.dart', 'class HoverBadge {}\n');
      write('lib/extensions/hover_extensions.dart',
          "import 'package:demo/ui/widgets/hover_badge.dart';\n\nclass Hover {}\n");
      for (final v in ['home', 'detail']) {
        write('lib/ui/views/main_shell/$v/${v}_view.dart',
            "import 'package:demo/ui/widgets/hover_badge.dart';\n\nclass View {}\n");
      }
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('unconsumed cross-shell widget fails', () {
      write('lib/ui/widgets/badge.dart', 'class Badge {}\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('unconsumed cross-shell widget (S6)'));
    });

    test('a *_chrome.dart is an edge, not a subject', () {
      write('lib/ui/widgets/app_chrome.dart', 'class AppChrome {}\n');
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });
  });

  group('S6/S2 dedupe: one cause, one failure', () {
    test('a cross-shell import out of a self-contained shell is reported by S2 only',
        () {
      plantShell('alt_shell', ['gallery']);
      manifest(['main_shell', 'alt_shell']);
      write('lib/ui/views/alt_shell/gallery/gallery_view.dart',
          "import 'package:demo/ui/views/main_shell/shared/widgets/badge.dart';\n\n"
          'class View {}\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('cross-shell import (S2)'));
      expect(detailsOf(r), isNot(contains('cross-shell widget in shared/widgets/ (S6)')),
          reason: 'S2 already names this edge; S6 must not double-report it');
    });
  });
}
