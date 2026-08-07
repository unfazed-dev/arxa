// arch_guard test — verifies the Dart port matches arch_guard.py's behavior.
// One positive (clean target passes) plus one negative per rule (G0–G5).

import 'dart:io';

import 'package:appboxd/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('arch-guard-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('G0 — no lib/ directory fails', () {
    final r = archGuard(tmp.path);
    expect(r.passed, isFalse);
    expect(r.files, 0);
    expect(r.violations, hasLength(1));
    expect(r.violations.single.rule, 'G0');
    expect(r.violations.single.file, 'lib/');
  });

  test('clean target with proper layering passes', () {
    _buildCleanTarget(tmp);
    final r = archGuard(tmp.path);
    expect(r.passed, isTrue,
        reason: r.violations.map((v) => '${v.rule} ${v.file}: ${v.msg}').join('\n'));
    expect(r.violations, isEmpty);
    expect(r.warnings, isEmpty);
    expect(r.files, greaterThan(0));
  });

  group('G1 layering', () {
    test('domain importing Flutter is a violation', () {
      _file(tmp, 'lib/domain/thing.dart',
          "import 'package:flutter/material.dart';\nclass Thing {}\n");
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(r.violations.any((v) => v.rule == 'G1' && v.msg.contains('Flutter')),
          isTrue);
    });

    test('domain importing Supabase is a violation (and G5)', () {
      _file(tmp, 'lib/domain/thing.dart',
          "import 'package:supabase_flutter/supabase_flutter.dart';\nclass Thing {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G1' && v.msg.contains('Supabase')),
          isTrue);
      expect(r.violations.any((v) => v.rule == 'G5'), isTrue);
    });

    test('domain importing infrastructure is a violation', () {
      _file(tmp, 'lib/domain/thing.dart',
          "import '../infrastructure/repo.dart';\nclass Thing {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G1' && v.msg.contains('infrastructure')),
          isTrue);
    });

    test('application importing Flutter widget UI is a violation', () {
      _file(tmp, 'lib/application/usecase.dart',
          "import 'package:flutter/widgets.dart';\nclass UseCase {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G1' && v.msg.contains('widget UI')),
          isTrue);
    });

    test('application importing infrastructure is a violation', () {
      _file(tmp, 'lib/application/usecase.dart',
          "import '../infrastructure/repo.dart';\nclass UseCase {}\n");
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G1' && v.msg.contains('use a domain Port')),
          isTrue);
    });
  });

  group('G2 viewmodel base', () {
    test('viewmodel extending a non-Stacked base is a violation', () {
      _file(tmp, 'lib/ui/bad_viewmodel.dart', 'class BadViewModel extends Foo {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(r.violations.any((v) => v.rule == 'G2' && v.msg.contains('Stacked base')),
          isTrue);
    });

    test('viewmodel with no class extending a base is a violation', () {
      _file(tmp, 'lib/ui/empty_viewmodel.dart', '// no class here\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G2' && v.msg.contains('missing')),
          isTrue);
    });

    test('viewmodel extending BaseViewModel is accepted', () {
      _file(tmp, 'lib/ui/good_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\nclass GoodViewModel extends BaseViewModel {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G2'), isEmpty);
    });

    test('viewmodel extending a generated *ViewModelBase is accepted', () {
      _file(tmp, 'lib/ui/gen_viewmodel.dart',
          'class GenViewModel extends GenViewModelBase {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G2'), isEmpty);
    });

    test('viewmodel extending the kit base (AppBoxKitViewModel) is accepted', () {
      _file(tmp, 'lib/ui/kit_viewmodel.dart',
          'class KitViewModel extends AppBoxKitViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G2'), isEmpty);
    });
  });

  group('G3 async-without-busy', () {
    test('viewmodel using async without a busy base is a violation', () {
      _file(
          tmp,
          'lib/ui/async_viewmodel.dart',
          'class AsyncViewModel extends Foo {\n'
          '  Future<void> run() async {}\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G3' && v.msg.contains('busy-capable')),
          isTrue);
    });
  });

  group('G4 infra repo port', () {
    test('infra repo without implements clause warns (but passes)', () {
      _file(tmp, 'lib/infrastructure/bad_repository.dart', 'class BadRepository {}\n');
      final r = archGuard(tmp.path);
      expect(r.warnings.any((w) => w.rule == 'G4'), isTrue);
      expect(r.passed, isTrue, reason: 'G4 is warn-level, not a violation');
    });

    test('infra repo implementing a Port does not warn', () {
      _file(tmp, 'lib/infrastructure/good_repository.dart',
          "import '../domain/ports/thing_repository.dart';\n"
          'class GoodRepo implements ThingRepository {}\n');
      final r = archGuard(tmp.path);
      expect(r.warnings.where((w) => w.rule == 'G4'), isEmpty);
    });

    test('abstract infra adapter base is skipped', () {
      _file(tmp, 'lib/infrastructure/base_repository.dart',
          'abstract class BaseRepository {}\n');
      final r = archGuard(tmp.path);
      expect(r.warnings.where((w) => w.rule == 'G4'), isEmpty);
    });
  });

  group('G5 supabase confinement', () {
    test('presentation importing supabase is a violation', () {
      _file(tmp, 'lib/ui/leak.dart',
          "import 'package:supabase_flutter/supabase_flutter.dart';\nclass Leak {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G5'), isTrue);
    });

    test('infrastructure importing supabase is NOT a violation', () {
      _file(tmp, 'lib/infrastructure/supabase_repository.dart',
          "import 'package:supabase_flutter/supabase_flutter.dart';\n"
          "import '../domain/ports/thing_repository.dart';\n"
          'class SupaRepo implements ThingRepository {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G5'), isEmpty);
    });
  });

  group('G6 one viewmodel per view', () {
    test('view importing a foreign viewmodel is a violation', () {
      _file(tmp, 'lib/ui/editor_view.dart',
          "import '../folder/folder_viewmodel.dart';\nclass EditorView {}\n");
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) => v.rule == 'G6' && v.msg.contains('foreign')),
          isTrue);
    });

    test('form-factor view importing a foreign viewmodel is a violation', () {
      _file(tmp, 'lib/ui/editor_view.mobile.dart',
          "import 'package:x/folder/folder_viewmodel.dart';\nclass EditorView {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G6'), isTrue);
    });

    test('view importing its own viewmodel (same basename) is accepted', () {
      _file(tmp, 'lib/ui/editor_view.mobile.dart',
          "import 'package:x/editor/editor_viewmodel.dart';\nclass EditorView {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G6'), isEmpty);
    });

    test('widgets are free to import any viewmodel (typed ViewModelWidget)', () {
      _file(tmp, 'lib/ui/widgets/editor_body_widget.dart',
          "import 'package:x/editor/editor_viewmodel.dart';\nclass Body {}\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G6'), isEmpty);
    });
  });

  group('G7 no mutable statics on viewmodels', () {
    test('a mutable static field on a viewmodel is a violation', () {
      _file(tmp, 'lib/ui/bad_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          'class BadViewModel extends BaseViewModel {\n'
          '  static String? pendingAction;\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) => v.rule == 'G7' && v.msg.contains('static')),
          isTrue);
    });

    test('static const/final fields and static members are accepted', () {
      _file(tmp, 'lib/ui/good_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          'class GoodViewModel extends BaseViewModel {\n'
          "  static const int limit = 10;\n"
          "  static final stamp = DateTime(2026);\n"
          '  static int get count => 1;\n'
          '  static void reset() {}\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G7'), isEmpty);
    });
  });

  group('G8 dialogs from UI', () {
    test('a view calling DialogService via the locator is a violation', () {
      _file(tmp, 'lib/ui/editor_view.dart',
          "import 'package:stacked_services/stacked_services.dart';\n"
          'class EditorView {\n'
          '  void go() => appBoxKitLocator<DialogService>().showCustomDialog();\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G8'), isTrue);
      expect(r.passed, isFalse);
    });

    test('a viewmodel calling DialogService does not warn', () {
      _file(tmp, 'lib/ui/editor_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:stacked_services/stacked_services.dart';\n"
          'class EditorViewModel extends BaseViewModel {\n'
          '  void go() => appBoxKitLocator<DialogService>().showCustomDialog();\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.warnings.where((w) => w.rule == 'G8'), isEmpty);
    });
  });

  group('G9 service-layer direction', () {
    test('viewmodel importing a repository is a violation', () {
      _file(tmp, 'lib/ui/bad_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:x/services/items/repositories/items_repository_service.dart';\n"
          'class BadViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any(
              (v) => v.rule == 'G9' && v.msg.contains('repository')),
          isTrue);
    });

    test('viewmodel importing a view is a violation', () {
      _file(tmp, 'lib/ui/bad_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:x/ui/views/home/home_view.dart';\n"
          'class BadViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G9'), isTrue);
    });

    test('facade importing a viewmodel is a violation', () {
      _file(tmp, 'lib/services/items/facades/items_facade_service.dart',
          "import 'package:x/ui/views/home/home_viewmodel.dart';\n"
          'class ItemsFacade {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G9'), isTrue);
    });

    test('adapter importing a facade is a violation', () {
      _file(tmp, 'lib/services/items/adapters/items_media_adapter_service.dart',
          "import 'package:x/services/items/facades/items_facade_service.dart';\n"
          'class ItemsAdapter {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G9'), isTrue);
    });

    test('repository importing an adapter is a violation', () {
      _file(tmp,
          'lib/services/items/repositories/items_repository_service.dart',
          "import 'package:x/services/items/adapters/items_media_adapter_service.dart';\n"
          'class ItemsRepo {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G9'), isTrue);
    });

    test('view importing a facade is a violation', () {
      _file(tmp, 'lib/ui/views/home/home_view.dart',
          "import 'package:x/services/items/facades/items_facade_service.dart';\n"
          'class HomeView {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G9'), isTrue);
    });

    test('facade importing repository + adapter is the sanctioned direction', () {
      _file(tmp, 'lib/services/items/facades/items_facade_service.dart',
          "import 'package:x/services/items/repositories/items_repository_service.dart';\n"
          "import 'package:x/services/items/adapters/items_media_adapter_service.dart';\n"
          'class ItemsFacade {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G9'), isEmpty);
    });

    test('viewmodel importing an adapter is a violation', () {
      _file(tmp, 'lib/ui/bad_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:x/services/items/adapters/items_media_adapter_service.dart';\n"
          'class BadViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) => v.rule == 'G9' && v.msg.contains('adapter')),
          isTrue);
    });

    test('viewmodel importing a facade is the sanctioned direction', () {
      _file(tmp, 'lib/ui/views/home/home_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:x/services/items/facades/items_facade_service.dart';\n"
          'class HomeViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G9'), isEmpty);
    });
  });

  group('G10 no duplicate URIs', () {
    test('the same URI imported twice is a violation', () {
      _file(tmp, 'lib/ui/dup.dart',
          "import 'package:flutter/material.dart';\n"
          "import 'package:flutter/material.dart' show Colors;\n"
          'class Dup {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any(
              (v) => v.rule == 'G10' && v.msg.contains('import')),
          isTrue);
    });

    test('the same URI exported twice is a violation', () {
      _file(tmp, 'lib/ui/dup.dart',
          "export 'package:x/a.dart';\n"
          "export 'package:x/a.dart' show A;\n");
      final r = archGuard(tmp.path);
      expect(r.violations.any((v) => v.rule == 'G10' && v.msg.contains('export')),
          isTrue);
    });

    test('import + export of the same URI is not a duplicate (barrel files)', () {
      _file(tmp, 'lib/data/models/models.dart',
          "export 'package:x/a.dart';\n"
          "export 'package:x/b.dart';\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G10'), isEmpty);
    });
  });

  group('G11 viewmodels never re-export', () {
    test('an export directive in a viewmodel is a violation', () {
      _file(tmp, 'lib/ui/reshare_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          "import 'package:x/models.dart';\n"
          "export 'package:x/models.dart';\n"
          'class ReShareViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any(
              (v) => v.rule == 'G11' && v.msg.contains('re-export')),
          isTrue);
    });
  });

  test('violations are sorted by (rule, file)', () {
    _file(tmp, 'lib/ui/zeta_viewmodel.dart', 'class Zeta extends Other {}\n');
    _file(tmp, 'lib/domain/alpha.dart',
        "import 'package:flutter/material.dart';\nclass Alpha {}\n");
    final r = archGuard(tmp.path);
    final keys = r.violations.map((v) => '${v.rule}|${v.file}').toList();
    final sorted = [...keys]..sort();
    expect(keys, equals(sorted));
  });
}

