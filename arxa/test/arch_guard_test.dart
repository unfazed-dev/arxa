// arch_guard test — verifies the Dart port matches arch_guard.py's behavior.
// One positive (clean target passes) plus one negative per rule (G0–G13).

import 'dart:io';

import 'package:arxa/arch_guard.dart';
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

    test('viewmodel extending the kit base (ArxaKitViewModel) is accepted', () {
      _file(tmp, 'lib/ui/kit_viewmodel.dart',
          'class KitViewModel extends ArxaKitViewModel {}\n');
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
          '  void go() => arxaKitLocator<DialogService>().showCustomDialog();\n'
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
          '  void go() => arxaKitLocator<DialogService>().showCustomDialog();\n'
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

  group('G12 enums/sealed types live in lib/enums', () {
    test('an enum declared in a viewmodel file is a violation', () {
      _file(tmp, 'lib/ui/editor_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          'enum EditorMode { draft, live }\n'
          'class EditorViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) =>
              v.rule == 'G12' &&
              v.file == 'ui/editor_viewmodel.dart' &&
              v.msg.contains('EditorMode')),
          isTrue);
    });

    test('a sealed class outside lib/enums is a violation', () {
      _file(tmp, 'lib/data/models/note_state.dart', 'sealed class NoteState {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any(
              (v) => v.rule == 'G12' && v.msg.contains('NoteState')),
          isTrue);
    });

    test('an enum under lib/enums/<shell>_enums is accepted', () {
      _file(tmp, 'lib/enums/showcase_notes_enums/note_status.dart',
          'enum NoteStatus { draft, live }\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G12'), isEmpty);
    });

    test('a sealed class under lib/enums is accepted', () {
      _file(tmp, 'lib/enums/showcase_notes_enums/note_state.dart',
          'sealed class NoteState {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G12'), isEmpty);
    });

    test('enums and sealed types in generated files are exempt', () {
      _file(tmp, 'lib/app/app.router.dart',
          'enum RouteTab { home, settings }\n'
          'sealed class RouterState {}\n');
      _file(tmp, 'lib/data/models/note.freezed.dart',
          'sealed class Note {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G12'), isEmpty);
    });
  });

  group('G13 semantic frontmatter', () {
    test('covered viewmodel without library; is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G13' && v.msg.contains('library;')),
          isTrue);
    });

    test('covered viewmodel with library; but no doc comment is a violation',
        () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G13' && v.msg.contains('doc comment')),
          isTrue);
    });

    test('covered viewmodel with doc comment but no role paragraph is a violation',
        () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel.\n'
          '/// It does things.\n'
          '/// More detail here.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// Loads the thing.\n'
          '///\n'
          '/// History: git log --follow -- x\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G13' && v.msg.contains('role paragraph')),
          isTrue);
    });

    test('covered viewmodel with doc comment but no requirements is a violation',
        () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel.\n'
          '/// It does things.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// History: git log --follow -- x\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G13' && v.msg.contains('requirements')),
          isTrue);
    });

    test('covered viewmodel with doc comment but no History is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel.\n'
          '/// It does things.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// Loads the thing.\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations
              .any((v) => v.rule == 'G13' && v.msg.contains('History')),
          isTrue);
    });

    test('fully conformant viewmodel passes', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages the state\n'
          '/// and exposes actions the view calls on user input.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('model (light variant) passes with role paragraph + library;', () {
      _file(tmp, 'lib/data/models/thing_model.dart',
          '/// A model is a pure data class — fields and serialization only.\n'
          '/// No behavior, no Flutter, no services.\n'
          '///\n'
          '/// This is the data shape for a thing — its id and name.\n'
          'library;\n'
          'class ThingModel {\n'
          '  final String id;\n'
          '  ThingModel({required this.id});\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('barrel file (export-only) is exempt', () {
      _file(tmp, 'lib/ui/widgets/widgets.dart',
          "export 'package:x/a_widget.dart';\n"
          "export 'package:x/b_widget.dart';\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('enum file is exempt', () {
      _file(tmp, 'lib/enums/shell_enums/thing_enum.dart',
          'enum ThingEnum { a, b }\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('generated file is exempt', () {
      _file(tmp, 'lib/app/app.router.dart',
          'class Router {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('file under lib/app/ is exempt', () {
      _file(tmp, 'lib/app/locator_viewmodel.dart',
          "import 'package:stacked/stacked.dart';\n"
          'class LocatorViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('widget file conforms with full frontmatter', () {
      _file(tmp, 'lib/ui/widgets/thing_widget.dart',
          '/// A widget is a reusable piece of a view — a card or section that\n'
          '/// composes primitives and turns taps into callbacks.\n'
          '///\n'
          '/// This is the user interface for a thing card. It shows the thing\n'
          '/// and calls back on tap.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Display] — story-1\n'
          '/// The thing is rendered in a card.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/widgets/thing_widget.dart\n'
          'library;\n'
          "import 'package:flutter/material.dart';\n"
          'class ThingWidget extends StatelessWidget {\n'
          '  const ThingWidget({super.key});\n'
          '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox();\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('diagram with misaligned tier centers is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// Relationships:\n'
          '///\n'
          '///      ┌──────────────────┐\n'
          '///      │ note editor view │\n'
          '///      └──────────────────┘\n'
          '///                            ┌─────────────────────────┐\n'
          '///                            │  note editor viewmodel  │\n'
          '///                            └─────────────────────────┘\n'
          '///                            ════════ abxAction ════════\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13' && v.msg.contains('diagram tier centers')),
          isTrue);
    });

    test('diagram with aligned tier centers passes', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// Relationships:\n'
          '///\n'
          '///      ┌──────────────────┐\n'
          '///      │ note editor view │\n'
          '///      └──────────────────┘\n'
          '///   ┌─────────────────────────┐\n'
          '///   │  note editor viewmodel  │\n'
          '///   └─────────────────────────┘\n'
          '///   ════════ abxAction ════════\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('spine parts out of order is a violation (History before Requirements)', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// Relationships:\n'
          '///\n'
          '///   ┌───────┐\n'
          '///   │ view  │\n'
          '///   └───────┘\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13' && v.msg.contains('spine parts out of order')),
          isTrue);
    });

    test('spine parts in order passes', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// Relationships:\n'
          '///\n'
          '///   ┌───────┐\n'
          '///   │ view  │\n'
          '///   └───────┘\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13'), isEmpty);
    });

    test('section separators out of order is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {\n'
          '  // ── Setup ──────────────────────────────────────────────────────────────\n'
          '  // ── Actions ──────────────────────────────────────────────────────────────\n'
          '  // ── Streams ────────────────────────────────────────────────────────────────\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13' &&
              v.msg.contains(
                  "section separator 'Actions' appears before 'Streams'")),
          isTrue);
    });

    test('section separators in locked order passes', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {\n'
          '  // ── Setup ──────────────────────────────────────────────────────────────\n'
          '  // ── Streams ────────────────────────────────────────────────────────────────\n'
          '  // ── Actions ────────────────────────────────────────────────────────────────\n'
          '  // ── Cleanup ────────────────────────────────────────────────────────────────\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.where(
              (v) => v.rule == 'G13' && v.msg.contains('section separator')),
          isEmpty);
    });

    test('section separators not checked for views', () {
      _file(tmp, 'lib/ui/test_view.dart',
          '/// A view composes primitives and binds the viewmodel streams.\n'
          '///\n'
          '/// This is the user interface for testing. It renders things.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Display] — story-1\n'
          '/// The thing is shown.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_view.dart\n'
          'library;\n'
          "import 'package:flutter/material.dart';\n"
          'class TestView extends StatelessWidget {\n'
          '  const TestView({super.key});\n'
          '  // ── Banana ──\n'
          '  // ── Apple ──\n'
          '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox();\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.where(
              (v) => v.rule == 'G13' && v.msg.contains('section separator')),
          isEmpty);
    });
  });

  group('G13-language plain-language canon', () {
    // Conformant frontmatter shared by the fixtures below.
    const fm = '/// The test viewmodel. Actions in, streams out.\n'
        '///\n'
        '/// This is the business logic for testing. It manages state.\n'
        '///\n'
        '/// Requirements:\n'
        '/// 1. [Load] — story-1\n'
        '/// The thing is loaded on init.\n'
        '///\n'
        '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
        'library;\n'
        "import 'package:stacked/stacked.dart';\n";

    test('the canonical pilot viewmodel passes clean', () {
      final pilot = File(
          '../kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart');
      _file(tmp, 'lib/ui/showcase_note_editor_viewmodel.dart',
          pilot.readAsStringSync());
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13-language'), isEmpty,
          reason: r.violations
              .map((v) => '${v.rule} ${v.file}: ${v.msg}')
              .join('\n'));
    });

    test('a 10-line jargon class doc is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '$fm' '/// This viewmodel leverages a self-contained paradigm where the\n'
          '/// PreferredSizeWidget and NestedRouter facilitate a wrapper\n'
          '/// abstraction over the IndexedStack. The boilerplate utilizes\n'
          '/// a StatelessWidget and StatefulWidget with BuildContext to\n'
          '/// render the Scaffold. This abstraction facilitates composition\n'
          '/// across the shell. The wrapper leverages the paradigm to\n'
          '/// reduce boilerplate further. The IndexedStack maintains state\n'
          '/// across tabs without rebuilding. The NestedRouter handles\n'
          '/// deep links. It is fully self-contained and easy to reason\n'
          '/// about.\n'
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      final lang = r.violations.where((v) => v.rule == 'G13-language').toList();
      expect(lang, isNotEmpty);
      expect(lang.any((v) => v.msg.contains('capped at 2 lines')), isTrue);
      expect(lang.any((v) => v.msg.contains('class doc comment')), isTrue);
      expect(lang.any((v) => v.msg.contains('banned token')), isTrue);
    });

    test('a 3-line member doc is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '$fm' 'class TestViewModel extends BaseViewModel {\n'
          '  /// The name, filled in once on load.\n'
          '  /// Empty while loading. Reset when\n'
          '  /// the thing changes.\n'
          '  String name = \'\';\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13-language' && v.msg.contains('capped at 2 lines')),
          isTrue);
    });

    test('a 2-line member doc passes', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '$fm' 'class TestViewModel extends BaseViewModel {\n'
          '  /// The name, filled in once on load.\n'
          '  /// Empty while loading.\n'
          '  String name = \'\';\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13-language'), isEmpty);
    });

    test('a banned token inside backticks passes; outside backticks fails', () {
      _file(tmp, 'lib/ui/backtick_viewmodel.dart',
          '$fm' 'class BacktickViewModel extends BaseViewModel {\n'
          '  /// Rendered inside an `IndexedStack`.\n'
          '  int tab = 0;\n'
          '}\n');
      _file(tmp, 'lib/ui/plain_viewmodel.dart',
          '$fm' 'class PlainViewModel extends BaseViewModel {\n'
          '  /// Rendered inside an IndexedStack.\n'
          '  int tab = 0;\n'
          '}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13-language' &&
              v.file.startsWith('ui/backtick_viewmodel.dart')),
          isFalse);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13-language' &&
              v.file.startsWith('ui/plain_viewmodel.dart') &&
              v.msg.contains('IndexedStack')),
          isTrue);
    });

    test('requirement lines, diagram, inventory, and History are exempt', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — leverage the paradigm\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// Relationships:\n'
          '///\n'
          '///   ┌───────────────────┐\n'
          '///   │ view — wrapper    │\n'
          '///   └───────────────────┘\n'
          '///   paradigm leverage utilize\n'
          '///\n'
          '///  streams (STRM)   actions (ACT)\n'
          '///    1. note\$         1. wrapper\n'
          '///\n'
          '/// History: git log --follow -- utilize facilitate boilerplate\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G13-language'), isEmpty,
          reason: r.violations
              .map((v) => '${v.rule} ${v.file}: ${v.msg}')
              .join('\n'));
    });

    test('a frontmatter paragraph over 6 lines is a violation', () {
      _file(tmp, 'lib/ui/test_viewmodel.dart',
          '/// The test viewmodel. Actions in, streams out — one.\n'
          '/// two.\n'
          '/// three.\n'
          '/// four.\n'
          '/// five.\n'
          '/// six.\n'
          '/// seven.\n'
          '///\n'
          '/// This is the business logic for testing. It manages state.\n'
          '///\n'
          '/// Requirements:\n'
          '/// 1. [Load] — story-1\n'
          '/// The thing is loaded on init.\n'
          '///\n'
          '/// History: git log --follow -- lib/ui/test_viewmodel.dart\n'
          'library;\n'
          "import 'package:stacked/stacked.dart';\n"
          'class TestViewModel extends BaseViewModel {}\n');
      final r = archGuard(tmp.path);
      expect(
          r.violations.any((v) =>
              v.rule == 'G13-language' &&
              v.msg.contains('frontmatter paragraph capped at 6 lines')),
          isTrue);
    });
  });

  group('G14 naming — abxAction vocabulary is the one family', () {
    test('a k-prefixed action constant declaration is a violation', () {
      _file(tmp, 'lib/ui/kit_action/bad_consts.dart',
          "const String kSaveAction = 'save';\n");
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) =>
              v.rule == 'G14' && v.msg.contains("kSaveAction")),
          isTrue);
    });

    test('a k-prefixed hub constant declaration is a violation', () {
      _file(tmp, 'lib/ui/kit_action/bad_hub.dart',
          "class Foo {\n  static const kNotesHub = 'notes';\n}\n");
      final r = archGuard(tmp.path);
      expect(
          r.violations.any(
              (v) => v.rule == 'G14' && v.msg.contains('kNotesHub')),
          isTrue);
    });

    test('an unrelated Flutter k-constant reference (not declared) does not fire', () {
      _file(tmp, 'lib/ui/widgets/fab_widget.dart',
          "import 'package:flutter/material.dart';\n"
          'double fabBottom(double barTop) =>\n'
          '    barTop - kFloatingActionButtonMargin;\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G14'), isEmpty);
    });

    test('an unrelated k-prefixed constant outside the action/hub family does not fire', () {
      _file(tmp, 'lib/ui/widgets/consts.dart',
          "const double kShowcaseTabBarBlockHeight = 64.0;\n");
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G14'), isEmpty);
    });

    test('the lowercase-k casing typo is a violation', () {
      _file(tmp, 'lib/ui/kit_action/typo.dart',
          'void disposeArxakitActions() {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any(
              (v) => v.rule == 'G14' && v.msg.contains('casing typo')),
          isTrue);
    });

    test('the correct ArxaKit casing does not fire', () {
      _file(tmp, 'lib/ui/kit_action/ok.dart',
          'void disposeArxaKitActions() {}\n'
          'class ArxaKitActionHub {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G14'), isEmpty);
    });

    test('a rival Abx* PascalCase type declaration is a violation', () {
      _file(tmp, 'lib/ui/kit_action/rival.dart', 'class AbxActionHub {}\n');
      final r = archGuard(tmp.path);
      expect(r.passed, isFalse);
      expect(
          r.violations.any((v) =>
              v.rule == 'G14' && v.msg.contains('AbxActionHub')),
          isTrue);
    });

    test('the sanctioned abx lowerCamel constants do not fire', () {
      _file(tmp, 'lib/ui/kit_action/sanctioned.dart',
          "const String abxPad16 = 'abxPad16';\n"
          "const String abxAction = 'abxAction';\n"
          'class ArxaKitActionHub {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G14'), isEmpty);
    });

    test('generated files are exempt — nobody authored the name', () {
      _file(tmp, 'lib/app/app.router.dart',
          "const kSaveActionRoute = 'kSaveActionRoute';\n");
      _file(tmp, 'lib/data/models/note.freezed.dart',
          'class AbxGenerated {}\n');
      final r = archGuard(tmp.path);
      expect(r.violations.where((v) => v.rule == 'G14'), isEmpty);
    });
  });

  test('violations are sorted by (rule, file)', () {
    _file(tmp, 'lib/ui/zeta_viewmodel.dart', 'class Zeta extends Other {}\n');
    _file(tmp, 'lib/domain/alpha.dart',
        "import 'package:flutter/material.dart';\nclass Alpha {}\n");
    final r = archGuard(tmp.path);
    // Sort with the same comparator the guard uses (rule first, then file),
    // not a bare string sort — 'G13' < 'G1' by raw string but 'G1' < 'G13'
    // by rule-only comparison, and the guard sorts by rule.
    final sorted = [...r.violations]..sort((a, b) {
      final byRule = a.rule.compareTo(b.rule);
      return byRule != 0 ? byRule : a.file.compareTo(b.file);
    });
    expect(
      r.violations.map((v) => '${v.rule}|${v.file}').toList(),
      equals(sorted.map((v) => '${v.rule}|${v.file}').toList()),
    );
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
  // application viewmodel — extends a Stacked busy-capable base, G13 frontmatter
  _file(tmp, 'lib/application/thing_viewmodel.dart',
      '/// The thing viewmodel. Actions in, streams out — never touches the\n'
      '/// view. Swap the UI for any other and this file stays unchanged.\n'
      '///\n'
      '/// This is the business logic for managing a thing. It loads the thing\n'
      '/// on init and exposes actions the view calls on user input.\n'
      '///\n'
      '/// Requirements:\n'
      '/// 1. [Load] — story-1\n'
      '/// The thing is loaded on init.\n'
      '///\n'
      '/// History: git log --follow -- lib/application/thing_viewmodel.dart\n'
      'library;\n'
      '\n'
      "import 'package:stacked/stacked.dart';\n"
      'class ThingViewModel extends BaseViewModel {}\n');
  // infrastructure repo — implements the domain Port
  _file(tmp, 'lib/infrastructure/thing_repository.dart',
      "import '../domain/ports/thing_repository.dart';\n"
      'class ThingRepo implements ThingRepository {}\n');
  // presentation view — Flutter UI lives here, G13 frontmatter
  _file(tmp, 'lib/presentation/thing_view.dart',
      '/// A view composes primitives and binds the viewmodel streams. It never\n'
      '/// contains business logic — every decision lives in the viewmodel.\n'
      '///\n'
      '/// This is the user interface for viewing a thing. It renders the thing\n'
      '/// and forwards user taps to the viewmodel actions.\n'
      '///\n'
      '/// Requirements:\n'
      '/// 1. [Display] — story-1\n'
      '/// The thing is shown on screen.\n'
      '///\n'
      '/// History: git log --follow -- lib/presentation/thing_view.dart\n'
      'library;\n'
      '\n'
      "import 'package:flutter/material.dart';\n"
      "import '../application/thing_viewmodel.dart';\n"
      'class ThingView extends StatelessWidget {\n'
      '  const ThingView({super.key});\n'
      '  @override\n'
      '  Widget build(BuildContext context) => const SizedBox();\n'
      '}\n');
}
