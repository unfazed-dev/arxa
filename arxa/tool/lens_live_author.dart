// Live deployed-dial author E2E (operator, 2026-09-10 — the client-token
// story proven against the PUBLISHED site): a wrong ?dial-author token gets
// no dial at all (exactly like no token); the right one boots the dial in
// author mode; a palette card click publishes through the publish_palette
// RPC — proven by reading the shared axes row through the injected public
// remote channel — and an ANONYMOUS visitor in a clean browser context
// settles onto the new pick. Restores the published pick passed in and
// verifies the restore settles too. Never prints the token. Usage:
//   dart run tool/lens_live_author.dart <base-url> <author-token> <restore-id>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln(
        'usage: dart run tool/lens_live_author.dart <base-url> <author-token> <restore-id>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final token = argv[1];
  final restoreId = argv[2];
  var failures = 0;
  void check(bool ok, String label) {
    stdout.writeln((ok ? 'PASS ' : 'FAIL ') + label);
    if (!ok) failures++;
  }

  final http = HttpClient();
  Future<String> get(String url, [Map<String, String>? headers]) async {
    final req = await http.getUrl(Uri.parse(url));
    if (headers != null) headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 15));
    return utf8.decoder.bind(res).join();
  }

  // the manifest is public — cards are found by their declared names
  final manifest =
      (jsonDecode(await get(base + '/palettes.json')) as Map).cast<String, dynamic>();
  final palettes = (manifest['palettes'] as List).cast<Map>();
  final restoreName =
      palettes.firstWhere((p) => p['id'] == restoreId)['name'] as String;
  final other = palettes.firstWhere((p) => p['id'] != restoreId && p['seeded'] == true);
  final otherName = other['name'] as String;
  final otherId = other['id'] as String;

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    Future<dynamic> ev(String js) => tab.evaluate(js);
    const modeJs =
        "(() => { const c = document.getElementById('arxa-dial-config');"
        " return c ? JSON.parse(c.textContent).mode : 'NONE'; })()";

    // 1. a wrong author token is EXACTLY no token — no dial config at all
    await tab.navigateAndSettle(base + '/?dial-author=definitely-wrong', settleMs: 4000);
    var mode = await ev(modeJs);
    check(mode == 'NONE',
        'wrong author token: no dial injected (got mode ' + mode.toString() + ')');

    // 2. the right token boots the dial in author mode
    await tab.navigateAndSettle(base + '/?dial-author=' + token, settleMs: 5000);
    mode = await ev(modeJs);
    check(mode == 'author',
        'right author token: dial boots in author mode (got ' + mode.toString() + ')');
    final bootPick = await ev("document.documentElement.getAttribute('data-palette')");
    stdout.writeln('published at boot: ' + bootPick.toString());
    check(bootPick == restoreId, 'site boots on the user pick ' + restoreId);

    // the public remote channel (the same one palette.js settles on)
    final remoteJson = await ev("JSON.stringify(window.__ARXA_PALETTE__.remote)");
    final remote = (jsonDecode(remoteJson as String) as Map).cast<String, dynamic>();
    check(remote['url'] != null, 'public remote channel injected for the live settle');
    Future<String?> publishedRow() async {
      try {
        final body = await get(remote['url'] as String, {
          'apikey': remote['anonKey'] as String,
          'Authorization': 'Bearer ' + (remote['anonKey'] as String),
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

    // 3. the theme tray lists every declared palette
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final count = await ev(sr + ".querySelectorAll('.palcard').length");
    check(
        count == palettes.length,
        'theme tray lists all ' +
            palettes.length.toString() +
            ' palettes (got ' +
            count.toString() +
            ')');

    // trim v2: the DEPLOYED author gets ONE slide — Access is local-only
    final tray = await ev("(() => { const r = " + sr + "; return { "
        "slides: [...r.querySelectorAll('.slide')].map(s => s.getAttribute('data-slide')), "
        "panel: !!r.querySelector('.gstpanel') }; })()") as Map;
    final slideIds = (tray['slides'] as List).map((s) => s.toString()).toList();
    check(slideIds.length == 1 && slideIds.first == 'theme' && tray['panel'] != true,
        'static author tray: Theme only, no Access (got ' + slideIds.join(',') + ')');

    // 4. clicking a different card publishes through the RPC
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('" + otherName + "')); "
        "c.click(); return 1; })()");
    final localFlip = await tab.waitForFunction(
        "document.documentElement.getAttribute('data-palette') === '" + otherId + "'",
        timeout: const Duration(seconds: 8));
    check(localFlip, 'local repaint flips to ' + otherId);
    final rowFlip = await untilRow(otherId, const Duration(seconds: 15));
    check(rowFlip, 'publish_palette wrote the shared row: ' + otherId);

    // 5. an anonymous visitor (clean context — no token, no memory) settles on it
    final anonCtx = await client.createBrowserContext();
    final anon = await client.newTab(browserContextId: anonCtx);
    await anon.enable();
    await anon.setViewport(1280, 832);
    await anon.navigateAndSettle(base, settleMs: 5000);
    final anonOk = await anon.waitForFunction(
        "document.documentElement.getAttribute('data-palette') === '" + otherId + "'",
        timeout: const Duration(seconds: 15));
    check(anonOk, 'anonymous visitor settles onto the published pick ' + otherId);
    await client.disposeBrowserContext(anonCtx);

    // 6. restore the user pick — and prove the restore settles too
    await ev("(() => { const r = " + sr + "; const c = [...r.querySelectorAll('.palcard')]"
        ".find(x => x.querySelector('.palname').textContent.includes('" + restoreName + "')); "
        "c.click(); return 1; })()");
    final rowBack = await untilRow(restoreId, const Duration(seconds: 15));
    check(rowBack, 'restored the shared row to ' + restoreId);
    final anonCtx2 = await client.createBrowserContext();
    final anon2 = await client.newTab(browserContextId: anonCtx2);
    await anon2.enable();
    await anon2.navigateAndSettle(base, settleMs: 5000);
    final backOk = await anon2.waitForFunction(
        "document.documentElement.getAttribute('data-palette') === '" + restoreId + "'",
        timeout: const Duration(seconds: 15));
    check(backOk, 'anonymous visitor settles back on ' + restoreId);
    await client.disposeBrowserContext(anonCtx2);

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the live flows');
    for (final e in errs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens live-author: ALL PASS'
      : 'lens live-author: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