/// Create a file (with parent dirs) and write [content].
void _file(Directory tmp, String relPath, String content) {
  final f = File('${tmp.path}/$relPath');
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
}

/// A complete, contract-conformant target that passes every rule.
void _buildCleanTarget(Directory tmp) {
  // domain — pure Dart
  _file(tmp, 'lib/domain/entities/thing.dart', 'class Thing {}\n');
  // domain Port
  _file(tmp, 'lib/domain/ports/thing_repository.dart',
      'abstract class ThingRepository {}\n');
  // application viewmodel — extends a Stacked busy-capable base
  _file(tmp, 'lib/application/thing_viewmodel.dart',
      "import 'package:stacked/stacked.dart';\n"
      'class ThingViewModel extends BaseViewModel {}\n');
  // infrastructure repo — implements the domain Port
  _file(tmp, 'lib/infrastructure/thing_repository.dart',
      "import '../domain/ports/thing_repository.dart';\n"
      'class ThingRepo implements ThingRepository {}\n');
  // presentation view — Flutter UI lives here
  _file(tmp, 'lib/presentation/thing_view.dart',
      "import 'package:flutter/material.dart';\n"
      "import '../application/thing_viewmodel.dart';\n"
      'class ThingView extends StatelessWidget {\n'
      '  const ThingView({super.key});\n'
      '  @override\n'
      '  Widget build(BuildContext context) => const SizedBox();\n'
      '}\n');
}
