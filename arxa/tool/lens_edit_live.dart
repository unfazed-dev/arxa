// Live deployed-dial AUTHOR EDIT E2E (operator, 2026-09-11 — the edit
// redesign's headline story): the author edits text and swaps an image ON
// THE DEPLOYED SITE through the author link; a guest in a second (foreground)
// tab watches the page change IN REAL TIME; undo works session-locally;
// Revert-to-published snaps everyone back; the overlay row lands in Supabase
// and is left ABSENT at the end (store pristine). Never prints tokens.
//
//   dart run tool/lens_edit_live.dart <live-base-url> <design-server-url> <author-token>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln(
        'usage: dart run tool/lens_edit_live.dart <live-base-url> <design-server-url> <author-token>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final server = argv[1].replaceAll(RegExp(r'/$'), '');
  final authorToken = argv[2];
  const email = 'lens-edit-guest@arxa.dev';
  const marker = 'LENSLIVEEDIT';
  const imgUrl = 'https://images.unsplash.com/photo-1518791841217-8f162f1e1131?w=200';
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
    final res = await req.close().timeout(const Duration(seconds: 20));
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
    final res = await req.close().timeout(const Duration(seconds: 20));
    return utf8.decoder.bind(res).join();
  }

  const sr = "document.querySelector('#arxa-dial-host') && document.querySelector('#arxa-dial-host').shadowRoot";
  // The editor's own target vocabulary, mirrored from the island: the
  // walk binds to the NEAREST data-arxa-id OR data-el stamp.
  const editableJs = "(() => { const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
      "for (const el of els) { const t = (el.textContent || '').trim(); "
      "if (t.length > 0 && t.length < 300 && !el.querySelector('[data-arxa-id],[data-el]') "
      "&& el.getBoundingClientRect().width > 40) return el; } return null; })()";

  String? guestToken;
  String? sbUrl;
  String? anonKey;
  String? designId;
  final client = await CdpClient.launch();

  Future<Map<String, dynamic>?> overlayRow() async {
    if (sbUrl == null || designId == null) return null;
    try {
      final body = await get(
          sbUrl! + '/rest/v1/arxa_dial_overlays?design_id=eq.' + designId! + '&select=patches,rev', {
        'apikey': anonKey!,
        'Authorization': 'Bearer ' + anonKey!,
      });
      final rows = jsonDecode(body);
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        return (rows.first as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }
  Future<bool> untilRow(bool Function(Map<String, dynamic>) test, Duration cap) async {
    final deadline = DateTime.now().add(cap);
    while (DateTime.now().isBefore(deadline)) {
      final row = await overlayRow();
      if (row != null && test(row)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }
  Future<bool> untilNoRow(Duration cap) async {
    final deadline = DateTime.now().add(cap);
    while (DateTime.now().isBefore(deadline)) {
      if (await overlayRow() == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  try {
    // 1. mint the WATCHING guest's link (design-time route, local server)
    final mint = await post(server + '/__dial/guests', {'email': email, 'name': 'Lens Edit', 'days': 1});
    check(mint.$1 == 201 && mint.$2['token'] is String, 'guest link mints (got ' + mint.$1.toString() + ')');
    guestToken = mint.$2['token'] as String?;

    // 2. AUTHOR tab first (it becomes the background tab), GUEST second
    //    (CDP makes the newest tab active — the SSE/channel watcher must be
    //    the foreground tab, the hidden-tab law).
    final atab = await client.newTab();
    await atab.enable();
    await atab.setViewport(1280, 832);
    await atab.navigateAndSettle(base + '/?dial-author=' + authorToken, settleMs: 5000);
    final aCfg = await atab.evaluate(
        "(() => { const c = document.getElementById('arxa-dial-config'); return c ? c.textContent : ''; })()") as String;
    final cfg = jsonDecode(aCfg) as Map;
    check(cfg['mode'] == 'author', 'author link boots the deployed dial in author mode');
    sbUrl = (cfg['static'] as Map)['url'] as String;
    anonKey = (cfg['static'] as Map)['anonKey'] as String;
    designId = (cfg['static'] as Map)['designId'] as String;
    check(await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25)), 'author dock boots');

    final gtab = await client.newTab();
    await gtab.enable();
    await gtab.setViewport(1280, 832);
    await gtab.navigateAndSettle(base + '/?dial=' + guestToken!, settleMs: 5000);
    check(await gtab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#dockbtn'); })()",
        timeout: const Duration(seconds: 25)), 'guest dock boots');
    final gVerbs = await gtab.evaluate(sr + ".querySelectorAll('button.verb').length") as int;
    check(gVerbs == 2, 'guest dial carries exactly 2 verbs (no Edit — got ' + gVerbs.toString() + ')');

    // 3. the author reveals the dial (hot corner) and arms Edit Mode
    await atab.hover(1270, 790);
    await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && r.querySelector('#dockbtn').classList.contains('open'); })()",
        timeout: const Duration(seconds: 8));
    await atab.evaluate("(() => { const r = " + sr + "; "
        "const v = r.querySelector('button.verb[data-verb=edit]'); if (!v) return false; v.click(); return true; })()");
    final armed = await atab.waitForFunction(
        "(() => { const r = " + sr + "; return r && !!r.querySelector('#editbar.open'); })()",
        timeout: const Duration(seconds: 8));
    check(armed, 'Edit Mode arms — the edit bar appears (Edit verb lives on the deployed site)');

    // 4. TEXT: double-click a text element, type, Enter
    final target = await atab.evaluate(
        "(() => { const el = " + editableJs + "; if (!el) return null; "
        "const r = el.getBoundingClientRect(); const mid = el.getAttribute('data-arxa-id'); "
        "return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2, "
        "id: (mid || ('el:' + (el.getAttribute('data-el') || ''))), text: el.textContent.trim()}); })()") as String?;
    check(target != null, 'a text-editable element is on the page');
    final t = jsonDecode(target!) as Map;
    final original = t['text'] as String;
    final cx = (t['x'] as num).round();
    final cy = (t['y'] as num).round();
    await atab.hover(cx, cy);
    await atab.dblclick(cx, cy);
    final typing = await atab.waitForFunction(
          "(() => { const k = '" + t['id']! + "'; "
          "const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
          "const el = els.find(e => (k.indexOf('el:') === 0 "
          "? ('el:' + (e.getAttribute('data-el') || '')) "
          ": e.getAttribute('data-arxa-id')) === k); "
          "return el && el.getAttribute('data-arxa-inline-editing') === '1'; })()",
        timeout: const Duration(seconds: 8));
    check(typing, 'double-click opens on-canvas typing (contenteditable)');
    for (final ch in marker.split('')) {
      await atab.key(ch);
    }
    final typed = await atab.evaluate(
          "(() => { const k = '" + t['id']! + "'; "
          "const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
          "const el = els.find(e => (k.indexOf('el:') === 0 "
          "? ('el:' + (e.getAttribute('data-el') || '')) "
          ": e.getAttribute('data-arxa-id')) === k); "
          "return el ? el.textContent : null; })()") as String?;
    check(typed != null && typed!.contains(marker),
        'the typed text is in the element before commit');
    await atab.key('Enter'); // commits (the island's Enter law)
    final rowSaved = await untilRow(
        (row) => ((row['patches'] as Map)[t['id']!] as Map?)?['text'] == marker,
        const Duration(seconds: 25));
    check(rowSaved, 'the text edit lands in arxa_dial_overlays (debounced save → save_overlay RPC)');

    // 5. the AUTHOR page shows the new text (live apply, survive the converge reload)
    final aSeen = await atab.waitForFunction(
        "document.body.textContent.includes('" + marker + "')",
        timeout: const Duration(seconds: 25));
    check(aSeen, 'author page shows the new text');

    // 6. the GUEST page repaints IN REAL TIME (frame + apply; the converge
    //    reload follows, the text assert survives both)
    final gSeen = await gtab.waitForFunction(
        "document.body.textContent.includes('" + marker + "')",
        timeout: const Duration(seconds: 25));
    check(gSeen, 'GUEST page shows the new text in real time — clients watch the author work');

    // 7. UNDO (session-local): the edit bar's undo returns the original and
    //    empties the row (rev 0 = deleted). The author's converge reload
    //    lands ~1.4s after the save — let it settle first (the stack rides
    //    sessionStorage and survives), and RETRY the click: a click on the
    //    dying page is lost, the button comes back armed post-reload.
    await Future<void>.delayed(const Duration(seconds: 3));
    var undid = false;
    {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        final row = await overlayRow();
        if (row == null) { undid = true; break; }
        await atab.hover(1270, 790);
        await atab.evaluate("(() => { const r = " + sr + "; const b = r && r.querySelector('.ebundo'); "
            "if (b && !b.disabled) b.click(); return true; })()");
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    final rowGone = await untilNoRow(const Duration(seconds: 20));
    check(undid && rowGone, 'undo reverts the edit and the overlay row dies (rev 0)');
    final gBack = await gtab.waitForFunction(
        "!document.body.textContent.includes('" + marker + "')",
        timeout: const Duration(seconds: 25));
    check(gBack, 'guest page snaps back (revert frame → reload)');

    // 8. IMAGE: click an image, swap by pasting a URL (the static surface)
    // The media surface is a stamped WRAPPER carrying an img/video (the
    // live artifact stamps wrappers; the media inside is unstamped).
    final img = await atab.evaluate(
        "(() => { const els = [...document.querySelectorAll('[data-arxa-id],[data-el]')]; "
        "for (const el of els) { if (!el.querySelector('img,video')) continue; "
        "if (el.querySelector('[data-arxa-id],[data-el]')) continue; "
        "const r = el.getBoundingClientRect(); if (r.width < 40 || r.height < 40) continue; "
        "if (r.bottom < 0 || r.top > innerHeight) continue; "
        "const mid = el.getAttribute('data-arxa-id'); "
        "return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2, "
        "id: (mid || ('el:' + (el.getAttribute('data-el') || '')))}); } return null; })()") as String?;
    check(img != null, 'a media-bearing stamped wrapper is on the page');
    if (img != null) {
      final im = jsonDecode(img) as Map;
      await atab.hover(1270, 790);
      await atab.waitForFunction(
          "(() => { const r = " + sr + "; return r && !!r.querySelector('#editbar.open'); })()",
          timeout: const Duration(seconds: 10));
      await atab.hover((im['x'] as num).round(), (im['y'] as num).round());
      await atab.click((im['x'] as num).round(), (im['y'] as num).round());
      final chipUp = await atab.waitForFunction(
          "(() => { const r = " + sr + "; const c = r && r.querySelector('#echip.open'); "
          "return c && [...c.querySelectorAll('button')].some(b => b.textContent.includes('Swap')); })()",
          timeout: const Duration(seconds: 8));
      check(chipUp, 'clicking an image opens the chip with Swap');
      await atab.evaluate("(() => { const r = " + sr + "; "
          "[...r.querySelectorAll('#echip.open button')].find(b => b.textContent.includes('Swap')).click(); return 1; })()");
      await atab.waitForFunction(
          "(() => { const r = " + sr + "; return r && !!r.querySelector('#epanel.open input'); })()",
          timeout: const Duration(seconds: 8));
      await atab.evaluate("(() => { const r = " + sr + "; const i = r.querySelector('#epanel.open input'); "
          "i.value = '" + imgUrl + "'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1; })()");
      await atab.evaluate("(() => { const r = " + sr + "; const p = r.querySelector('#epanel.open'); "
          "[...p.querySelectorAll('button')].find(b => b.textContent.trim() === 'Swap').click(); return 1; })()");
      final imgRow = await untilRow(
          (row) => (((row['patches'] as Map)[im['id']!] as Map?)?['attrs'] as Map?)?['src'] == imgUrl,
          const Duration(seconds: 25));
      check(imgRow, 'the image swap lands in the overlay (attrs.src, paste-URL surface)');
      final gImgOk = await gtab.waitForFunction(
          "[...document.querySelectorAll('img,video')].some(i => (i.currentSrc || i.src || i.getAttribute('src') || '').includes('photo-1518791841217'))",
          timeout: const Duration(seconds: 25));
      check(gImgOk, 'guest page shows the swapped image (attr-only frame — purely live, no reload)');

      // 9. Revert-to-published: the row dies, everyone returns to source
      await atab.hover(1270, 790);
      final reverted = await atab.waitForFunction(
          "(() => { const r = " + sr + "; const b = r && r.querySelector('.ebrevert'); "
          "if (!b || b.disabled) return false; b.click(); return true; })()",
          timeout: const Duration(seconds: 15));
      final rowGone2 = await untilNoRow(const Duration(seconds: 20));
      check(reverted && rowGone2, 'Revert-to-published clears the overlay row');
      final gImgBack = await gtab.waitForFunction(
          "![...document.querySelectorAll('img,video')].some(i => (i.currentSrc || i.src || i.getAttribute('src') || '').includes('photo-1518791841217'))",
          timeout: const Duration(seconds: 25));
      check(gImgBack, 'guest image returns to the published source');
    }

    final aErrs = [...atab.consoleErrors, ...atab.pageErrors];
    final gErrs = [...gtab.consoleErrors, ...gtab.pageErrors];
    check(aErrs.isEmpty && gErrs.isEmpty, 'zero console/page errors through the edit flows');
    for (final e in aErrs.followedBy(gErrs)) {
      stdout.writeln('  err: ' + e);
    }
  } finally {
    try {
      await post(server + '/__dial/guests/revoke', {'email': email});
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens edit-live: ALL PASS'
      : 'lens edit-live: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
