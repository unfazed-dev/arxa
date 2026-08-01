// kb_build test — verifies the combined port of kb_build.py + build_toc.py:
// domain-page grouping, package mining, the coverage table, References
// injection (idempotent), the TOC output format, and the first_sentence helper.
//
// All fixtures are written into a temp repo root; no real repo state is touched.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/kb_build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kb-build-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('firstSentence', () {
    test('null / empty -> empty', () {
      expect(firstSentence(null), '');
      expect(firstSentence(''), '');
    });

    test('no ". " separator gets a single trailing period', () {
      expect(firstSentence('Hello world'), 'Hello world.');
    });

    test('stops at the first ". "', () {
      expect(firstSentence('First. Second. Third'), 'First.');
    });

    test('trailing dots are trimmed to one', () {
      expect(firstSentence('Done...'), 'Done.');
    });

    test('keeps internal punctuation', () {
      expect(firstSentence('Auth, sessions, and OAuth. Then more.'), 'Auth, sessions, and OAuth.');
    });
  });

  group('mdLink', () {
    test('with notes', () {
      final s = Source(
        id: 'a',
        title: 'Dart docs',
        url: 'https://dart.dev',
        kind: 'official',
        domain: 'dart',
        kits: const ['*'],
        notes: 'lang docs',
      );
      expect(mdLink(s), '- [Dart docs](https://dart.dev) — lang docs');
    });

    test('without notes', () {
      final s = Source(
        id: 'a',
        title: 'Dart docs',
        url: 'https://dart.dev',
        kind: 'official',
        domain: 'dart',
        kits: const ['*'],
      );
      expect(mdLink(s), '- [Dart docs](https://dart.dev)');
    });
  });

  group('referencesFor', () {
    test('splits framework-wide vs kit-specific', () {
      final srcs = <Source>[
        // wildcard official -> framework
        Source(id: 'dart', title: 'Dart', url: 'u1', kind: 'official',
            domain: 'dart', kits: const ['*']),
        // wildcard package -> framework (mined packages have kits=[kit], so this
        // only happens for an explicit wildcard package entry)
        Source(id: 'pkg', title: 'P', url: 'u2', kind: 'package',
            domain: 'flutter', kits: const ['*']),
        // explicit auth -> own
        Source(id: 'own', title: 'Own', url: 'u3', kind: 'community',
            domain: 'community', kits: const ['auth']),
        // forms-only -> excluded from auth
        Source(id: 'skip', title: 'Skip', url: 'u4', kind: 'community',
            domain: 'community', kits: const ['forms']),
      ];
      final refs = referencesFor('auth', srcs);

      expect(refs, startsWith('Official docs and tooling:\n'));
      expect(refs, contains('- [Dart](u1)'));
      expect(refs, contains('- [P](u2)'));
      expect(refs, contains('Kit-specific:'));
      expect(refs, contains('- [Own](u3)'));
      expect(refs, isNot(contains('[Skip]')));
    });

    test('no Kit-specific section when none are own', () {
      final srcs = <Source>[
        Source(id: 'dart', title: 'Dart', url: 'u1', kind: 'official',
            domain: 'dart', kits: const ['*']),
      ];
      final refs = referencesFor('auth', srcs);
      expect(refs, isNot(contains('Kit-specific')));
    });
  });

  group('injectReferences', () {
    test('idempotent — running twice yields identical output', () {
      final srcs = <Source>[
        Source(id: 'dart', title: 'Dart', url: 'u1', kind: 'official',
            domain: 'dart', kits: const ['*']),
      ];
      final facts = <String, Fact>{
        'auth': const Fact(kit: 'auth', name: 'appbox_kit_auth'),
      };
      final pb = p.join(tmp.path, 'auth', 'auth_playbook.mdx');
      _file(tmp, 'auth/auth_playbook.mdx',
          '# Auth playbook\n\nIntro.\n\n<!-- kb:begin -->\nOLD\n<!-- kb:end -->\n\nMore.\n');

      expect(injectReferences(tmp.path, srcs, facts), 1);

      final after1 = File(pb).readAsStringSync();
      expect(after1, contains('### References'));
      expect(after1, contains('- [Dart](u1)'));
      expect(after1, isNot(contains('OLD')));
      // surrounding text is preserved.
      expect(after1, startsWith('# Auth playbook\n'));
      expect(after1, contains('More.'));

      // second run writes nothing (byte-identical).
      injectReferences(tmp.path, srcs, facts);
      expect(File(pb).readAsStringSync(), after1);
    });

    test('playbook without markers is left unchanged', () {
      final srcs = <Source>[
        Source(id: 'dart', title: 'Dart', url: 'u1', kind: 'official',
            domain: 'dart', kits: const ['*']),
      ];
      final facts = <String, Fact>{
        'auth': const Fact(kit: 'auth', name: 'appbox_kit_auth'),
      };
      final pb = p.join(tmp.path, 'auth', 'auth_playbook.mdx');
      _file(tmp, 'auth/auth_playbook.mdx', '# Auth\n\nNo markers here.\n');
      final before = File(pb).readAsStringSync();

      injectReferences(tmp.path, srcs, facts);

      expect(File(pb).readAsStringSync(), before);
    });

    test('missing playbook file is skipped (count reflects found files)', () {
      final facts = <String, Fact>{
        'auth': const Fact(kit: 'auth', name: 'appbox_kit_auth'),
      };
      // no playbook file on disk
      expect(injectReferences(tmp.path, const <Source>[], facts), 0);
    });
  });

  group('buildKb', () {
    test('writes KB.md + 5 domain pages and reports counts', () {
      _sources(tmp, [
        {
          'id': 'dart-doc',
          'title': 'Dart docs',
          'url': 'https://dart.dev',
          'kind': 'official',
          'domain': 'dart',
          'kits': ['*'],
        },
        {
          'id': 'flutter-doc',
          'title': 'Flutter docs',
          'url': 'https://flutter.dev',
          'kind': 'official',
          'domain': 'flutter',
          'kits': ['*'],
        },
      ]);
      _fact(tmp, 'auth', {
        'kit': 'auth',
        'name': 'appbox_kit_auth',
        'description': 'Auth and session. More detail.',
        'backingPackages': ['firebase_auth'],
      });

      final r = buildKb(tmp.path);

      expect(r.registrySources, 2);
      expect(r.minedPackageRefs, 1);
      expect(r.domainPages, 5);

      final kb = File(p.join(tmp.path, 'kb', 'KB.md'));
      expect(kb.existsSync(), isTrue);
      expect(kb.readAsStringSync(), contains('# appbox kit knowledge base'));

      for (final name in const [
        'stacked.md',
        'flutter.md',
        'dart.md',
        'mcp.md',
        'community.md',
      ]) {
        final f = File(p.join(tmp.path, 'kb', name));
        expect(f.existsSync(), isTrue, reason: name);
      }
    });

    test('creates kb/ dir when it does not exist', () {
      _fact(tmp, 'auth', {'kit': 'auth', 'name': 'appbox_kit_auth'});
      // deliberately no kb/ dir and no sources.json

      final r = buildKb(tmp.path);

      expect(r.registrySources, 0);
      expect(r.minedPackageRefs, 0);
      expect(File(p.join(tmp.path, 'kb', 'KB.md')).existsSync(), isTrue);
    });

    test('domain pages group mined packages by kit (sorted)', () {
      _sources(tmp, [
        {
          'id': 'dart-doc',
          'title': 'Dart docs',
          'url': 'https://dart.dev',
          'kind': 'official',
          'domain': 'dart',
          'kits': ['*'],
          'notes': 'lang docs',
        },
      ]);
      _fact(tmp, 'forms', {
        'kit': 'forms',
        'name': 'appbox_kit_forms',
        'backingPackages': ['c_pkg'],
      });
      _fact(tmp, 'auth', {
        'kit': 'auth',
        'name': 'appbox_kit_auth',
        'backingPackages': ['a_pkg', 'b_pkg'],
      });

      buildKb(tmp.path);

      // all mined packages are domain 'flutter'.
      final flutter =
          File(p.join(tmp.path, 'kb', 'flutter.md')).readAsStringSync();
      expect(flutter, contains('# Flutter'));
      expect(flutter, contains('3 curated source(s).'));
      expect(flutter, contains('## Backing packages (per kit)'));
      // kits sorted: auth before forms.
      expect(flutter.indexOf('**auth**'), lessThan(flutter.indexOf('**forms**')));
      expect(flutter, contains('a_pkg (pub.dev)'));
      expect(flutter, contains('pub.dev/packages/b_pkg'));
      expect(flutter, contains('backing dependency of appbox_kit_forms'));

      // dart domain has the official source and NO backing-packages section.
      final dart = File(p.join(tmp.path, 'kb', 'dart.md')).readAsStringSync();
      expect(dart, contains('1 curated source(s).'));
      expect(dart, contains('- [Dart docs](https://dart.dev) — lang docs'));
      expect(dart, isNot(contains('Backing packages')));

      // empty domain still gets a page.
      final mcp = File(p.join(tmp.path, 'kb', 'mcp.md')).readAsStringSync();
      expect(mcp, contains('# MCP servers'));
      expect(mcp, contains('0 curated source(s).'));
    });

    test('coverage table flags kits below 3 sources', () {
      _sources(tmp, [
        {
          'id': 'dart-doc',
          'title': 'Dart docs',
          'url': 'https://dart.dev',
          'kind': 'official',
          'domain': 'dart',
          'kits': ['*'],
        },
      ]);
      _fact(tmp, 'auth', {'kit': 'auth', 'name': 'appbox_kit_auth'});

      buildKb(tmp.path);

      final kb = File(p.join(tmp.path, 'kb', 'KB.md')).readAsStringSync();
      // auth has 1 wildcard source -> flagged.
      expect(kb, contains('| auth | 1 |'));
      expect(kb, contains('`auth_playbook.mdx`](../auth/auth_playbook.mdx)'));
      expect(kb, contains('**< 3 — add sources**'));
    });

    test('mined package counts toward the owning kit only', () {
      _fact(tmp, 'auth', {
        'kit': 'auth',
        'name': 'appbox_kit_auth',
        'backingPackages': ['pkg1', 'pkg2', 'pkg3'],
      });
      buildKb(tmp.path);

      final kb = File(p.join(tmp.path, 'kb', 'KB.md')).readAsStringSync();
      // auth has exactly 3 mined package sources -> not flagged.
      expect(kb, contains('| auth | 3 |'));
      expect(kb, isNot(contains('add sources')));
    });
  });

  group('buildToc', () {
    test('emits playbooks.md table + llms.txt sections', () {
      _fact(tmp, 'forms', {'kit': 'forms', 'name': 'appbox_kit_forms',
        'description': 'Forms.'});
      _fact(tmp, 'auth', {
        'kit': 'auth',
        'name': 'appbox_kit_auth',
        'description': 'Auth and session. Extra detail.',
        'readmeLines': 42,
      });

      final r = buildToc(tmp.path);

      expect(r.kitCount, 2);
      expect(File(p.join(tmp.path, 'playbooks.md')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'llms.txt')).existsSync(), isTrue);

      // playbooks.md
      expect(r.playbooksMd, startsWith('# appbox kit — playbooks index'));
      expect(r.playbooksMd, contains('| Kit | Role | Playbook | README | Status |'));
      // auth: first sentence role, README link present (readmeLines>0).
      expect(
          r.playbooksMd,
          contains('| `appbox_kit_auth` | Auth and session. | '
              '[auth_playbook.mdx](auth/auth_playbook.mdx) | '
              '[README](auth/README.md) | active |'));
      // forms: no readmeLines -> README column is an em dash; rows are sorted
      // (auth before forms).
      expect(r.playbooksMd, contains('— | active |'));
      expect(r.playbooksMd, isNot(contains('[README](forms/README.md)')));
      expect(r.playbooksMd.indexOf('appbox_kit_auth'),
          lessThan(r.playbooksMd.indexOf('appbox_kit_forms')));

      // llms.txt
      expect(r.llmsTxt, startsWith('# appbox kit'));
      expect(r.llmsTxt, contains('## Playbooks'));
      expect(
          r.llmsTxt,
          contains('- [appbox_kit_auth playbook](auth/auth_playbook.mdx): '
              'Auth and session.'));
      expect(r.llmsTxt, contains('## Knowledge base'));
      expect(r.llmsTxt, contains('## Orientation'));
      expect(r.llmsTxt, contains('## Optional'));
    });

    test('role falls back to readmeFirst then name when description is absent', () {
      _fact(tmp, 'auth', {
        'kit': 'auth',
        'name': 'appbox_kit_auth',
        'readmeFirst': 'Readme-first role.',
      });
      _fact(tmp, 'forms', {'kit': 'forms', 'name': 'appbox_kit_forms'});

      final r = buildToc(tmp.path);

      // playbooks.md: readmeFirst fallback for auth.
      expect(r.playbooksMd, contains('| `appbox_kit_auth` | Readme-first role. |'));
      // playbooks.md + llms.txt: name fallback for forms (no description).
      expect(r.playbooksMd, contains('appbox_kit_forms` | appbox_kit_forms |'));
      expect(r.llmsTxt,
          contains(': appbox_kit_forms'));
    });

    test('empty facts dir produces headers with no kit rows', () {
      // no facts written; memory/facts absent entirely.
      final r = buildToc(tmp.path);
      expect(r.kitCount, 0);
      expect(r.playbooksMd, contains('| --- | --- | --- | --- | --- |'));
      expect(r.llmsTxt, contains('## Playbooks'));
    });
  });
}

/// Write kb/sources.json with the given source list.
void _sources(Directory root, List<Map<String, dynamic>> sources) {
  Directory(p.join(root.path, 'kb')).createSync(recursive: true);
  File(p.join(root.path, 'kb', 'sources.json'))
      .writeAsStringSync(jsonEncode({'sources': sources}));
}

/// Write `memory/facts/<kit>.json` (kit schema).
void _fact(Directory root, String kit, Map<String, dynamic> fact) {
  Directory(p.join(root.path, 'memory', 'facts')).createSync(recursive: true);
  File(p.join(root.path, 'memory', 'facts', '$kit.json'))
      .writeAsStringSync(jsonEncode(fact));
}

/// Create a file (with parent dirs) and write [content].
void _file(Directory root, String relPath, String content) {
  final f = File(p.join(root.path, relPath));
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
}
