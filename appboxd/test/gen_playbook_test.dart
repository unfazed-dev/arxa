// Tests for gen_playbook.dart — the Dart port of gen_playbook.py.
//
// Covers the faithful-render contract: the mechanical sections land from facts,
// README narrative folds into prose, empty facts stay safe, the stacked_kit
// brand never appears (appbox_kit does), and test doubles are split out of the
// public API table.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gen_playbook.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('generatePlaybook', () {
    test('renders header, role, public-surface table, and references from facts',
        () {
      final facts = <String, dynamic>{
        'name': 'appbox_kit_core',
        'version': '0.1.0',
        'description':
            'Reusable Stacked MVVM toolkit. Holds AppBoxKitAction and reactive services.',
        'hasTesting': true,
        'publicSurface': [
          {'name': 'AppBoxKitPlatform', 'kind': 'class', 'file': 'platform/appbox_kit_platform.dart'},
          {'name': 'AppBoxKitTier', 'kind': 'enum', 'file': 'platform/appbox_kit_platform.dart'},
        ],
        'frameworkDeps': ['stacked', 'stacked_services'],
        'backingPackages': ['get', 'rxdart'],
        'kitDeps': <String>[],
      };

      final mdx = generatePlaybook(facts);

      // Header + version line.
      expect(mdx, contains('# appbox_kit_core — Per-Package Playbook'));
      expect(mdx, contains('v**0.1.0**'));

      // First sentence of the description becomes the one-line role.
      expect(mdx, contains('**Role (one line):** Reusable Stacked MVVM toolkit'));

      // Key symbols land in the API table; the slug-derived block id is core.
      expect(mdx, contains('AppBoxKitPlatform'));
      expect(mdx, contains('AppBoxKitTier'));
      expect(mdx, contains('id="core-api"'));

      // Integration map carries the framework + backing deps verbatim.
      expect(mdx, contains('stacked, stacked_services'));
      expect(mdx, contains('get, rxdart'));

      // Anchors that must always be present.
      expect(mdx, contains('<!-- kb:begin -->'));
      expect(mdx, contains('### References'));
      expect(mdx, contains('<!-- kb:end -->'));
      expect(mdx, contains('<QuestionForm id="open-questions"'));
    });

    test('loads facts + README from a temp kit dir and folds README prose', () {
      final tmp = Directory.systemTemp.createTempSync('gen_playbook_kit');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // The kit source directory (with a README to mine).
      final kitDir = Directory(p.join(tmp.path, 'maps'))..createSync();
      File(p.join(kitDir.path, 'README.md')).writeAsStringSync('''
# appbox_kit_maps

Plugin-neutral maps port for appbox_kit apps.

## Usage

Render `AppBoxKitMapView` and pass a `AppBoxKitMapConfig`.

## Architecture

Standalone leaf — no sibling-kit dependency.
''');

      // The facts JSON produced by extract_facts, written to a temp facts dir.
      final factsDir = Directory(p.join(tmp.path, 'facts'))..createSync();
      File(p.join(factsDir.path, 'maps.json')).writeAsStringSync(jsonEncode({
        'name': 'appbox_kit_maps',
        'version': '0.2.0',
        'description': 'Plugin-neutral maps port.',
        'publicSurface': [
          {'name': 'AppBoxKitMapView', 'kind': 'class', 'file': 'appbox_kit_map_view.dart'},
        ],
      }));

      final facts = loadKitFacts(
        File(p.join(factsDir.path, 'maps.json')),
        kitDir,
      );
      final mdx = generatePlaybook(facts);

      // The README was attached and its sections mined into prose.
      expect(facts['readme'], isA<String>());
      expect(mdx, contains('Render `AppBoxKitMapView` and pass a `AppBoxKitMapConfig`.'));
      expect(mdx, contains('Standalone leaf — no sibling-kit dependency.'));
      expect(mdx, contains('### Usage & wiring'));
      expect(mdx, contains('### Architecture'));
    });

    test('empty facts do not crash and emit TODO(prose) markers', () {
      final mdx = generatePlaybook(<String, dynamic>{});

      expect(mdx, contains('<Callout id="header"'));

      // No public surface -> fallback API row + a features placeholder.
      expect(mdx, contains('no public symbols extracted'));
      expect(mdx, contains('See README for the feature list'));

      // Narrative sections with no source are flagged for the prose pass.
      expect(mdx, contains('TODO(prose)'));
      expect(mdx, contains('### Overview & role'));
    });

    test('never references stacked_kit; branding is appbox_kit', () {
      final facts = <String, dynamic>{
        'name': 'appbox_kit_auth',
        'version': '1.0.0',
        'description': 'Auth kit.',
        'publicSurface': [
          {'name': 'AppBoxKitAuth', 'kind': 'class', 'file': 'appbox_kit_auth.dart'},
        ],
        'frameworkDeps': ['stacked'],
        'backingPackages': <String>[],
        'kitDeps': <String>[],
      };

      final mdx = generatePlaybook(facts);

      // The stacked_kit repo brand never appears; the package name does.
      expect(mdx, isNot(contains('stacked_kit')));
      expect(mdx, contains('appbox_kit_auth'));

      // The Stacked *framework* is still named — it is a real runtime dep,
      // distinct from the stacked_kit brand.
      expect(mdx, contains('Stacked framework deps'));
    });

    test('splits test doubles out of the public API surface', () {
      final facts = <String, dynamic>{
        'name': 'appbox_kit_haptics',
        'version': '0.1.0',
        'description': 'Haptics kit.',
        'hasTesting': true,
        'publicSurface': [
          {'name': 'AppBoxKitHaptics', 'kind': 'class', 'file': 'appbox_kit_haptics.dart'},
          {'name': 'FakeHaptics', 'kind': 'class', 'file': 'testing.dart'},
          {'name': 'RecordingHapticCounter', 'kind': 'class', 'file': 'testing.dart'},
        ],
      };

      final mdx = generatePlaybook(facts);

      // The real symbol stays in the API table.
      expect(mdx, contains('AppBoxKitHaptics'));

      // Fakes route to the test-doubles line, not the API columns; the
      // hasTesting flag adds the call-count note.
      expect(mdx, contains('Test doubles in `lib/testing.dart`'));
      expect(mdx, contains('`FakeHaptics`'));
      expect(mdx, contains('`RecordingHapticCounter`'));
      expect(mdx, contains('Scripts and call-counts'));
    });
  });
}
