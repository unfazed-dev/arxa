// One-off page-state probe for the live desktop engine (2026-09-03).
// Usage: dart run tool/lens_probe_page.dart <url> <orgId> <orgName>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  final url = argv[0];
  final orgId = argv[1];
  final orgName = argv[2];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 800);
    await tab.navigateAndSettle(url, settleMs: 3500);
    Future<dynamic> js(String expr) => tab.evaluate(expr);

    await js(
      "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='Continue');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 400));
    final open = await js(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'$orgId'})}).then(r=>r.text())");
    print('org.open -> $open');
    for (var i = 0; i < 10; i++) {
      final state = await js(
        "(()=>{const ti=[...document.querySelectorAll('[role=treeitem]')].map(e=>(e.textContent||'').slice(0,20));"
        "return { treeitems: ti.slice(0, 10), n: ti.length,"
        " bodyHasOrg: document.body.innerText.includes('$orgName'),"
        " bodyHasFile: document.body.innerText.includes('check.sh') } })()");
      print('t${i * 800}ms -> ${jsonEncode(state)}');
      if (state is Map && state['bodyHasFile'] == true) break;
      await Future.delayed(const Duration(milliseconds: 800));
    }
    final png = await tab.screenshot();
    File('/tmp/arxa-av26/live-page.png').writeAsBytesSync(png);
    print('shot -> /tmp/arxa-av26/live-page.png');
  } finally {
    await client.close();
  }
}
