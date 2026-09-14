// Live deployed-dial GUEST E2E (operator, 2026-09-10 — the client-link
// story end to end): mints a personal guest link against the LOCAL design
// server (the mint route is design-time; the link itself is validated by
// the DEPLOYED site), boots the live dial as a guest, proves the publish
// law (a guest's palette pick publishes for everyone — verified on the
// shared axes row and by an anonymous clean-context visitor), restores the
// published pick, revokes the link, and proves the dead link boots the
// 'invalid' surface with zero writes. Never prints tokens. Usage:
//   dart run tool/lens_live_guest.dart <live-base-url> <design-server-url> <restore-id>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln(
        'usage: dart run tool/lens_live_guest.dart <live-base-url> <design-server-url> <restore-id>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final server = argv[1].replaceAll(RegExp(r'/$'), '');
  final restoreId = argv[2];
  const email = 'lens-guest@arxa.dev';
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
  Future<String> get(String url, [Map<String, String>? headers]) async {
    final req = await http.getUrl(Uri.parse(url));
    if (headers != null) headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 15));
    return utf8.decoder.bind(res).join();
  }

  final manifest =
      (jsonDecode(await get(base + '/palettes.json')) as Map).cast<String, dynamic>();
  final palettes = (manifest['palettes'] as List).cast<Map>();
  final restoreName =
      palettes.firstWhere((p) => p['id'] == restoreId)['name'] as String;
  final other = palettes.firstWhere((p) => p['id'] != restoreId && p['seeded'] == true);
  final otherName = other['name'] as String;
  final otherId = other['id'] as String;

  String? token;
  Map<String, dynamic>? remote;
  final client = await CdpClient.launch();
  Future<String?> publishedRow() async {
    if (remote == null) return null;
    try {
      final body = await get(remote!['url'] as String, {
        'apikey': remote!['anonKey'] as String,
        'Authorization': 'Bearer ' + (remote!['anonKey'] as String),
      });
      final rows = jsonDecode(body);
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        return (rows.first as Map)['palette'] as String?;
      }
    } catch (_) {}
    return null;
  }
  Future<bool> untilRow(String want, Duration cap) async {
    final deadline = DateTime.now().add(cap);
    while (DateTime.now().isBefore(deadline)) {
      if (await publishedRow() == want) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
  Future<void> rpcPublish(String linkToken, String paletteId) async {
    if (remote == null) return;
    final url = (remote!['url'] as String);
    final origin = url.substring(0, url.indexOf('/rest/v1/'));
    await post(origin + '/rest/v1/rpc/publish_palette', {
      'link_token': linkToken,
      'palette_id': paletteId,
    });
  }

  try {
    // 1. mint a personal guest link on the LOCAL design server (design-time)
    final mint = await post(server + '/__dial/guests',
        {'email': email, 'name': 'Lens Smoke', 'days': 1});
    check(mint.$1 == 201 && mint.$2['token'] is String,
        'guest link mints on the design server (got ' + mint.$1.toString() + ')');
    token = mint.$2['token'] as String?;
    if (token == null) throw StateError('no token — aborting');

    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    Future<dynamic> ev(String js) => tab.evaluate(js);

    // 2. the guest link boots the DEPLOYED dial in guest mode
    await tab.navigateAndSettle(base + '/?dial=' + token!, settleMs: 5000);
    final mode = await ev(
        "(() => { const c = document.getElementById('arxa-dial-config');"
        " return c ? JSON.parse(c.textContent).mode : 'NONE'; })()");
    check(mode == 'guest', 'deployed dial boots in guest mode (got ' + mode.toString() + ')');
    final remoteJson = await ev("JSON.stringify(window.__ARXA_PALETTE__.remote)");
    remote = (jsonDecode(remoteJson as String) as Map).cast<String, dynamic>();
    // the guest boot is async (resolve_guest_link → pins → mount): poll for it
    const sr = "document.querySelector('#arxa-dial-host') && document.querySelector('#arxa-dial-host').shadowRoot";
    final docked = await tab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25));
    check(docked, 'guest identity resolves — the dock boots');

    // 3. the publish law: a GUEST pick publishes for everyone
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final count = await ev(sr + ".querySelectorAll('.palcard').length");
    check(count == palettes.length,
        'guest theme tray lists all ' + palettes.length.toString() + ' palettes');
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('" + otherName + "')); "
        "c.click(); return 1; })()");
    final rowFlip = await untilRow(otherId, const Duration(seconds: 15));
    check(rowFlip, 'guest pick published the shared row: ' + otherId);

    // 4. an anonymous visitor (clean context) settles onto the guest's pick
    final anonCtx = await client.createBrowserContext();
    final anon = await client.newTab(browserContextId: anonCtx);
    await anon.enable();
    await anon.navigateAndSettle(base, settleMs: 5000);
    final anonOk = await anon.waitForFunction(
        "document.documentElement.getAttribute('data-palette') === '" + otherId + "'",
        timeout: const Duration(seconds: 15));
    check(anonOk, 'anonymous visitor settles onto the guest pick ' + otherId);
    await client.disposeBrowserContext(anonCtx);

    // 5. restore through the same guest link
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('" + restoreName + "')); "
        "c.click(); return 1; })()");
    final rowBack = await untilRow(restoreId, const Duration(seconds: 15));
    check(rowBack, 'restored the shared row to ' + restoreId);

    // 6. revoke — the dead link boots the invalid surface, zero writes
    final revoke =
        await post(server + '/__dial/guests/revoke', {'email': email});
    check(revoke.$1 == 200, 'guest link revoked (got ' + revoke.$1.toString() + ')');
    await tab.navigateAndSettle(base + '/?dial=' + token!, settleMs: 6000);
    // #dockbtn is built eagerly at script load in EVERY mode — the invalid
    // surface's tell is the expiry toast, not the dock's absence.
    final dead = await tab.waitForFunction(
        "(() => { const r = " + sr + "; "
        "return r && r.textContent.includes('expired or invalid'); })()",
        timeout: const Duration(seconds: 25));
    check(dead, 'revoked link boots the invalid surface (expiry toast, dock never finishes boot)');
    final rowAfter = await publishedRow();
    check(rowAfter == restoreId,
        'the dead link made ZERO writes (row still ' + restoreId.toString() + ')');

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the guest flows');
    for (final e in errs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    // leave everything exactly as found: restore the pick, burn the demo link
    try {
      if (token != null && remote != null) {
        if (await publishedRow() != restoreId) await rpcPublish(token!, restoreId);
      }
    } catch (_) {}
    try {
      await post(server + '/__dial/guests/revoke', {'email': email});
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens live-guest: ALL PASS'
      : 'lens live-guest: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
