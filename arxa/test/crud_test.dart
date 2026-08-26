// crud test — round-trips for create/update/rename/delete/verify through the
// real dispatch (crudMain), on temp dirs with dummy registries. Mirrors the
// archived Python self-test's discriminating cases.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/crud.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('crud-test-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Plant a design root with the given registry JSON (default: empty array).
  String root({String registry = '[]'}) {
    final root = '${tmp.path}/design';
    Directory('$root/models/screens_model').createSync(recursive: true);
    File('$root/models/screens_model/registry.json').writeAsStringSync(registry);
    return root;
  }

  /// Decode the registry back from disk.
  List<Map<String, dynamic>> regOf(String root) {
    final raw =
        File('$root/models/screens_model/registry.json').readAsStringSync();
    return [
      for (final e in jsonDecode(raw) as List) e as Map<String, dynamic>
    ];
  }

  test('create appends entry in canonical key order + writes the pair', () {
    final r = root();
    final rc = crudMain([
      'create', r,
      '--id', 'proj.home',
      '--shell', 'proj',
      '--comp', 'ProjHome',
      '--surface', 'proj_home_view',
      '--label', 'Home',
    ]);
    expect(rc, 0, reason: 'create succeeds');

    final reg = regOf(r);
    expect(reg, hasLength(1));
    expect(reg.first['id'], 'proj.home');
    // frozen key order — round-trips are byte-stable
    expect(reg.first.keys.toList(),
        ['id', 'label', 'surface', 'shell', 'comp']);
    expect(reg.first['surface'], 'proj_home_view');

    // pair: ui/views/<shell>/<short>/ where short is the last '.'-segment
    final dir = '$r/ui/views/proj/home';
    final view = File('$dir/home_view.html').readAsStringSync();
    final vm = File('$dir/home_viewmodel.js').readAsStringSync();
    expect(view, contains('data-surface="proj_home_view"'));
    expect(view, contains('Home'));
    expect(vm, contains("export const surfaceId = 'proj.home';"));
  });

  test('create with surface null/omitted is a declared exclusion (no pair)', () {
    final r = root();
    // --surface null ⇒ coerced to null ⇒ exclusion
    expect(
        crudMain([
          'create', r,
          '--id', 'proj.splash',
          '--shell', 'proj',
          '--comp', 'ProjSplash',
          '--surface', 'null',
        ]),
        0);
    final reg = regOf(r);
    expect(reg.first['surface'], isNull);
    expect(reg.first['label'], '');
    // no pair dir is ever created for a declared exclusion
    expect(Directory('$r/ui/views').existsSync(), isFalse);
  });

  test('create refuses to reuse a stable id (§18)', () {
    final r = root(registry: jsonEncode([
      {'id': 'proj.home', 'label': '', 'surface': null, 'shell': 'proj', 'comp': 'ProjHome'}
    ]));
    final rc = crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'X'
    ]);
    expect(rc, 1, reason: 'duplicate id is rejected');
    // nothing was written — the registry is untouched
    expect(regOf(r), hasLength(1));
  });

  test('update edits the label and refreshes the pair (id/surface immutable)', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);
    final rc = crudMain([
      'update', r, '--id', 'proj.home', '--label', 'Home Page'
    ]);
    expect(rc, 0);
    final reg = regOf(r);
    expect(reg.first['label'], 'Home Page');
    expect(reg.first['id'], 'proj.home', reason: 'id is immutable');
    expect(reg.first['surface'], 'proj_home_view', reason: 'surface is immutable');
    // the view body carries the refreshed label
    expect(File('$r/ui/views/proj/home/home_view.html').readAsStringSync(),
        contains('Home Page'));
  });

  test('update preserves extra keys when re-serializing in canonical order', () {
    final r = root(registry: jsonEncode([
      {
        'id': 'proj.home', 'label': 'Home', 'surface': 'proj_home_view',
        'shell': 'proj', 'comp': 'ProjHome',
        'note': 'hand-authored extra' // extra key must survive
      }
    ]));
    // also plant the pair so writePair's dir already exists
    Directory('$r/ui/views/proj/home').createSync(recursive: true);
    File('$r/ui/views/proj/home/home_viewmodel.js')
        .writeAsStringSync("export const surfaceId = 'proj.home';\n");

    expect(crudMain(['update', r, '--id', 'proj.home', '--label', 'Home2']), 0);
    final e = regOf(r).first;
    expect(e['label'], 'Home2');
    expect(e['note'], 'hand-authored extra', reason: 'extra key preserved');
    // known keys come first, then extras
    expect(e.keys.toList().sublist(0, 5),
        ['id', 'label', 'surface', 'shell', 'comp']);
  });

  test('rename writes the new pair BEFORE removing the old + records migration', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);

    final rc = crudMain(['rename', r, '--from', 'proj.home', '--to', 'proj.dashboard']);
    expect(rc, 0);

    final reg = regOf(r);
    expect(findId(reg, 'proj.home'), isFalse, reason: 'old id retired');
    expect(findId(reg, 'proj.dashboard'), isTrue, reason: 'new id live');
    expect(reg.firstWhere((e) => e['id'] == 'proj.dashboard')['comp'], 'ProjHome');

    // new pair exists, old pair gone
    expect(File('$r/ui/views/proj/dashboard/dashboard_viewmodel.js').existsSync(),
        isTrue);
    expect(File('$r/ui/views/proj/home/home_viewmodel.js').existsSync(), isFalse);

    // migration lineage recorded, target still live ⇒ not pruned
    final mig = jsonDecode(
        File('$r/models/screens_model/migrations.json').readAsStringSync()) as List;
    expect(mig, hasLength(1));
    expect(mig.first, {
      'op': 'rename', 'from': 'proj.home', 'to': 'proj.dashboard',
      'surface': 'proj_home_view',
    });
  });

  test('rename refuses if --to already exists (id never reused)', () {
    final r = root(registry: jsonEncode([
      {'id': 'a.x', 'label': '', 'surface': null, 'shell': 'a', 'comp': 'X'},
      {'id': 'a.y', 'label': '', 'surface': null, 'shell': 'a', 'comp': 'Y'},
    ]));
    expect(crudMain(['rename', r, '--from', 'a.x', '--to', 'a.y']), 1);
    expect(regOf(r), hasLength(2), reason: 'nothing changed on refusal');
  });

  test('delete removes entry + pair and sweeps to empty ancestors', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);
    // refuses without a human-minted token (removal is not recoverable)
    expect(crudMain(['delete', r, '--id', 'proj.home']), 1);
    expect(regOf(r), hasLength(1), reason: 'no-confirm refusal changes nothing');

    expect(crudMain(['delete', r, '--id', 'proj.home', '--confirm', 'tok-123']), 0);
    expect(regOf(r), isEmpty);
    // the whole ui/views tree collapsed (empty ancestors removed bottom-up)
    expect(Directory('$r/ui/views').existsSync(), isFalse);
  });

  test('delete is idempotent on the desired end state (repairs a mid-crash)', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);
    // simulate a crash: entry already gone, but the pair lingers
    crudMain(['delete', r, '--id', 'proj.home', '--confirm', 't']);
    // second delete converges (no entry to remove, orphan pair swept)
    expect(crudMain(['delete', r, '--id', 'proj.home', '--confirm', 't']), 0);
    expect(regOf(r), isEmpty);
    expect(Directory('$r/ui/views').existsSync(), isFalse);
  });

  test('delete prunes stale migrations whose target is no longer live', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);
    crudMain(['rename', r, '--from', 'proj.home', '--to', 'proj.dashboard']);
    expect(File('$r/models/screens_model/migrations.json').existsSync(), isTrue);

    crudMain(['delete', r, '--id', 'proj.dashboard', '--confirm', 't']);
    expect(File('$r/models/screens_model/migrations.json').existsSync(), isFalse,
        reason: 'lineage to a deleted id is stale debris — removed');
  });

  test('verify OK on a clean tree, FAIL on an orphan pair, --fix repairs it', () {
    final r = root();
    crudMain([
      'create', r, '--id', 'proj.home', '--shell', 'proj', '--comp', 'ProjHome',
      '--surface', 'proj_home_view', '--label', 'Home'
    ]);
    expect(crudMain(['verify', r]), 0, reason: 'clean tree verifies');

    // plant an orphan pair whose surfaceId maps to no live entry
    Directory('$r/ui/views/proj/ghost').createSync(recursive: true);
    File('$r/ui/views/proj/ghost/ghost_viewmodel.js')
        .writeAsStringSync("export const surfaceId = 'proj.ghost';\n");
    expect(crudMain(['verify', r]), 1, reason: 'orphan pair fails the assertion');

    // verify (no --fix) changes nothing
    expect(Directory('$r/ui/views/proj/ghost').existsSync(), isTrue);

    // --fix needs --confirm
    expect(crudMain(['verify', r, '--fix']), 1);
    expect(Directory('$r/ui/views/proj/ghost').existsSync(), isTrue);

    expect(crudMain(['verify', r, '--fix', '--confirm', 'tok']), 0);
    expect(Directory('$r/ui/views/proj/ghost').existsSync(), isFalse,
        reason: '--fix swept the orphan');
    expect(crudMain(['verify', r]), 0, reason: 'clean again after fix');
  });

  test('list and show read the registry', () {
    final r = root(registry: jsonEncode([
      {'id': 'proj.home', 'label': 'Home', 'surface': 'proj_home_view',
       'shell': 'proj', 'comp': 'ProjHome'},
      {'id': 'proj.splash', 'label': '', 'surface': null,
       'shell': 'proj', 'comp': 'ProjSplash'},
    ]));
    expect(crudMain(['list', r]), 0);
    expect(crudMain(['show', r, 'proj.home']), 0);
    expect(crudMain(['show', r, 'nope']), 1, reason: 'unknown id fails');
  });

  test('missing registry / usage errors exit non-zero', () {
    // no registry planted
    expect(crudMain(['list', '${tmp.path}/empty']), 1);
    expect(crudMain([]), 2, reason: 'no operation → usage');
    expect(crudMain(['bogus', 'x']), 2, reason: 'unknown operation → usage');
    expect(crudMain(['create', root(), '--id', 'x']), 2,
        reason: 'missing required --shell/--comp → usage');
  });
}

bool findId(List<Map<String, dynamic>> reg, String id) =>
    reg.any((e) => e['id'] == id);
