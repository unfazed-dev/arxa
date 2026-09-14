// arxa_dial_test.dart — the Arxa Dial Feedback Mode core (decisions
// 1/6/7/9 of the 2026-08-23 amendment). Pure-core tests: no HTTP server, no
// Chrome — DialApi.handle is a pure function and MemoryDialStore is real.

import 'dart:convert';

import 'package:arxa/arxa_dial.dart';
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
        'el': ?el,
        'rect': {'x': 10.0, 'y': 20.0, 'w': 83.0, 'h': 32.0},
      },
      'name': ?name,
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

      // Rework 2026-08-24: exactly open/resolved/wont_do on the wire; the
      // legacy names fold to open (read-side migration lives in parse).
      final moved = await api.handle(
          'POST', '/pins/status', {}, {'id': pin['id'], 'status': 'wont_do'}, null);
      expect(moved.status, 200);
      expect(((moved.json as Map)['pin'] as Map)['status'], 'wont_do');
      expect(DialPinStatus.parse('triaged'), DialPinStatus.open);
      expect(DialPinStatus.parse('in_progress'), DialPinStatus.open);
      expect(DialPinStatus.parse('bogus'), isNull);

      final replied = await api.handle('POST', '/pins/reply', {},
          {'id': pin['id'], 'body': 'on it'}, null);
      expect(replied.status, 201);
      final after = await api.handle('GET', '/pins', {}, null, null);
      final pins = (after.json as Map)['pins'] as List;
      expect((pins.first['replies'] as List).single['body'], 'on it');
    });

    test('selection handoff: register → organized read → expire-safe ids',
        () async {
      final api = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final reg = await api.handle('POST', '/selection', {}, {
        'key': 'ui-widgets-x-e11',
        'label': 'hero · text',
        'kind': 'h1',
        'group': 'text',
        'route': '/projects',
        'text': 'DOMKA TO STUDIO',
        'styles': {'font-size': '12rem'},
        'png': 'data:image/png;base64,iVBORw0KGgo=',
      }, null);
      expect(reg.status, 201);
      final id = (reg.json as Map)['id'] as String;
      expect(id, startsWith('s'));

      final read = await api.handle('GET', '/selection/$id', {}, null, null);
      expect(read.status, 200);
      final j = (read.json as Map).cast<String, dynamic>();
      expect(j['key'], 'ui-widgets-x-e11');
      expect(j['law'], contains('LOCKED'));
      expect(j['fetch'], '/__dial/selection/$id');
      expect((j['styles'] as Map)['font-size'], '12rem');
      expect(j['png'], startsWith('data:image/png'));

      // Guest cannot register; a bogus id shape 400s.
      final guest = await api.handle('POST', '/selection', {}, {'key': 'k', 'label': 'l'},
          ShareLinkGrant(artifact: 'demo', expiresAt: '2099-01-01T00:00:00Z'));
      expect(guest.status, 403);
      final bad = await api.handle('GET', '/selection/../../etc', {}, null, null);
      expect(bad.status, 400);

      // Oversize png refuses.
      final big = await api.handle('POST', '/selection', {}, {
        'key': 'k', 'label': 'l', 'png': 'data:image/png;base64,${'x' * 500000}',
      }, null);
      expect(big.status, 400);
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
              const {'ARXA_SUPABASE_URL': 'https://x.supabase.co'}),
          isNull);
      final s = SupabaseDialStore.fromEnv(const {
        'ARXA_SUPABASE_URL': 'https://x.supabase.co',
        'ARXA_SUPABASE_SERVICE_KEY': 'k',
      });
      expect(s, isNotNull);
      expect(s!.kind, 'supabase');
    });
  });

  group('the ~/.arxa/supabase credentials file', () {
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
          'ARXA_SUPABASE_URL': 'https://env.supabase.co',
          'ARXA_SUPABASE_SERVICE_KEY': 'envkey',
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

  group('live overlay routes (edit redesign, grilled 2026-09-11)', () {
    // The fake mirrors save_overlay's SQL semantics: author-only writes
    // (enforced by DialApi), rev stale-guard, empty patches = revert.
    late _OverlayFakeStore store;
    late DialApi api;
    setUp(() {
      store = _OverlayFakeStore();
      api = DialApi(store: store, artifact: 'demo', artifactDir: '/tmp/w/demo');
    });

    test('author PUT → GET roundtrip; guests read but never write',
        () async {
      final put = await api.handle('PUT', '/overlay', {}, {
        'baseRev': 0,
        'patches': {
          'e1': {
            'text': 'Hi',
            'was': 'Old',
            'attrs': {'src': 'https://x.co/i.jpg'},
          }
        },
      }, null);
      expect(put.status, 200, reason: jsonEncode(put.json));
      expect((put.json as Map)['ok'], true);
      expect((put.json as Map)['rev'], 1);

      final get = await api.handle('GET', '/overlay', {}, null, null);
      final overlay = (get.json as Map)['overlay'] as Map;
      expect(overlay['rev'], 1);
      expect(((overlay['patches'] as Map)['e1'] as Map)['text'], 'Hi');

      // A guest READS the overlay (decision 2: clients see live edits)…
      final token = await store.mintShareLink('demo', const Duration(days: 1));
      final grant = await store.resolveShareLink(token);
      final guestGet =
          await api.handle('GET', '/overlay', {'dial': token}, null, grant);
      expect(guestGet.status, 200);
      // …and can never write it.
      final guestPut = await api.handle('PUT', '/overlay', {'dial': token},
          {'baseRev': 1, 'patches': {}}, grant);
      expect(guestPut.status, 403, reason: 'clients never edit text/media');
    });

    test('a stale baseRev is refused with the fresh doc attached', () async {
      await api.handle('PUT', '/overlay', {},
          {'baseRev': 0, 'patches': {'e1': {'text': 'one'}}}, null);
      // Simulate another surface writing ahead of us.
      store.rev = 5;
      store.patches = {'e9': {'text': 'newer'}};
      final stale = await api.handle('PUT', '/overlay', {},
          {'baseRev': 1, 'patches': {'e1': {'text': 'two'}}}, null);
      expect(stale.status, 200);
      final j = stale.json as Map;
      expect(j['ok'], false);
      expect(j['error'], 'stale');
      expect(j['rev'], 5);
      expect((j['patches'] as Map)['e9'], isNotNull,
          reason: 'the caller resyncs from the fresh doc in one round trip');
    });

    test('empty patches revert: the row dies and rev resets', () async {
      await api.handle('PUT', '/overlay', {},
          {'baseRev': 0, 'patches': {'e1': {'text': 'Hi'}}}, null);
      final revert = await api.handle(
          'PUT', '/overlay', {}, {'baseRev': 1, 'patches': {}}, null);
      expect((revert.json as Map)['ok'], true);
      expect((revert.json as Map)['rev'], 0);
      final after = await api.handle('GET', '/overlay', {}, null, null);
      expect((after.json as Map)['overlay'], isNull);
    });

    test('a malformed body is a 400, never a 500', () async {
      final r = await api.handle('PUT', '/overlay', {}, {'patches': 'x'}, null);
      expect(r.status, 400);
    });

    test('the memory store answers null (no Edit verb law)', () async {
      final mem = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final r = await mem.handle('GET', '/overlay', {}, null, null);
      expect(r.status, 200);
      expect((r.json as Map)['overlay'], isNull);
    });

    test('dead links are refused everywhere (regression)', () async {
      final dead =
          await api.handle('GET', '/overlay', {'dial': 'deadbeef'}, null, null);
      expect(dead.status, 403);
      final deadPins =
          await api.handle('GET', '/pins', {'dial': 'deadbeef'}, null, null);
      expect(deadPins.status, 403);
    });
  });

  group('the identity plane (arc 2)', () {
    test('mint → attribute → roster → revoke: the personal-link lifecycle',
        () async {
      final store = MemoryDialStore();
      final api = DialApi(store: store, artifact: 'demo');

      final minted = await api.handle('POST', '/guests', {},
          {'email': 'jane@client.com', 'name': 'Jane'}, null);
      expect(minted.status, 201, reason: jsonEncode(minted.json));
      final grant = await store.resolveShareLink(
          (minted.json as Map)['token'] as String);
      expect(grant!.guestEmail, 'jane@client.com');

      final roster = await api.handle('GET', '/guests', {}, null, null);
      final gs = (roster.json as Map)['guests'] as List;
      expect(gs.single['email'], 'jane@client.com');
    });

    test('re-minting converges on one guest, links stack', () async {
    final store = MemoryDialStore();
    final api = DialApi(store: store, artifact: 'demo');
    await api.handle('POST', '/guests', {}, {'email': 'a@b.co'}, null);
    await api.handle(
        'POST', '/guests', {}, {'email': 'A@B.CO', 'name': 'A'}, null);
    final roster = await api.handle('GET', '/guests', {}, null, null);
    final gs = (roster.json as Map)['guests'] as List;
    expect(gs.length, 1, reason: 'upsert on (design, email), never a fork');
    expect(gs.single['linksAlive'], 2);
    expect(gs.single['name'], 'A');
  });
});

group('eject automint config (grilled 2026-09-10)', () {
  test('no dial block and no env = automint off', () {
    final c = dialAutomintConfig(null, const {});
    expect(c.enabled, isFalse);
  });

  test('the arxa.json dial block carries email + days (90 default)', () {
    final c = dialAutomintConfig(const {
      'automint': true,
      'clientEmail': 'client@co.com',
    }, const {});
    expect(c.enabled, isTrue);
    expect(c.email, 'client@co.com');
    expect(c.days, 90);
  });

  test('env ARXA_DIAL_AUTOMINT forces on and off over the block', () {
    expect(
        dialAutomintConfig(null, const {'ARXA_DIAL_AUTOMINT': '1'}).enabled,
        isTrue);
    expect(
        dialAutomintConfig(null, const {'ARXA_DIAL_AUTOMINT': 'true'}).enabled,
        isTrue);
    expect(
        dialAutomintConfig(const {'automint': true},
                const {'ARXA_DIAL_AUTOMINT': '0'})
            .enabled,
        isFalse);
    expect(
        dialAutomintConfig(const {'automint': true},
                const {'ARXA_DIAL_AUTOMINT': 'false'})
            .enabled,
        isFalse);
  });

  test('env email wins over the block email; days clamp + override', () {
    final c = dialAutomintConfig(const {
      'automint': true,
      'clientEmail': 'json@co.com',
      'days': 30,
    }, const {
      'ARXA_DIAL_CLIENT_EMAIL': 'env@co.com',
      'ARXA_DIAL_CLIENT_DAYS': '120',
    });
    expect(c.email, 'env@co.com');
    expect(c.days, 120);
    final clamped = dialAutomintConfig(const {
      'automint': true,
      'clientEmail': 'a@b.co',
      'days': 9999,
    }, const {});
    expect(clamped.days, 90);
    final envOnly = dialAutomintConfig(
        const {'automint': true, 'clientEmail': 'a@b.co'},
        const {'ARXA_DIAL_CLIENT_DAYS': '7'});
    expect(envOnly.days, 7);
  });

  test('enabled with a missing or malformed email reports email null', () {
    expect(dialAutomintConfig(const {'automint': true}, const {}).email,
        isNull);
    expect(
        dialAutomintConfig(
            const {'automint': true, 'clientEmail': 'not-an-email'},
            const {})
            .email,
        isNull);
  });
});

}
/// The overlay fake: mirrors save_overlay's SQL semantics for DialApi
/// route tests (author-only writes are DialApi's job; rev stale-guard and
/// empty-patches-revert are the store's).
class _OverlayFakeStore extends MemoryDialStore {
  Map<String, dynamic> patches = {};
  int rev = 0;

  @override
  Future<OverlayDoc?> readOverlay() async =>
      patches.isEmpty ? null : OverlayDoc(patches: patches, rev: rev);

  @override
  Future<OverlayWriteResult> writeOverlay(
      Map<String, dynamic> p, int baseRev) async {
    if (p.isEmpty) {
      patches = {};
      rev = 0;
      return const OverlayWriteResult(ok: true, rev: 0);
    }
    if (baseRev < rev) {
      return OverlayWriteResult(
          ok: false, error: 'stale', rev: rev, patches: patches);
    }
    patches = p;
    rev += 1;
    return OverlayWriteResult(ok: true, rev: rev);
  }
}
