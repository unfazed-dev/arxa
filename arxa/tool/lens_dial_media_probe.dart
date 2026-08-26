// Media probe (slice 4): the /media routes against the LIVE server with
// REAL provider keys, plus the card's Media section rendering for a real
// image element. Cleans up its own artifact writes.
import 'dart:convert';
import 'dart:io';
import 'package:arxa/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const sr = "document.getElementById('arxa-dial-host').shadowRoot";
int fails = 0;
void check(bool ok, String label) {
  stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
  if (!ok) fails++;
}
Future<void> main() async {
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettleForCapture('http://127.0.0.1:4319/', settleMs: 2500);

  // 1. search: both providers, normalized shape
  final search = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/media/search', {method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({q: 'minimal studio interior', kind: 'photo'})});
      const j = await r.json();
      return {status: r.status, n: (j.results || []).length,
              providers: [...new Set((j.results || []).map(x => x.provider))],
              first: j.results ? j.results[0] : null};
    })()
  ''');
  final s = (search as Map).cast<String, dynamic>();
  check(s['status'] == 200, 'search 200');
  check((s['n'] as num) >= 10, 'search returned ${s['n']} results');
  final providers = (s['providers'] as List).toSet();
  check(providers.contains('unsplash') && providers.contains('pexels'),
      'both providers merged ($providers)');

  // 2. copy: writes into the artifact + credits
  final first = (s['first'] as Map).cast<String, dynamic>();
  final copy = await js(tab, '''    (async () => {
      const r = await fetch('/__dial/media/copy', {method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({url: ${jsonDart(first['full'])},
          name: 'lens-probe-' + Date.now(), credit: ${jsonDart(first['credit'])},
          provider: ${jsonDart(first['provider'])}})});
      return await r.json();
    })()
  ''');
  final c = (copy as Map).cast<String, dynamic>();
  check(c['path'] != null && (c['path'] as String).startsWith('assets/images/'),
      'copy returned artifact path (${c['path']})');
  final abs = '/Volumes/developer_ssd/Developer/totem_labs/clients/architect-gallore/design/suczka-studio/${c['path'] as String? ?? 'x'}';
  check(File(abs).existsSync(), 'file exists on disk');

  // 3. assets lists it
  final assets = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/media/assets');
      return await r.json();
    })()
  ''');
  final a = (assets as Map).cast<String, dynamic>();
  check((a['assets'] as List? ?? []).contains(c['path']), 'assets lists the copy');

  // 4. SSRF guard: a non-CDN url refuses
  final guard = await js(tab, '''
    (async () => {
      const r = await fetch('/__dial/media/copy', {method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({url: 'http://169.254.169.254/latest/meta-data', name: 'x', credit: 'c', provider: 'p'})});
      return r.status;
    })()
  ''');
  check(guard == 400, 'SSRF-shaped url refused 400 (got $guard)');

  // 5. guest fence
  final guest = await js(tab, '''
    (async () => {
      const m = await (await fetch('/__dial/share', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'})).json();
      const r = await fetch('/__dial/media/search?dial=' + m.token, {method: 'POST',
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({q: 'x'})});
      return r.status;
    })()
  ''');
  check(guest == 403, 'guest media search 403 (got $guest)');

  // 6. card Media section on a real image
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, '$sr.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$sr.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  // The home canvas is scroll-driven; walk down until a usable img shows.
  Map? imgPt;
  for (var scroll = 0; scroll <= 5 && imgPt == null; scroll++) {
    imgPt = (await js(tab, '''
      (() => {
        const imgs = [...document.querySelectorAll('img[data-arxa-id]')];
        for (const im of imgs) {
          const r = im.getBoundingClientRect();
          if (r.width > 60 && r.height > 60 && r.x >= 0 && r.y >= 40 &&
              r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
            return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + Math.min(r.height / 2, 60))};
          }
        }
        return null;
      })()
    ''')) as Map?;
    if (imgPt == null) {
      await js(tab, 'scrollBy(0, 500)');
      await Future.delayed(const Duration(milliseconds: 900));
    }
  }
  if (imgPt is Map) {
    final x = (imgPt['x'] as num).toInt(), y = (imgPt['y'] as num).toInt();
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
    await tab.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
    await Future.delayed(const Duration(milliseconds: 500));
    final mediaSect = await js(tab, '''
      (() => {
        const sects = [...$sr.querySelectorAll('#card .sect')].map(s => s.textContent);
        return {media: sects.includes('Media'), find: !!$sr.querySelector('#card .facet .btn')};
      })()
    ''');
    final ms = (mediaSect as Map).cast<String, dynamic>();
    check(ms['media'] == true, 'card shows Media section for image');
    // search from the card against live providers
    await js(tab, '''
      (() => {
        const btns = [...$sr.querySelectorAll('#card .facet .btn')];
        const find = btns.find(b => b.textContent === 'Find');
        if (!find) return false;
        const facet = find.closest('.facet');
        const inp = facet && facet.querySelector('input[type=text]');
        if (inp) { inp.value = 'chair'; find.click(); return true; }
        return false;
      })()
    ''');
    await Future.delayed(const Duration(milliseconds: 2500));
    final thumbs = await js(tab, '$sr.querySelectorAll("#card img").length');
    check((thumbs as num) >= 5, 'card search renders provider thumbnails ($thumbs)');
  } else {
    check(false, 'artifact renders an img to select');
  }

  // 7. console + cleanup
  check(tab.consoleErrors.isEmpty, 'console clean (${tab.consoleErrors.length})');
  final f = File(abs);
  if (f.existsSync()) f.deleteSync();
  // Prune credit rows whose file no longer exists; drop the ledger when
  // empty. (The original condition was inverted and kept probe litter.)
  final credits = File('/Volumes/developer_ssd/Developer/totem_labs/clients/architect-gallore/design/suczka-studio/assets/credits.json');
  if (credits.existsSync()) {
    final j = jsonDecode(credits.readAsStringSync()) as Map;
    final media = (j['media'] as List? ?? []).where((e) => File('/Volumes/developer_ssd/Developer/totem_labs/clients/architect-gallore/design/suczka-studio/${(e as Map)['file'] as String}').existsSync()).toList();
    if (media.isEmpty) { credits.deleteSync(); }
    else { credits.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({...j, 'media': media})); }
  }
  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}

String jsonDart(Object? v) => '"${(v ?? '').toString().replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
