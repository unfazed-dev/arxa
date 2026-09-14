// Live PUBLIC palette-ear E2E (operator, 2026-09-11 — the researched
// close of the "open public tab never hears palette changes" gap): boots
// the DEPLOYED site with NO dial credential, proves a bare tab hears a
// published palette change live WITHOUT any reload, proves the
// visibility law (hidden tab holds no connection; show resyncs), proves
// the receipt law (an explicit ?palette= is never stomped), and leaves
// the shared row exactly as found. Usage:
//   dart run tool/lens_palette_public.dart <live-base-url> <design-server-url> <keep-id>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln(
        'usage: dart run tool/lens_palette_public.dart <live-base-url> <design-server-url> <keep-id>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final server = argv[1].replaceAll(RegExp(r'/$'), '');
  final keepId = argv[2];
  var failures = 0;
  void check(bool ok, String label) {
    stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
  }

  final http = HttpClient();
  Future<(int, Map<String, dynamic>)> post(String url, Map<String, dynamic> body) async {
    final req = await http.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decoder.bind(res).join();
    Map<String, dynamic> json = {};
    try {
      json = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {}
    return (res.statusCode, json);
  }
  Future<String> get(String url) async {
    final req = await http.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 15));
    return utf8.decoder.bind(res).join();
  }

  // The manifest tells us which ids this build can dress (the ear refuses
  // ids ahead of the deploy — pick flip/third from the SEEDED set).
  final manifest =
      (jsonDecode(await get(base + '/palettes.json')) as Map).cast<String, dynamic>();
  final seeded = (manifest['palettes'] as List)
      .cast<Map>()
      .where((p) => p['seeded'] == true && p['id'] != keepId)
      .map((p) => p['id'] as String)
      .toList();
  if (seeded.length < 2) {
    stderr.writeln('need two seeded ids besides keep — got ' + seeded.toString());
    exit(2);
  }
  final flipId = seeded[0];
  final thirdId = seeded[1];

  Future<void> publish(String id) async {
    final r = await post(server + '/__dial/axes', {'palette': id});
    if (r.$1 != 200) throw StateError('publish failed: ' + r.$1.toString());
  }

  final client = await CdpClient.launch();
  try {
    // 0. start from the keeper
    await publish(keepId);

    // 1. the public tab: no dial credential, settles onto the row
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    Future<dynamic> ev(String js) => tab.evaluate(js);
    Future<bool> attrIs(String id, Duration cap) => tab.waitForFunction(
        "document.documentElement.getAttribute('data-palette') === '" + id + "'",
        timeout: cap);
    await tab.navigateAndSettle(base, settleMs: 5000);
    final settled = await attrIs(keepId, const Duration(seconds: 10));
    check(settled, 'public tab boots + settles onto published ' + keepId);
    // the no-reload witness: set AFTER settle; a reload would erase it
    await ev('window.__lensMark = 42; 1');

    // 2. THE GAP IS CLOSED: publish, the bare tab flips live, no reload
    await publish(flipId);
    final flipped = await attrIs(flipId, const Duration(seconds: 10));
    check(flipped, 'published ' + flipId + ' repaints the open public tab LIVE');
    final mark = await ev('typeof window.__lensMark === "number"');
    check(mark == true, 'no reload happened (the witness survived)');

    // 3. the visibility law: hidden tab holds no connection
    final cover = await client.newTab();
    await cover.enable();
    await cover.bringToFront(); // tab goes hidden -> the ear tears down
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await publish(keepId);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final stale = await ev(
        "document.documentElement.getAttribute('data-palette') !== '" + keepId + "'");
    check(stale == true,
        'hidden tab heard NOTHING (channel was down, still on ' + flipId + ')');
    await tab.bringToFront(); // visible again -> resync read recovers truth
    final resynced = await attrIs(keepId, const Duration(seconds: 10));
    check(resynced, 'show resync recovers the truth (' + keepId + ')');

    // 4. the receipt law: an explicit ?palette= is never stomped
    await tab.navigateAndSettle(base + '/?palette=' + flipId, settleMs: 5000);
    final receiptHeld = await attrIs(flipId, const Duration(seconds: 8));
    check(receiptHeld, 'the ?palette= receipt pre-paints ' + flipId);
    await publish(thirdId); // a live frame arrives with a DIFFERENT id
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final receiptKept = await attrIs(flipId, const Duration(seconds: 2));
    check(receiptKept, 'the live frame did NOT stomp the receipt (still ' + flipId + ')');

    // 5. leave the world as found
    await publish(keepId);
    await tab.navigateAndSettle(base, settleMs: 5000);
    final back = await attrIs(keepId, const Duration(seconds: 10));
    check(back, 'store restored: published is ' + keepId + ' again');

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the public-ear flows');
    for (final e in errs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    try {
      await publish(keepId);
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens palette-public: ALL PASS'
      : 'lens palette-public: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
