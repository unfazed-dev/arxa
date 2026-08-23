// dial_probe.dart — E2E evidence for the Design Dial Feedback slice:
// drives the LIVE served artifact over CDP through the shadow DOM:
// boots the dial, expands the radial, arms pin mode, drops a pin on a real
// element, verifies the badge, mints a Share Link, opens the guest view,
// and screenshots each stage to /tmp/dial-frames/.
//
// Run with the server live:  dart run tool/dial_probe.dart [base-url]
// (defaults to http://127.0.0.1:4321/)

import 'dart:io';
import 'package:appboxd/cdp.dart';

String _base = 'http://127.0.0.1:4321';

Future<dynamic> shadow(CdpSession tab, String js) => tab.evaluate(
    '(async () => { const R = document.getElementById("arxa-dial-host").shadowRoot; $js })()');

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) _base = args[0].replaceAll(RegExp('/\$'), '');
  Directory('/tmp/dial-frames').createSync(recursive: true);
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettle('$_base/', settleMs: 2500);

  // 1. The dial booted (author mode, store badge data). Bounded retry:
  // the first evaluate can race the navigation's execution-context swap and
  // read a stale document — NO-HOST then means "not yet", not "missing".
  String boot = 'NO-HOST';
  for (var i = 0; i < 10; i++) {
    boot = await tab.evaluate('''(() => {
      const host = document.getElementById("arxa-dial-host");
      if (!host) return "NO-HOST";
      const cfg = JSON.parse(document.getElementById("arxa-dial-config").textContent);
      return JSON.stringify({mode: cfg.mode, store: cfg.store, artifact: cfg.artifact, shadow: !!host.shadowRoot});
    })()''') as String;
    if (boot != 'NO-HOST') break;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print('boot: $boot');
  if (boot == 'NO-HOST') throw StateError('dial never booted');

  // 2. Expand the radial fan.
  await shadow(tab, 'R.querySelector("#dockbtn").click(); await new Promise(r=>setTimeout(r,400)); return "ok";');
  File('/tmp/dial-frames/01-radial.png').writeAsBytesSync(await tab.screenshot());

  // 3. Arm pin mode, then click a real design element (canvas click at the
  // element's center so the inspect-walk resolves its data-el).
  final armed = await shadow(tab, '''
    R.querySelector('[data-verb="pin"]').click();
    await new Promise(r=>setTimeout(r,200));
    const target = document.querySelector("[data-el]");
    if (!target) return "NO-DATA-EL";
    const r = target.getBoundingClientRect();
    const cx = r.left + r.width/2, cy = r.top + r.height/2;
    document.dispatchEvent(new PointerEvent("pointermove", {clientX: cx, clientY: cy, bubbles: true}));
    document.dispatchEvent(new MouseEvent("click", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,300));
    return JSON.stringify({armed: true, el: target.getAttribute("data-el"), composer: R.querySelector("#composer").classList.contains("open")});
  ''');
  print('armed: $armed');
  File('/tmp/dial-frames/02-composer.png').writeAsBytesSync(await tab.screenshot());

  // 4. Fill the composer and add the pin.
  final added = await shadow(tab, '''
    const area = R.querySelector("#composer textarea");
    area.value = "Probe pin — this headline needs more room";
    const btns = [...R.querySelectorAll("#composer .btn")];
    btns.find(b => b.textContent === "Add pin").click();
    await new Promise(r=>setTimeout(r,700));
    return JSON.stringify({pins: R.querySelectorAll("#pins .pin").length, badge: R.querySelector("#dockbtn .dot").textContent});
  ''');
  print('added: $added');
  File('/tmp/dial-frames/03-pin-placed.png').writeAsBytesSync(await tab.screenshot());

  // 4b. Draw-over: arm the pen, sketch two strokes, then pin — the strokes
  // must ATTACH to the pin (locked 2026-08-23: drawings attach to pins).
  final drew = await shadow(tab, '''
    R.querySelector('[data-verb="pen"]').click();
    await new Promise(r=>setTimeout(r,150));
    const cv = R.querySelector("#draw");
    function stroke(x0,y0,x1,y1) {
      cv.dispatchEvent(new PointerEvent("pointerdown", {clientX:x0, clientY:y0, bubbles:true, pointerId:1}));
      for (let i=1;i<=8;i++) {
        cv.dispatchEvent(new PointerEvent("pointermove", {clientX:x0+(x1-x0)*i/8, clientY:y0+(y1-y0)*i/8, bubbles:true, pointerId:1}));
      }
      cv.dispatchEvent(new PointerEvent("pointerup", {clientX:x1, clientY:y1, bubbles:true, pointerId:1}));
    }
    stroke(500, 300, 700, 260);
    stroke(700, 260, 720, 340);
    await new Promise(r=>setTimeout(r,150));
    // now arm pin and click the same element
    R.querySelector('[data-verb="pin"]').click();
    await new Promise(r=>setTimeout(r,150));
    const target = document.querySelector("[data-el]");
    const r2 = target.getBoundingClientRect();
    document.dispatchEvent(new MouseEvent("click", {clientX: r2.left+r2.width/2, clientY: r2.top+r2.height/2, bubbles: true}));
    await new Promise(r=>setTimeout(r,300));
    const note = R.querySelector("#composer").textContent.includes("stroke(s) will attach");
    return JSON.stringify({attachNote: note});
  ''');
  print('drew: $drew');
  File('/tmp/dial-frames/03b-draw-attach.png').writeAsBytesSync(await tab.screenshot());
  final addedDraw = await shadow(tab, '''
    const area = R.querySelector("#composer textarea");
    area.value = "Probe pin with drawing — arrows mean widen this";
    [...R.querySelectorAll("#composer .btn")].find(b => b.textContent === "Add pin").click();
    await new Promise(r=>setTimeout(r,800));
    const pins = await fetch("/__dial/pins").then(r=>r.json());
    const withDrawing = pins.pins.filter(p => p.drawing).length;
    const drawnBadges = R.querySelectorAll("#pins .pin.drawn").length;
    return JSON.stringify({withDrawing, drawnBadges, strokes: pins.pins.find(p=>p.drawing)?.drawing?.length});
  ''');
  print('added-with-drawing: $addedDraw');

  // 5. Open the thread and move the kanban (author power).
  final kanban = await shadow(tab, '''
    R.querySelector("#pins .pin").click();
    await new Promise(r=>setTimeout(r,300));
    const threadOpen = R.querySelector("#thread").classList.contains("open");
    const st = [...R.querySelectorAll("#thread .stbtn")].find(b => b.textContent === "Triaged");
    if (!st) return JSON.stringify({threadOpen, kanban: "NO-STATUS-BUTTONS"});
    st.click();
    await new Promise(r=>setTimeout(r,700));
    const pin = await fetch("/__dial/pins").then(r=>r.json());
    return JSON.stringify({threadOpen, status: pin.pins[0].status});
  ''');
  print('kanban: $kanban');
  File('/tmp/dial-frames/04-thread-kanban.png').writeAsBytesSync(await tab.screenshot());

  // 6. Review shade to max.
  await shadow(tab, '''
    R.querySelector('[data-verb="shade"]').click();
    await new Promise(r=>setTimeout(r,200));
    const slider = R.querySelector("#pbody input[type=range]");
    slider.value = "60"; slider.dispatchEvent(new Event("input"));
    await new Promise(r=>setTimeout(r,300)); return "ok";
  ''');
  File('/tmp/dial-frames/05-shade.png').writeAsBytesSync(await tab.screenshot());

  // 7. Mint a Share Link and open the GUEST view in a second tab.
  final share = await tab.evaluate('''(async () => {
    const r = await fetch("/__dial/share", {method: "POST", headers: {"Content-Type": "application/json"}, body: "{}"}).then(r=>r.json());
    return r.token || "MINT-FAILED";
  })()''');
  print('share token: ${share.toString().substring(0, 8)}…');
  final guest = await client.newTab();
  await guest.enable();
  await guest.setViewport(1280, 800);
  await guest.navigateAndSettle('$_base/?dial=$share', settleMs: 2500);
  final gmode = await guest.evaluate('''(() => {
    const cfg = JSON.parse(document.getElementById("arxa-dial-config").textContent);
    return JSON.stringify({mode: cfg.mode, pins: null});
  })()''');
  print('guest mode: $gmode');
  // Guest sees the author's pin; guest has NO kanban buttons in the thread.
  final gthread = await shadow(guest, '''
    await new Promise(r=>setTimeout(r,600));
    const pinCount = R.querySelectorAll("#pins .pin").length;
    const p = R.querySelector("#pins .pin");
    if (p) p.click();
    await new Promise(r=>setTimeout(r,300));
    const statuses = R.querySelectorAll("#thread .stbtn").length;
    return JSON.stringify({pinCount, statuses, note: "statuses must be 0 for guests"});
  ''');
  print('guest thread: $gthread');
  File('/tmp/dial-frames/06-guest-view.png').writeAsBytesSync(await guest.screenshot());

  await client.close();
  print('PROBE-DONE');
}
