// Tests for the kit structural-contract checker — barrel files, publish_to,
// SDK pin consistency, and dependency-topology violation detection. Fixtures
// build a throwaway kit/ tree and assert checkKitConventions flags or passes.

import 'dart:io';

import 'package:appboxd/kit_conventions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kit_conventions_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Writes [relPath] (under kit/) with [contents], creating parent dirs.
  File f(String relPath, String contents) {
    final file = File(p.join(tmp.path, 'kit', relPath))
      ..createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  /// Seeds a well-formed kit directory. Pass a custom [pubspec] to inject
  /// violations; barrel/testing default on for library kits.
  void kit(
    String dir, {
    required String name,
    String? pubspec,
    bool barrel = true,
    bool testing = true,
  }) {
    f('$dir/pubspec.yaml',
        pubspec ?? "name: $name\npublish_to: 'none'\n\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n");
    if (barrel) f('$dir/lib/$name.dart', '// barrel\n');
    if (testing) f('$dir/lib/testing.dart', '// testing\n');
  }

  String kitRoot() => p.join(tmp.path, 'kit');

  group('barrel files', () {
    test('errors when a library kit is missing its barrel lib/<name>.dart', () {
      kit('core', name: 'appbox_kit_core', barrel: false);
      final r = checkKitConventions(kitRoot());
      expect(r.ok, isFalse);
      expect(r.errors,
          anyElement(contains('core missing barrel lib/appbox_kit_core.dart')));
    });

    test('showcase_app is exempt from the barrel check', () {
      kit('showcase_app', name: 'showcase_app', barrel: false, testing: false);
      final r = checkKitConventions(kitRoot());
      expect(r.errors, isEmpty);
    });
  });

  group('publish_to', () {
    test("errors when publish_to: 'none' is absent", () {
      kit('core',
          name: 'appbox_kit_core',
          pubspec: "name: appbox_kit_core\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n");
      final r = checkKitConventions(kitRoot());
      expect(r.ok, isFalse);
      expect(r.errors, anyElement(contains("missing publish_to: 'none'")));
    });

    test("accepts publish_to with double quotes", () {
      kit('core',
          name: 'appbox_kit_core',
          pubspec: 'name: appbox_kit_core\npublish_to: "none"\n\nenvironment:\n  sdk: \'>=3.0.0 <4.0.0\'\n');
      expect(checkKitConventions(kitRoot()).ok, isTrue);
    });
  });

  group('SDK pin consistency', () {
    test('errors when two kits declare different SDK constraints', () {
      kit('core',
          name: 'appbox_kit_core',
          pubspec: "name: appbox_kit_core\npublish_to: 'none'\n\nenvironment:\n  sdk: '>=3.8.1 <4.0.0'\n");
      kit('auth',
          name: 'appbox_kit_auth',
          pubspec: "name: appbox_kit_auth\npublish_to: 'none'\n\nenvironment:\n  sdk: '>=3.0.3 <4.0.0'\n");
      final r = checkKitConventions(kitRoot());
      expect(r.ok, isFalse);
      expect(r.errors, anyElement(contains('SDK pins differ across kits')));
    });

    test('passes when every kit shares the same SDK pin', () {
      kit('core', name: 'appbox_kit_core');
      kit('auth', name: 'appbox_kit_auth');
      expect(checkKitConventions(kitRoot()).ok, isTrue);
    });
  });

  group('dependency topology', () {
    test('errors when a standalone kit reaches across to another kit', () {
      // 'auth' is not in the allowed-deps map → standalone; any appbox_kit_*
      // dep is a violation.
      kit('auth',
          name: 'appbox_kit_auth',
          pubspec: "name: appbox_kit_auth\npublish_to: 'none'\n\n"
              "environment:\n  sdk: '>=3.0.0 <4.0.0'\n\n"
              "dependencies:\n  appbox_kit_core:\n    path: ../core\n");
      final r = checkKitConventions(kitRoot());
      expect(r.ok, isFalse);
      expect(r.errors,
          anyElement(contains('auth -> appbox_kit_core')));
    });

    test("allows data -> appbox_kit_core (sanctioned by the hub-and-spoke)", () {
      kit('core', name: 'appbox_kit_core');
      kit('data',
          name: 'appbox_kit_data',
          pubspec: "name: appbox_kit_data\npublish_to: 'none'\n\n"
              "environment:\n  sdk: '>=3.0.0 <4.0.0'\n\n"
              "dependencies:\n  appbox_kit_core:\n    path: ../core\n");
      expect(checkKitConventions(kitRoot()).ok, isTrue);
    });

    test('allows ui_library -> appbox_kit_core and appbox_kit_motion', () {
      kit('core', name: 'appbox_kit_core');
      kit('motion', name: 'appbox_kit_motion');
      kit('ui_library',
          name: 'appbox_kit_ui',
          pubspec: "name: appbox_kit_ui\npublish_to: 'none'\n\n"
              "environment:\n  sdk: '>=3.0.0 <4.0.0'\n\n"
              "dependencies:\n  appbox_kit_core:\n    path: ../core\n"
              "  appbox_kit_motion:\n    path: ../motion\n");
      expect(checkKitConventions(kitRoot()).ok, isTrue);
    });
  });
}
