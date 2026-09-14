// Local AUTHOR comment E2E (operator, 2026-09-10): the design-server half
// of the comments smoke — the loopback author drops a pin through the real
// composer (author_kind 'author'), replies through the thread popover, and
// flips the kanban status (the author- AND local-only triage surface,
// #statusrow). A second tab open on the same design proves the SSE repaint
// law: the new pin appears there with NO reload. Cleans up its own rows via
// the service key in finally. Usage:
//   dart run tool/lens_comment_local.dart <base-url>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/arxa_dial.dart' show parseSupabaseCredentials;

Future<void> main(List<String> argv) async {
  if (argv.length < 1) {
    stderr.writeln('usage: dart run tool/lens_comment_local.dart <base-url>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  const marker = 'lens local author comment probe';
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

  final home = Platform.environment['HOME'] ?? '.';
  final creds = parseSupabaseCredentials(
      File(home + '/.arxa/supabase').readAsStringSync());
  final sbUrl = creds.url;
  final serviceKey = creds.key;
  const designId = '6c21ecb2-74d5-4dc8-9065-bf036fccac5e'; // arxa-site
  String? pinId;

  Future<List<dynamic>> rowsByBody() async {
    try {
      final text = await get(
          sbUrl! + '/rest/v1/arxa_dial_pins?design_id=eq.' + designId +
              '&select=*,arxa_dial_replies(*)&body=eq.' + Uri.encodeComponent(marker),
          {'apikey': serviceKey!, 'Authorization': 'Bearer ' + serviceKey!});
      return jsonDecode(text) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }
  Future<bool> untilRows(int want, Duration cap) async {
    final deadline = DateTime.now().add(cap);
    while (DateTime.now().isBefore(deadline)) {
      if ((await rowsByBody()).length == want) return true;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return (await rowsByBody()).length == want;
  }

  final client = await CdpClient.launch();
  try {
    // THE HIDDEN-TAB LAW (2026-08-25): a background tab holds no realtime
    // by design — it closes SSE on hide and resyncs on show. So the
    // WATCHER must be the FOREGROUND tab and the DROPPER the hidden one:
    // CDP makes the newest tab active, so the dropper is created FIRST
    // (goes hidden, still drivable — evaluate and input events work),
    // the watcher SECOND (stays visible, SSE open, receives the frame).
    final tab = await client.newTab(); // dropper — becomes hidden
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(base, settleMs: 3500);
    await tab.waitForFunction(
        "!!document.querySelector('#arxa-dial-host').shadowRoot.querySelector('#dockbtn')",
        timeout: const Duration(seconds: 15));

    final tabB = await client.newTab(); // watcher — foreground, SSE live
    await tabB.enable();
    await tabB.setViewport(1280, 832);
    await tabB.navigateAndSettle(base, settleMs: 3500);
    await tabB.waitForFunction(
        "!!document.querySelector('#arxa-dial-host').shadowRoot.querySelector('#dockbtn')",
        timeout: const Duration(seconds: 15));
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";
    final visOk = await tabB.evaluate('document.visibilityState') as String?;
    check(visOk == 'visible', 'the watcher tab is the visible one (SSE open)');
    final pinsBefore = await tabB.evaluate(sr + ".querySelectorAll('.pin').length")
        as int? ?? 0;
    Future<dynamic> ev(String js) => tab.evaluate(js);
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button.verb')].filter(b => /Comment/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tab.click(520, 380);
    final composerOpen = await tab.waitForFunction(
        "(() => { const r = " + sr + "; const c = r.querySelector('#composer');"
        " return c && c.classList.contains('open') && !!c.querySelector('textarea'); })()",
        timeout: const Duration(seconds: 8));
    check(composerOpen, 'author click drops into the composer');
    await ev("(() => { const r = " + sr + "; const a = r.querySelector('#composer textarea'); "
        "a.value = '" + marker + "'; a.dispatchEvent(new Event('input', { bubbles: true })); "
        "const add = [...r.querySelectorAll('#composer button')].filter(b => /add pin/i.test(b.textContent)); "
        "add[0].click(); return 1; })()");

    final landed = await untilRows(1, const Duration(seconds: 12));
    check(landed, 'the author pin row lands in arxa_dial_pins');
    final rows = await rowsByBody();
    if (rows.isNotEmpty) {
      final row = rows.first as Map<String, dynamic>;
      pinId = row['id'] as String?;
      check(row['author_kind'] == 'author',
          'attributed author_kind author (got ' + row['author_kind'].toString() + ')');
      check(row['status'] == 'open', 'born open on the kanban');
    }

    // SSE repaint law: tab B sees the pin with NO reload
    final repaint = await tabB.waitForFunction(
        sr + ".querySelectorAll('.pin').length > " + pinsBefore.toString(),
        timeout: const Duration(seconds: 10));
    check(repaint, 'a second open dial repaints the new pin via SSE (no reload)');

    // reply through the thread popover
    await ev("(() => { const r = " + sr + "; const p = [...r.querySelectorAll('.pin')]"
        ".find(x => (x.title || '').includes('lens local author')); "
        "if (p) p.click(); return 1; })()");
    final threadOpen = await tab.waitForFunction(
        "(() => { const r = " + sr + "; const t = r.querySelector('#thread');"
        " return t && t.classList.contains('open') && !!t.querySelector('input'); })()",
        timeout: const Duration(seconds: 8));
    check(threadOpen, 'the marker opens the thread popover');
    final statusrow = await ev("!!" + sr + ".querySelector('#thread #statusrow')");
    check(statusrow == true, 'the kanban status row renders (author + local only)');
    await ev("(() => { const r = " + sr + "; const i = r.querySelector('#thread input'); "
        "i.value = 'local author reply'; i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); "
        "return 1; })()");
    var replied = false;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final rs = await rowsByBody();
      if (rs.isNotEmpty &&
          ((rs.first as Map)['arxa_dial_replies'] as List?)?.isNotEmpty == true) {
        replied = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    check(replied, 'the reply lands in arxa_dial_replies');

    // kanban triage: open -> resolved through the real status buttons
    await ev("(() => { const r = " + sr + "; const b = [...r.querySelectorAll('#statusrow .stbtn')]"
        ".find(x => /resolved/i.test(x.textContent)); if (b) b.click(); return 1; })()");
    var resolved = false;
    final dl2 = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(dl2)) {
      final rs = await rowsByBody();
      if (rs.isNotEmpty && (rs.first as Map)['status'] == 'resolved') {
        resolved = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    check(resolved, 'kanban triage flips the row to resolved');

    final errs = [...tab.consoleErrors, ...tab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the author flows');
    for (final e in errs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    try {
      if (pinId != null && serviceKey != null) {
        await http
            .deleteUrl(Uri.parse(sbUrl! + '/rest/v1/arxa_dial_replies?pin_id=eq.' + pinId!))
            .then((req) {
          req.headers.set('apikey', serviceKey!);
          req.headers.set('Authorization', 'Bearer ' + serviceKey!);
          return req.close();
        });
        await http
            .deleteUrl(Uri.parse(sbUrl! + '/rest/v1/arxa_dial_pins?id=eq.' + pinId!))
            .then((req) {
          req.headers.set('apikey', serviceKey!);
          req.headers.set('Authorization', 'Bearer ' + serviceKey!);
          return req.close();
        });
      }
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens comment-local: ALL PASS'
      : 'lens comment-local: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
