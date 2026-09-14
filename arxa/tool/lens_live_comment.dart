// Live deployed-dial COMMENT E2E (operator, 2026-09-10): proves the third
// Supabase capability end-to-end on the PUBLISHED site — a minted guest
// arms Comment, drops a pin through the real composer, the row lands in
// arxa_dial_pins with guest attribution, a reply lands in arxa_dial_replies
// through the real thread popover, and revoking the guest scrubs
// guest_email off BOTH rows while keeping the content (the PII contract).
// Cleans up its own rows via the service key in finally — a test pin never
// outlives the run. Never prints tokens or keys. Usage:
//   dart run tool/lens_live_comment.dart <live-base-url> <design-server-url>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/arxa_dial.dart' show parseSupabaseCredentials;

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln(
        'usage: dart run tool/lens_live_comment.dart <live-base-url> <design-server-url>');
    exit(2);
  }
  final base = argv[0].replaceAll(RegExp(r'/$'), '');
  final server = argv[1].replaceAll(RegExp(r'/$'), '');
  const email = 'comment-probe@arxa.dev';
  const marker = 'lens comment probe v11';
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

  // service key from the operator credentials file (cleanup only, never printed)
  final home = Platform.environment['HOME'] ?? '.';
  final creds = parseSupabaseCredentials(
      File(home + '/.arxa/supabase').readAsStringSync());
  final sbUrl = creds.url;
  final serviceKey = creds.key;

  String? token;
  String? anonKey;
  String? designId;
  String? pinId;
  final client = await CdpClient.launch();
  try {
    // 1. mint the probe guest
    final mint = await post(server + '/__dial/guests',
        {'email': email, 'name': 'Comment Probe', 'days': 1});
    check(mint.$1 == 201, 'probe guest mints (got ' + mint.$1.toString() + ')');
    token = mint.$2['token'] as String?;

    // 2. boot the deployed dial as the guest
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    Future<dynamic> ev(String js) => tab.evaluate(js);
    await tab.navigateAndSettle(base + '/?dial=' + token!, settleMs: 5000);
    final cfg = await ev(
        "(() => { const c = JSON.parse(document.getElementById('arxa-dial-config').textContent);"
        " const r = window.__ARXA_PALETTE__.remote;"
        " return { mode: c.mode, anon: r.anonKey, did: c.static ? c.static.designId : '' }; })()") as Map;
    check(cfg['mode'] == 'guest', 'dial boots in guest mode');
    anonKey = cfg['anon'] as String?;
    designId = cfg['did'] as String? ?? '';
    final docked = await tab.waitForFunction(
        "!!document.querySelector('#arxa-dial-host').shadowRoot.querySelector('#dockbtn')",
        timeout: const Duration(seconds: 25));
    check(docked, 'guest identity resolves — the dock boots');
    const sr = "document.querySelector('#arxa-dial-host').shadowRoot";

    // 3. arm Comment and drop a pin through the real composer
    // the verbs carry class 'verb' — the dock button's own face text also
    // contains the word 'Comment', so filtering by text alone clicks the
    // dock instead of arming.
    await ev("(() => { const r = " + sr + "; r.querySelector('#dockbtn').click(); "
        "const v = [...r.querySelectorAll('button.verb')].filter(b => /Comment/.test(b.textContent)); "
        "v[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tab.click(520, 380); // on the page, clear of the parked dial
    final composerOpen = await tab.waitForFunction(
        "(() => { const r = " + sr + "; const c = r.querySelector('#composer');"
        " return c && c.classList.contains('open') && !!c.querySelector('textarea'); })()",
        timeout: const Duration(seconds: 8));
    check(composerOpen, 'clicking the design drops into the composer');
    await ev("(() => { const r = " + sr + "; const a = r.querySelector('#composer textarea'); "
        "a.value = '" + marker + "'; a.dispatchEvent(new Event('input', { bubbles: true })); "
        "const add = [...r.querySelectorAll('#composer button')].filter(b => /add pin/i.test(b.textContent)); "
        "add[0].click(); return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    // 4. the row landed in Supabase with guest attribution
    Future<List<dynamic>> pinRows() async {
      final text = await get(
          sbUrl! + '/rest/v1/arxa_dial_pins?design_id=eq.' + designId! +
              '&select=*,arxa_dial_replies(*)&body=eq.' + Uri.encodeComponent(marker),
          {'apikey': anonKey!, 'Authorization': 'Bearer ' + anonKey!});
      try {
        return jsonDecode(text) as List<dynamic>;
      } catch (_) {
        return const [];
      }
    }
    var rows = await pinRows();
    if (rows.length != 1) {
      stdout.writeln('  debug: pinRows read back ' + rows.length.toString()
          + ' — raw probe of the design row follows');
      stdout.writeln('  debug: sbUrl=' + (sbUrl ?? 'NULL')
          + ' designId=' + designId.toString()
          + ' anonKey=' + (anonKey == null ? 'NULL' : 'present'));
      try {
        final raw = await get(
            sbUrl! + '/rest/v1/arxa_dial_pins?design_id=eq.' + designId!
                + '&select=id,body&order=created_at.desc&limit=5',
            {'apikey': anonKey!, 'Authorization': 'Bearer ' + anonKey!});
        stdout.writeln('  debug: recent rows: ' + raw);
      } catch (e) {
        stdout.writeln('  debug: recent-rows read threw: ' + e.toString());
      }
    }
    check(rows.length == 1, 'the pin row landed in arxa_dial_pins');
    if (rows.isNotEmpty) {
      final row = rows.first as Map<String, dynamic>;
      pinId = row['id'] as String?;
      check(row['author_kind'] == 'guest', 'attributed author_kind guest');
      check(row['guest_email'] == email,
          'attributed to the guest email (got ' + row['guest_email'].toString() + ')');
      check(row['status'] == 'open', 'born open on the kanban');
    }

    // 5. a reply through the real thread popover
    await ev("(() => { const r = " + sr + "; const p = [...r.querySelectorAll('.pin')]"
        ".find(x => (x.title || '').includes('" + marker + "')); "
        "if (p) p.click(); return 1; })()");
    final threadOpen = await tab.waitForFunction(
        "(() => { const r = " + sr + "; const t = r.querySelector('#thread');"
        " return t && t.classList.contains('open') && !!t.querySelector('input'); })()",
        timeout: const Duration(seconds: 8));
    check(threadOpen, 'the pin marker opens the thread popover');
    await ev("(() => { const r = " + sr + "; const i = r.querySelector('#thread input'); "
        "i.value = 'probe reply'; i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); "
        "return 1; })()");
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    rows = await pinRows();
    final replies = rows.isNotEmpty
        ? (rows.first as Map<String, dynamic>)['arxa_dial_replies'] as List? ?? const []
        : const [];
    check(replies.isNotEmpty, 'the reply landed in arxa_dial_replies');
    if (replies.isNotEmpty) {
      final rr = replies.first as Map<String, dynamic>;
      check(rr['guest_email'] == email, 'the reply carries guest attribution too');
    }

    // 6. revoke — the PII contract: emails scrubbed, content kept
    final revoke = await post(server + '/__dial/guests/revoke', {'email': email});
    check(revoke.$1 == 200, 'the probe guest is revoked');
    rows = await pinRows();
    check(rows.isNotEmpty, 'the pin content SURVIVES the revoke');
    if (rows.isNotEmpty) {
      final row = rows.first as Map<String, dynamic>;
      check(row['guest_email'] == null,
          'the pin email is scrubbed (got ' + row['guest_email'].toString() + ')');
      final rreplies = row['arxa_dial_replies'] as List? ?? const [];
      if (rreplies.isNotEmpty) {
        check((rreplies.first as Map)['guest_email'] == null,
            'the reply email is scrubbed too');
      }
    }
  } finally {
    // cleanup: the probe's rows die with the run (service key, never printed)
    try {
      if (pinId != null && serviceKey != null) {
        await get(
            sbUrl! + '/rest/v1/arxa_dial_replies?pin_id=eq.' + pinId!,
            {'apikey': serviceKey, 'Authorization': 'Bearer ' + serviceKey});
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
    try {
      await post(server + '/__dial/guests/revoke', {'email': email});
    } catch (_) {}
    await client.close();
  }
  stdout.writeln(failures == 0
      ? 'lens live-comment: ALL PASS'
      : 'lens live-comment: ' + failures.toString() + ' FAILURES');
  exit(failures == 0 ? 0 : 1);
}
