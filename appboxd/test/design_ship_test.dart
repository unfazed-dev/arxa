// Tests for the Ship channel (slice 5, rework 2026-08-24): the confined
// git+gh autopilot. The runner is faked and every argv captured — the
// safety laws are asserted on the actual command stream, not on prose:
// no force flags anywhere, merge re-enforces green, conflicts abort
// cleanly, guests 403, non-repo 503.
library;

import 'package:appboxd/design_dial.dart';
import 'package:appboxd/design_ship.dart';
import 'package:test/test.dart';

void main() {
  group('DialShip laws', () {
    test('commitAndPr runs the exact automated prefix, never touching main',
        () async {
      final calls = <(String, List<String>)>[];
      Map<String, ShipProc> respond(String cmd, List<String> args) {
        calls.add((cmd, args));
        if (const ['status', '--porcelain', '/art'].join(' ') ==
            args.skip(2).join(' ')) {
          return const {'git': ShipProc(0, 'M x.tsx\n')};
        }
        if (args.contains('rev-parse')) return const {'git': ShipProc(0, 'main')};
        if (args.contains('checkout')) return const {'git': ShipProc(0, '')};
        if (args.contains('commit')) return const {'git': ShipProc(0, '[branch abc]')};
        if (args.contains('push')) return const {'git': ShipProc(0, '')};
        if (args.contains('pr')) {
          return const {'gh': ShipProc(0, 'https://github.com/x/y/pull/1')};
        }
        return const {'git': ShipProc(0, '')};
      }

      // Build a runner that answers via respond()
      Future<ShipProc> run(String cmd, List<String> args) async =>
          respond(cmd, args)[cmd]!;

      final ship = DialShip(repoDir: '/repo', run: run);
      final r = await ship.commitAndPr(
          artifactDir: '/art', title: 'design(dial): batch', body: 'ops');
      expect(r['url'], contains('pull/1'));
      final flat = calls.map((c) => '${c.$1} ${c.$2.join(' ')}').toList();
      // The exact prefix sequence
      expect(flat, contains('git -C /repo status --porcelain /art'));
      expect(flat, contains('git -C /repo rev-parse --abbrev-ref HEAD'));
      expect(
          flat
              .where((c) => c.contains('checkout'))
              .first,
          contains('checkout -b design/dial-'));
      expect(flat, contains('git -C /repo add -- /art'));
      expect(flat.any((c) => c.contains(' push -u origin ')), isTrue);
      expect(flat.any((c) => c.contains('pr create') && c.contains('--base main')),
          isTrue);
      // THE LAW: no force anywhere, ever
      expect(flat.any((c) => c.contains('--force') || c.contains(' -f ')),
          isFalse);
    });

    test('nothing to ship refuses with 409-shaped refusal', () async {
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        if (args.contains('--porcelain')) return const ShipProc(0, '');
        return const ShipProc(0, 'main');
      });
      await expectLater(
          ship.commitAndPr(artifactDir: '/art', title: 't', body: 'b'),
          throwsA(isA<ShipRefusal>()));
    });

    test('not on main refuses — one design PR at a time', () async {
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        if (args.contains('--porcelain')) return const ShipProc(0, 'M x');
        if (args.contains('rev-parse')) return const ShipProc(0, 'design/dial-1');
        return const ShipProc(0, '');
      });
      try {
        await ship.commitAndPr(artifactDir: '/art', title: 't', body: 'b');
        fail('refused');
      } on ShipRefusal catch (e) {
        expect(e.message, contains('design/dial-1'));
      }
    });

    test('merge re-enforces green: failing checks refuse', () async {
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        if (cmd == 'gh' && args.contains('view')) {
          return const ShipProc(0,
              '{"number":7,"title":"t","state":"OPEN","mergeable":true,'
              '"url":"u","headRefName":"b",'
              '"statusCheckRollup":[{"name":"ci","status":"completed","conclusion":"FAILURE"}]}');
        }
        return const ShipProc(0, '');
      });
      try {
        await ship.merge();
        fail('refused');
      } on ShipRefusal catch (e) {
        expect(e.message, contains('failing'));
      }
    });

    test('merge re-enforces green: pending checks refuse', () async {
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        if (cmd == 'gh' && args.contains('view')) {
          return const ShipProc(0,
              '{"number":7,"title":"t","state":"OPEN","mergeable":true,'
              '"url":"u","headRefName":"b",'
              '"statusCheckRollup":[{"name":"ci","status":"in_progress","conclusion":""}]}');
        }
        return const ShipProc(0, '');
      });
      try {
        await ship.merge();
        fail('refused');
      } on ShipRefusal catch (e) {
        expect(e.message, contains('running'));
      }
    });

    test('merge green path is squash + delete-branch, no force', () async {
      final calls = <String>[];
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        calls.add('$cmd ${args.join(' ')}');
        if (cmd == 'gh' && args.contains('view')) {
          return const ShipProc(0,
              '{"number":7,"title":"t","state":"OPEN","mergeable":true,'
              '"url":"u","headRefName":"b",'
              '"statusCheckRollup":[{"name":"ci","status":"completed","conclusion":"SUCCESS"}]}');
        }
        return const ShipProc(0, '');
      });
      final r = await ship.merge();
      expect(r['merged'], '7');
      expect(calls.any((c) => c.contains('pr merge 7 --squash --delete-branch')),
          isTrue);
      expect(calls.any((c) => c.contains('--force')), isFalse);
    });

    test('sync aborts a conflicted rebase and says so', () async {
      final calls = <String>[];
      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        calls.add('$cmd ${args.join(' ')}');
        if (args.contains('checkout')) return const ShipProc(0, '');
        if (args.contains('pull')) return const ShipProc(1, '', 'CONFLICT');
        return const ShipProc(0, '');
      });
      try {
        await ship.sync();
        fail('refused');
      } on ShipRefusal catch (e) {
        expect(e.message, contains('conflicts'));
      }
      expect(calls.any((c) => c.contains('rebase --abort')), isTrue);
    });
  });

  group('dial routes: /ship/*', () {
    test('guest 403; ship null 503; status passes through', () async {
      final off = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final r503 =
          await off.handle('GET', '/ship/status', {}, null, null);
      expect(r503.status, 503);

      final ship = DialShip(repoDir: '/repo', run: (cmd, args) async {
        if (args.contains('get-url')) {
          return const ShipProc(0, 'https://github.com/unfazed-dev/x.git');
        }
        if (args.contains('rev-parse')) return const ShipProc(0, 'main');
        if (cmd == 'gh') return const ShipProc(1, 'no PR');
        return const ShipProc(0, '');
      });
      final api = DialApi(
          store: MemoryDialStore(), artifact: 'demo', ship: ship);
      final ok = await api.handle('GET', '/ship/status', {}, null, null);
      expect(ok.status, 200);
      final j = (ok.json as Map).cast<String, dynamic>();
      expect(j['repo'], 'unfazed-dev/x');
      expect(j['branch'], 'main');
      expect(j['pr'], isNull);

      final guest = await api.handle(
          'GET', '/ship/status', {}, null,
          ShareLinkGrant(artifact: 'demo', expiresAt: '2099-01-01T00:00:00Z'));
      expect(guest.status, 403);
    });
  });
}
