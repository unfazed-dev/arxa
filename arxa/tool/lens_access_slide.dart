// Access-slide E2E (trim v2, grilled 2026-09-10): the LOCAL author's tray
// carries Theme + Access (the client-link panel — mint button, roster), a
// guest's tray is ONE slide with no pagination and no access surface
// anywhere in the shadow root. The deployed/static author arm is proven by
// lens_live_author against the live site. Usage:
//   dart run tool/lens_access_slide.dart <base-url> <design-server-url>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_access_slide.dart <base-url> <design-server-url>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final server = argv[1].replaceAll(RegExp(r'/$'), '');
  const email = 'access-probe@arxa.dev';
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

  String? token;
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    Future<dynamic> ev(String js) => tab.evaluate(js);
    const sr =
        "document.querySelector('#arxa-dial-host') && document.querySelector('#arxa-dial-host').shadowRoot";

    // ── author arm: two slides, Access carries the client panel ──────────
    await tab.navigateAndSettle(base, settleMs: 3500);
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    var state = await ev("(() => { const r = " + sr + "; return { "
        "slides: [...r.querySelectorAll('.slide')].map(s => s.getAttribute('data-slide')), "
        "dots: r.querySelectorAll('#dots .dotbtn').length, "
        "dotsShown: getComputedStyle(r.querySelector('#dots')).display !== 'none', "
        "title: r.querySelector('#ttitle').textContent }; })()") as Map;
    check(state['slides'] is List &&
        List.from(state['slides'] as List).join(',') == 'theme,access',
        'author tray: exactly Theme + Access (got ' + state['slides'].toString() + ')');
    check(state['dots'] == 2 && state['dotsShown'] == true,
        'author tray: two dot buttons shown');
    check(state['title'] == 'Theme', 'author tray boots on Theme');

    await ev("(() => { const r = " + sr + "; "
        "const d = r.querySelectorAll('#dots .dotbtn')[1]; d.click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 900));
    state = await ev("(() => { const r = " + sr + "; return { "
        "title: r.querySelector('#ttitle').textContent, "
        "panel: !!r.querySelector('.slide[data-slide=access] .gstpanel'), "
        "mint: [...r.querySelectorAll('.slide[data-slide=access] button')]"
        "  .some(b => /mint personal link/i.test(b.textContent)), "
        "roster: !!r.querySelector('.slide[data-slide=access] .gstlist'), "
        "placeholder: !!r.querySelector('.incoming') }; })()") as Map;
    check(state['title'] == 'Access', 'slide 2 titles Access (got ' + state['title'].toString() + ')');
    check(state['panel'] == true, 'the client-access panel renders on Access');
    check(state['mint'] == true, 'the Mint personal link button renders');
    check(state['roster'] == true, 'the guest roster renders');
    check(state['placeholder'] != true, 'the Incoming placeholder is gone');
    final aErrs = [...tab.consoleErrors, ...tab.pageErrors];
    check(aErrs.isEmpty, 'zero console/page errors on the author arm');
    for (final e in aErrs) {
      stdout.writeln('  err: ' + e);
    }

    // ── guest arm: ONE slide, no pagination, no access surface ───────────
    final mint = await post(server + '/__dial/guests',
        {'email': email, 'name': 'Access Probe', 'days': 1});
    check(mint.$1 == 201, 'probe guest mints (got ' + mint.$1.toString() + ')');
    token = mint.$2['token'] as String?;
    if (token == null) throw StateError('no token');
    await tab.navigateAndSettle(base + '/?dial=' + token!, settleMs: 4500);
    final docked = await tab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25));
    check(docked, 'guest dial boots');
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button')].filter(b => /Studio/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    state = await ev("(() => { const r = " + sr + "; return { "
        "slides: [...r.querySelectorAll('.slide')].map(s => s.getAttribute('data-slide')), "
        "dotsShown: getComputedStyle(r.querySelector('#dots')).display !== 'none', "
        "panel: !!r.querySelector('.gstpanel') }; })()") as Map;
    check(state['slides'] is List && (state['slides'] as List).length == 1 &&
        (state['slides'] as List).first == 'theme',
        'guest tray: Theme only (got ' + state['slides'].toString() + ')');
    check(state['dotsShown'] != true, 'guest tray: no pagination dots');
    check(state['panel'] != true, 'guest shadow root has NO access panel');
    final gErrs = [...tab.consoleErrors.where((e) => !aErrs.contains(e)),
      ...tab.pageErrors];
    check(gErrs.isEmpty, 'zero NEW console/page errors on the guest arm');
    for (final e in gErrs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    try {
      await post(server + '/__dial/guests/revoke', {'email': email});
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens access-slide: ALL PASS'
      : 'lens access-slide: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
