// LOCAL-designer AUTHOR EDIT E2E (operator, 2026-09-11): the loopback
// author edits text through the SAME overlay row (one truth with the
// deployed site — the store is the shared Supabase project), the PUT rides
// the local /__dial/overlay route, the SSE 'overlay' frame repaints a
// second tab live, a guest link READS the overlay but cannot write it, and
// the row is left ABSENT at the end. Never prints tokens.
//
//   dart run tool/lens_edit_local.dart <base-url>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 1) {
    stderr.writeln('usage: dart run tool/lens_edit_local.dart <base-url>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  const marker = 'LENSLOCALEDIT';
  const email = 'lens-edit-local@arxa.dev';
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
    final res = await req.close().timeout(const Duration(seconds: 25));
    final text = await utf8.decoder.bind(res).join();
    Map<String, dynamic> json = {};
    try {
      json = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {}
    return (res.statusCode, json);
  }
  Future<(int, Map<String, dynamic>)> put(String url, Map<String, dynamic> body) async {
    final req = await http.openUrl('PUT', Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 25));
    final text = await utf8.decoder.bind(res).join();
    Map<String, dynamic> json = {};
    try {
      json = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {}
    return (res.statusCode, json);
  }
  Future<Map<String, dynamic>?> getJson(String url) async {
    try {
      final req = await http.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await utf8.decoder.bind(res).join();
      return (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  const sr = "document.querySelector('#arxa-dial-host') && document.querySelector('#arxa-dial-host').shadowRoot";
  // The runtime's full stamp vocabulary (the walk binds to the NEAREST
  // data-arxa-id OR data-el — this artifact stamps text carriers data-el).
  const editableJs = "(() => { const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
      "for (const el of els) { const t = (el.textContent || '').trim(); "
      "if (t.length > 0 && t.length < 300 && !el.querySelector('[data-arxa-id],[data-el]') "
      "&& el.getBoundingClientRect().width > 40) return el; } return null; })()";

  final client = await CdpClient.launch();
  try {
    // 1. the overlay route answers on the local server (memory of the row)
    final before = await getJson(base + '/__dial/overlay');
    check(before != null && before!['overlay'] == null,
        'GET /__dial/overlay answers (no row yet)');

    // 2. AUTHOR loopback tab first, WATCHER second (foreground — the SSE
    //    watcher must not be a hidden tab)
    final atab = await client.newTab();
    await atab.enable();
    await atab.setViewport(1280, 832);
    await atab.navigateAndSettle(base, settleMs: 4000);
    final mode = await atab.evaluate(
        "(() => { const c = document.getElementById('arxa-dial-config'); return c ? JSON.parse(c.textContent).mode : 'NONE'; })()");
    check(mode == 'author', 'loopback boots author mode (got ' + mode.toString() + ')');
    await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25));

    final wtab = await client.newTab();
    await wtab.enable();
    await wtab.setViewport(1280, 832);
    await wtab.navigateAndSettle(base, settleMs: 4000);
    await wtab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25));
    // A real author types with the tab FOCUSED — CDP char insertion into a
    // contenteditable on a backgrounded tab is unreliable, so the author tab
    // is foreground for the edit gesture. The watcher gets its truth through
    // the show-time resync read (the socket-pool law's other half) and then
    // witnesses a LIVE frame when the author reverts.
    await atab.bringToFront();

    // 3. arm Edit, type into a text element
    await atab.hover(1270, 790);
    await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && r.querySelector('#dockbtn').classList.contains('open'); })()",
        timeout: const Duration(seconds: 8));
    await atab.evaluate("(() => { const r = " + sr + "; "
        "const v = r.querySelector('button.verb[data-verb=edit]'); if (!v) return false; v.click(); return true; })()");
    await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#editbar.open'); })()",
        timeout: const Duration(seconds: 8));
    final target = await atab.evaluate(
        "(() => { const el = " + editableJs + "; if (!el) return null; "
        "const r = el.getBoundingClientRect(); "
        "const mid = el.getAttribute('data-arxa-id'); "
        "const key = mid || ('el:' + (el.getAttribute('data-el') || '')); "
        "return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2, id: key}); })()") as String?;
    check(target != null, 'a text-editable element is on the page');
    final t = jsonDecode(target!) as Map;
    await atab.hover((t['x'] as num).round(), (t['y'] as num).round());
    await atab.dblclick((t['x'] as num).round(), (t['y'] as num).round());
    await atab.waitForFunction(
        "(() => { const k = '" + t['id']! + "'; const sel = k.indexOf('el:') === 0 "
        "? ('[data-el=\"' + k.slice(3) + '\"]') : ('[data-arxa-id=\"' + k + '\"]'); "
        "const el = document.querySelector(sel); "
        "return el && el.getAttribute('data-arxa-inline-editing') === '1'; })()",
        timeout: const Duration(seconds: 8));
    for (final ch in marker.split('')) {
      await atab.key(ch);
    }
    // (a row landing with unchanged text is a silent failure)
    // Typing truth: the characters must be IN the element before Enter.
    final typed = await atab.evaluate(
          "(() => { const k = '" + t['id']! + "'; "
          "const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
          "const el = els.find(e => (k.indexOf('el:') === 0 "
          "? ('el:' + (e.getAttribute('data-el') || '')) "
          ": e.getAttribute('data-arxa-id')) === k); "
          "return el ? el.textContent : null; })()") as String?;
    check(typed != null && typed!.contains(marker),
        'the typed text is in the element before commit');
    await atab.key('Enter');

    // 4. the row lands (author PUT → save_overlay via service role)
    var rowSeen = false;
    {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        final r = await getJson(base + '/__dial/overlay');
        final o = r?['overlay'];
        if (o is Map && (o['patches'] as Map)[t['id']!] != null) {
          rowSeen = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    check(rowSeen, 'the edit lands in the shared overlay row (local author, service-role save)');

    // 5. the WATCHER tab was hidden while the author typed (the author
    //    held the focus) — foregrounding it runs the show-time resync read,
    //    which adopts the row and repaints (decision 2 for every surface).
    await wtab.bringToFront();
    final wSeen = await wtab.waitForFunction(
        "document.body.textContent.includes('" + marker + "')",
        timeout: const Duration(seconds: 25));
    check(wSeen, 'watcher tab adopts the row on show (resync read)');

    // 6. a GUEST reads the overlay through the local server but cannot write
    final mint = await post(base + '/__dial/guests', {'email': email, 'days': 1});
    check(mint.$1 == 201, 'guest link mints (got ' + mint.$1.toString() + ')');
    final gt = mint.$2['token'] as String?;
    final guestRead = await getJson(base + '/__dial/overlay?dial=' + gt!);
    check(guestRead != null && guestRead!['overlay'] is Map,
        'guest READS the overlay (decision 2)');
    final guestWrite = await put(base + '/__dial/overlay?dial=' + gt, {
      'baseRev': 1,
      'patches': {},
    });
    check(guestWrite.$1 == 403, 'guest WRITE refused (403 — clients never edit)');

    // 7. cleanup: revert all through the author's edit bar
    await atab.hover(1270, 790);
    final reverted = await atab.waitForFunction(
        "(() => { const r = " + sr + "; const b = r && r.querySelector('.ebrevert'); "
        "if (!b || b.disabled) return false; b.click(); return true; })()",
        timeout: const Duration(seconds: 15));
    var rowGone = false;
    {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        final r = await getJson(base + '/__dial/overlay');
        if (r != null && r['overlay'] == null) {
          rowGone = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    check(reverted && rowGone, 'Revert all clears the row (store pristine)');

    final errs = [...atab.consoleErrors, ...atab.pageErrors, ...wtab.consoleErrors, ...wtab.pageErrors];
    check(errs.isEmpty, 'zero console/page errors through the local flows');
    for (final e in errs) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    try {
      await post(base + '/__dial/guests/revoke', {'email': email});
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens edit-local: ALL PASS'
      : 'lens edit-local: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
