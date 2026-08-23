// design_dial_test.dart — the Design Dial Feedback Mode core (decisions
// 1/6/7/9 of the 2026-08-23 amendment). Pure-core tests: no HTTP server, no
// Chrome — DialApi.handle is a pure function and MemoryDialStore is real.

import 'package:appboxd/design_dial.dart';
import 'package:test/test.dart';

Map<String, dynamic> pinBody({
  String route = '/pricing',
  String body = 'make this pop',
  String? el = 'pricing.cta',
  String? name,
}) =>
    {
      'route': route,
      'body': body,
      'viewport': {'w': 1280, 'h': 800},
      'anchor': {
        if (el != null) 'el': el,
        'rect': {'x': 10.0, 'y': 20.0, 'w': 83.0, 'h': 32.0},
      },
      if (name != null) 'name': name,
    };

void main() {
  group('MemoryDialStore', () {
    test('pin lifecycle: create, list, status, reply', () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final created = await api.handle('POST', '/pins', {}, pinBody(), null);
      expect(created.status, 201);
      final pin =
          ((created.json as Map)['pin'] as Map).cast<String, dynamic>();
      expect(pin['status'], 'open');
      expect(pin['author'], 'author');

      final listed = await api.handle('GET', '/pins', {}, null, null);
      expect((listed.json as Map)['store'], 'memory');
      expect(((listed.json as Map)['pins'] as List).length, 1);

      final moved = await api.handle(
          'POST', '/pins/status', {}, {'id': pin['id'], 'status': 'triaged'}, null);
      expect(moved.status, 200);
      expect(((moved.json as Map)['pin'] as Map)['status'], 'triaged');

      final replied = await api.handle('POST', '/pins/reply', {},
          {'id': pin['id'], 'body': 'on it'}, null);
      expect(replied.status, 201);
      final after = await api.handle('GET', '/pins', {}, null, null);
      final pins = (after.json as Map)['pins'] as List;
      expect((pins.first['replies'] as List).single['body'], 'on it');
    });

    test('unknown ids are 404, never silent', () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final s = await api.handle(
          'POST', '/pins/status', {}, {'id': 'nope', 'status': 'open'}, null);
      expect(s.status, 404);
      final r = await api.handle(
          'POST', '/pins/reply', {}, {'id': 'nope', 'body': 'x'}, null);
      expect(r.status, 404);
    });
  });

  group('kanban vocabulary (decision 9)', () {
    test('the wire set is closed and exact', () {
      for (final s in ['open', 'triaged', 'in_progress', 'resolved', 'wont_do']) {
        expect(DialPinStatus.parse(s), isNotNull, reason: s);
      }
      expect(DialPinStatus.parse('done'), isNull);
      expect(DialPinStatus.parse('Open'), isNull);
      expect(DialPinStatus.parse(null), isNull);
    });

    test('a bad status is a 400 naming the set', () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final created = await api.handle('POST', '/pins', {}, pinBody(), null);
      final id = ((created.json as Map)['pin'] as Map)['id'];
      final r = await api.handle(
          'POST', '/pins/status', {}, {'id': id, 'status': 'done'}, null);
      expect(r.status, 400);
      expect((r.json as Map)['error'] as String, contains('wont_do'));
    });
  });

  group('guest access (decisions 1/7)', () {
    test('guests pin and reply but CANNOT move the kanban or mint links',
        () async {
      final store = MemoryDialStore();
      final api = DialApi(store: store, artifact: 'demo');
      final minted =
          await api.handle('POST', '/share', {}, {'days': 7}, null);
      expect(minted.status, 201);
      final token = (minted.json as Map)['token'] as String;
      final grant = await store.resolveShareLink(token);
      expect(grant, isNotNull);
      expect(grant!.artifact, 'demo');

      // Guest creates a pin and a reply.
      final gp = await api.handle(
          'POST', '/pins', {}, pinBody(name: 'Client Claire'), grant);
      expect(gp.status, 201);
      expect(((gp.json as Map)['pin'] as Map)['author'], 'guest');
      expect(((gp.json as Map)['pin'] as Map)['name'], 'Client Claire');
      final pid = ((gp.json as Map)['pin'] as Map)['id'];
      final gr = await api.handle(
          'POST', '/pins/reply', {}, {'id': pid, 'body': '+1'}, grant);
      expect(gr.status, 201);

      // Guest kanban move: refused. Guest share mint: refused.
      final gs = await api.handle('POST', '/pins/status', {},
          {'id': pid, 'status': 'resolved'}, grant);
      expect(gs.status, 403);
      final gm = await api.handle('POST', '/share', {}, null, grant);
      expect(gm.status, 403);
    });

    test('a link scopes to ITS artifact only', () async {
      final store = MemoryDialStore();
      final a = DialApi(store: store, artifact: 'demo');
      final token =
          ((await a.handle('POST', '/share', {}, null, null)).json
              as Map)['token'] as String;
      final grant = await store.resolveShareLink(token);
      final other = DialApi(store: store, artifact: 'other-project');
      final r = await other.handle('GET', '/pins', {}, null, grant);
      expect(r.status, 403);
    });

    test('expired links resolve to nothing', () async {
      final store = MemoryDialStore();
      final raw = await store.mintShareLink('demo', const Duration(days: 1));
      expect(await store.resolveShareLink(raw), isNotNull);
      // Forge expiry in the past by minting zero-width: a 0-day ttl is
      // rejected by the API cap (days 1..365), so test the grant itself.
      const expired = ShareLinkGrant(
          artifact: 'demo', expiresAt: '2000-01-01T00:00:00.000Z');
      expect(expired.expired, isTrue);
      const immortal = ShareLinkGrant(artifact: 'demo', expiresAt: null);
      expect(immortal.expired, isFalse);
    });
  });

  group('validation', () {
    test('missing route / bad viewport / oversize body / bad rect → 400',
        () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      Future<int> post(Map<String, dynamic> b) async =>
          (await api.handle('POST', '/pins', {}, b, null)).status;

      final noRoute = pinBody()..remove('route');
      expect(await post(noRoute), 400);

      final badVp = pinBody()..['viewport'] = {'w': 0, 'h': 800};
      expect(await post(badVp), 400);

      expect(await post(pinBody(body: 'x' * 4001)), 400);

      final badRect = pinBody();
      (badRect['anchor'] as Map)['rect'] = {'x': 1, 'y': 2, 'w': 3};
      expect(await post(badRect), 400);

      final nanRect = pinBody();
      (nanRect['anchor'] as Map)['rect'] =
          {'x': 1, 'y': 2, 'w': 3, 'h': double.nan};
      expect(await post(nanRect), 400);

      expect(await api.handle('DELETE', '/pins', {}, null, null)
          .then((r) => r.status), 404);
      expect(await api.handle('GET', '/nope', {}, null, null)
          .then((r) => r.status), 404);
    });

    test('surface-level pins (no data-el) are legal — the sentinel case',
        () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final r = await api.handle('POST', '/pins', {}, pinBody(el: null), null);
      expect(r.status, 201);
      expect(((r.json as Map)['pin'] as Map)['anchor']['el'], isNull);
    });
  });

  group('drawings attach to pins (locked 2026-08-23)', () {
    test('a pin carries its drawing through the store and toJson', () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final b = pinBody();
      b['drawing'] = [
        [
          [1.0, 2.0],
          [3.5, 4.5],
        ],
        [
          [10.0, 10.0],
          [20.0, 20.0],
          [30.0, 25.0],
        ],
      ];
      final created = await api.handle('POST', '/pins', {}, b, null);
      expect(created.status, 201);
      final pin = ((created.json as Map)['pin'] as Map).cast<String, dynamic>();
      expect((pin['drawing'] as List).length, 2);

      final listed = await api.handle('GET', '/pins', {}, null, null);
      final found = ((listed.json as Map)['pins'] as List).single;
      expect((found['drawing'] as List)[1][2], [30.0, 25.0]);
    });

    test('no drawing → key absent (lean rows), malformed drawings → 400', () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final plain = await api.handle('POST', '/pins', {}, pinBody(), null);
      expect(plain.status, 201);
      expect(((plain.json as Map)['pin'] as Map).containsKey('drawing'), isFalse);

      Future<int> bad(Object? drawing) async {
        final b = pinBody();
        b['drawing'] = drawing;
        return (await api.handle('POST', '/pins', {}, b, null)).status;
      }

      expect(await bad('not-an-array'), 400);
      expect(await bad(List.filled(65, [[1, 2]])), 400); // stroke cap
      expect(await bad([List.filled(2001, [1, 2])]), 400); // per-stroke cap
      expect(await bad([[1]]), 400); // point shape
      expect(await bad([[]]), 400); // empty stroke
      expect(
          await bad([
            [
              [1, 2],
              [3, double.nan],
            ],
          ]),
          400); // non-finite
      expect(
          await bad(List.filled(5, List.filled(1601, [1, 2]))),
          400); // 8005 total > 8000
    });
  });

  group('SupabaseDialStore.fromEnv', () {
    test('null without BOTH vars; the memory fallback is the default', () {
      expect(SupabaseDialStore.fromEnv(const {}), isNull);
      expect(
          SupabaseDialStore.fromEnv(
              const {'APPBOX_SUPABASE_URL': 'https://x.supabase.co'}),
          isNull);
      final s = SupabaseDialStore.fromEnv(const {
        'APPBOX_SUPABASE_URL': 'https://x.supabase.co',
        'APPBOX_SUPABASE_SERVICE_KEY': 'k',
      });
      expect(s, isNotNull);
      expect(s!.kind, 'supabase');
    });
  });

  group('the ~/.appbox/supabase credentials file', () {
    test('parses key=value lines, tolerates comments and junk', () {
      final c = parseSupabaseCredentials(
          '# operator project\nurl=https://x.supabase.co\n\n'
          'service_key=abc123 # trailing comment\njunk line\n=nope\n');
      expect(c.url, 'https://x.supabase.co');
      expect(c.key, 'abc123');
      expect(parseSupabaseCredentials('').url, isNull);
      expect(parseSupabaseCredentials('url=x').key, isNull);
    });

    test('env wins over the file; the file fills what env lacks', () {
      final both = SupabaseDialStore.fromConfig(
        env: const {
          'APPBOX_SUPABASE_URL': 'https://env.supabase.co',
          'APPBOX_SUPABASE_SERVICE_KEY': 'envkey',
        },
        credentialsFileText: 'url=https://file.supabase.co\nservice_key=filekey',
      );
      expect(both!.url, 'https://env.supabase.co');
      expect(both.serviceKey, 'envkey');

      final fileOnly = SupabaseDialStore.fromConfig(
        env: const {},
        credentialsFileText: 'url=https://file.supabase.co\nservice_key=filekey',
      );
      expect(fileOnly!.url, 'https://file.supabase.co');

      // A half-written file degrades to null (→ memory store), never a crash.
      expect(
          SupabaseDialStore.fromConfig(
              env: const {}, credentialsFileText: 'url=https://x.co'),
          isNull);

      // The shipped placeholder is 'absent', not a key.
      expect(
          SupabaseDialStore.fromConfig(
              env: const {},
              credentialsFileText:
                  'url=https://x.co\nservice_key=PASTE-SERVICE-ROLE-KEY-HERE'),
          isNull);
    });
  });
}
