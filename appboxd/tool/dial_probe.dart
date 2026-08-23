// dial_probe.dart — E2E evidence for the Design Dial Feedback slice:
// drives the LIVE served artifact over CDP through the shadow DOM:
// boots the dial, expands the radial, arms pin mode, drops a pin on a real
// element, verifies the badge, mints a Share Link, opens the guest view,
// and screenshots each stage to /tmp/dial-frames/.
//
// Run with the server live:  dart run tool/dial_probe.dart

import 'dart:io';
import 'package:appboxd/cdp.dart';

Future<dynamic> shadow(CdpSession tab, String js) => tab.evaluate(
    '(async () => { const R = document.getElementById("arxa-dial-host").shadowRoot; $js })()');

Future<void> main() async {
  final out = Directory('/tmp/dial-frames')..createSync();
  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettle('http://127.0.0.1:4321/', settleMs: 2500);

  // 1. The dial booted in author mode with the memory store badge data.
  final boot = await tab.evaluate('''(() => {
    const host = document.getElementById("arxa-dial-host");
    if (!host) return "NO-HOST";
    const cfg = JSON.parse(document.getElementById("arxa-dial-config").textContent);
    return JSON.stringify({mode: cfg.mode, store: cfg.store, artifact: cfg.artifact, shadow: !!host.shadowRoot});
  })()''');
  print('boot: $boot');

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
  await guest.navigateAndSettle('http://127.0.0.1:4321/?dial=$share', settleMs: 2500);
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
