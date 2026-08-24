// Ask-arxa probe (slice 7): the full handoff loop in real Chrome —
// open a card on a real element, tap ✨ arxa, prove the selection landed
// server-side with an organized context (label/kind/styles/text/law),
// the PNG captured (best-effort — foreignObject rasterization), and the
// SSE broadcast frame fired for the studio plugin.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appboxd/cdp.dart';
Future<dynamic> js(CdpSession tab, String e) => tab.evaluate(e);
const SR = "document.getElementById('arxa-dial-host').shadowRoot";
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

  // SSE reader running BEFORE the tap, capturing dial frames.
  final frames = <String>[];
  await js(tab, '''
    window.__probeFrames = [];
    (() => {
      const es = new EventSource('/__dial/events');
      es.addEventListener('dial', (ev) => { window.__probeFrames.push(ev.data); });
    })()
  ''');

  // Arm Edit Mode and select a text element.
  for (var i = 0; i < 5; i++) {
    await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': 1276 - i, 'y': 796 - i});
    await Future.delayed(const Duration(milliseconds: 80));
  }
  await Future.delayed(const Duration(milliseconds: 900));
  await js(tab, '$SR.querySelector("#dockbtn").click()');
  await Future.delayed(const Duration(milliseconds: 400));
  await js(tab, "$SR.querySelector('[data-verb=edit]').click()");
  await Future.delayed(const Duration(milliseconds: 300));
  final pt = await js(tab, '''
    (() => {
      const els = [...document.querySelectorAll('[data-arxa-id]')];
      for (const el of els) {
        const t = (el.textContent || '').trim();
        if (!t || t.length < 3 || el.querySelector('[data-arxa-id]')) continue;
        const r = el.getBoundingClientRect();
        if (r.width > 40 && r.height > 12 && r.x >= 0 && r.y >= 0 &&
            r.x + r.width <= innerWidth && r.y + r.height <= innerHeight) {
          return {x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2)};
        }
      }
      return null;
    })()
  ''');
  if (pt is! Map) { check(false, 'a selectable text element in view'); await client.close(); exit(1); }
  final x = (pt['x'] as num).toInt(), y = (pt['y'] as num).toInt();
  await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y});
  await tab.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await tab.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': 'left', 'clickCount': 1});
  await Future.delayed(const Duration(milliseconds: 500));
  final cardOpen = await js(tab, '$SR.querySelector("#card").classList.contains("open")');
  check(cardOpen == true, 'card opens on a real text element');

  // Tap ✨ arxa.
  final tapped = await js(tab, '''
    (() => {
      const ask = $SR.querySelector('#chead button[title*=arxa]');
      if (!ask) return false;
      ask.click();
      return true;
    })()
  ''');
  check(tapped == true, 'Ask-arxa button present and tapped');
  await Future.delayed(const Duration(milliseconds: 2500));

  // The SSOT: fetch the pointer from the last selection frame / probe state.
  final ssot = await js(tab, '''
    (async () => {
      const frames = (window.__probeFrames || []).map((f) => { try { return JSON.parse(f); } catch (_) { return null; } });
      const sel = [...frames].reverse().find((f) => f && f.kind === 'selection');
      if (!sel) return {frame: false};
      const r = await fetch(sel.data.fetch);
      return {frame: true, status: r.status, body: await r.json()};
    })()
  ''');
  final s = (ssot as Map).cast<String, dynamic>();
  check(s['frame'] == true, 'selection frame broadcast on /__dial/events');
  final body = (s['body'] as Map?)?.cast<String, dynamic>() ?? {};
  check(s['status'] == 200, 'SSOT GET answers 200');
  check(body.isNotEmpty && (body['key'] as String?) != null && (body['key'] as String).isNotEmpty,
      'organized context carries the patch key (${body['key']})');
  check((body['law'] as String? ?? '').contains('LOCKED'), 'law rides the context');
  check(body['styles'] is Map && (body['styles'] as Map).isNotEmpty,
      'style digest present (${(body['styles'] as Map).keys.toList().take(3).join(',')})');
  final png = body['png'] as String?;
  stdout.writeln('png captured: ${png == null ? "null (best-effort path)" : png.length.toString() + " chars"}');
  check(tab.consoleErrors.isEmpty, 'console clean (${tab.consoleErrors.length})');

  stdout.writeln(fails == 0 ? 'ALL PROBES PASS' : '$fails PROBES FAILED');
  await client.close();
  exit(fails == 0 ? 0 : 1);
}
