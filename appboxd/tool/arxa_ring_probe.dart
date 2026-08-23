
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appboxd/cdp.dart';

const prompt = "Use the gen_ui tool to build one pricing-card surface. Start with the card container itself, then fill it top to bottom, in order: a header reading \"Studio\", a price row \"\$29 / month\", four feature rows (Fast setup · Unlimited projects · Team roles · Priority support), and a primary CTA button \"Start free\". Emit it as one continuous build so I can watch the card assemble.";

const sessionsRoot =
    '/Users/unfazed-mac/.arxa/dsh/sessions/--Volumes-developer_ssd-Developer-totem_labs-arxa-studio--';

const ledgerJs = r'''

window.__ledger = [];
window.__t0 = performance.now();
document.addEventListener('animationstart', (e) => {
  try {
    const r = e.target.getBoundingClientRect();
    const cn = (e.target.className && e.target.className.baseVal !== undefined) ? e.target.className.baseVal : String(e.target.className || '');
    window.__ledger.push({
      t: Math.round(performance.now() - window.__t0),
      name: e.animationName,
      pseudo: e.pseudoElement || '',
      tag: e.target.tagName.toLowerCase(),
      cls: cn.slice(0, 90),
      w: Math.round(r.width), h: Math.round(r.height),
      txt: (e.target.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40)
    });
  } catch (_) {}
}, true);
'armed';

''';

String? newestSessionLog() {
  final dir = Directory(sessionsRoot);
  if (!dir.existsSync()) return null;
  String? best;
  var bestM = DateTime.fromMillisecondsSinceEpoch(0);
  for (final e in dir.listSync()) {
    if (e is! Directory) continue;
    final f = File(e.path + '/session.jsonl.zstd');
    if (!f.existsSync()) continue;
    final m = f.lastModifiedSync();
    if (m.isAfter(bestM)) { bestM = m; best = f.path; }
  }
  return best;
}

Future<bool> turnEnded(String path) async {
  try {
    final res = await Process.run('zstd', ['-dc', path]);
    return (res.stdout as String).contains('"turn/end"');
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  final frames = Directory('/tmp/ring-frames');
  if (frames.existsSync()) frames.deleteSync(recursive: true);
  frames.createSync(recursive: true);

  final client = await CdpClient.launch();
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettle('http://127.0.0.1:7891/', settleMs: 3500);
  print('navigated');

  print('ledger: ' + (await tab.evaluate(ledgerJs)).toString());

  final filled = await tab.evaluate('(() => {'
      ' const e = document.querySelector("textarea");'
      ' if (!e) return "no-textarea";'
      ' const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set;'
      ' setter.call(e, ' + jsonEncode(prompt) + ');'
      ' e.dispatchEvent(new Event("input", {bubbles: true}));'
      ' e.focus();'
      ' return "filled:" + e.value.length.toString();'
      '})()');
  print('composer: ' + filled.toString());

  await tab.key('Enter');
  await Future.delayed(const Duration(seconds: 3));
  final log = newestSessionLog();
  print('watching log: ' + log.toString());
  if (log == null) { print('FATAL: no session log found'); await client.close(); return; }

  var lastLen = -1;
  var quiet = 0;
  var polls = 0;
  final sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(minutes: 8)) {
    await Future.delayed(const Duration(seconds: 3));
    polls++;
    final s = await tab.evaluate('JSON.stringify({'
        ' n: (window.__ledger || []).length,'
        ' cta: [...document.querySelectorAll(".arxa-genui-enter")].some(e => e.textContent.includes("Start free")),'
        ' surfaces: document.querySelectorAll(".arxa-genui-enter").length'
        '})');
    final m = jsonDecode(s as String) as Map<String, dynamic>;
    final n = (m['n'] as num).toInt();
    if (n == lastLen) { quiet += 3; } else { quiet = 0; lastLen = n; }
    final ended = await turnEnded(log);
    print('poll ' + polls.toString() + ' t=' + sw.elapsed.inSeconds.toString() + 's events=' + n.toString() + ' quiet=' + quiet.toString() + 's surfaces=' + m['surfaces'].toString() + ' cta=' + m['cta'].toString() + ' turnEnd=' + ended.toString());
    final png = await tab.screenshot();
    File('/tmp/ring-frames/f' + polls.toString().padLeft(3, '0') + '.png').writeAsBytesSync(png);
    if (ended && quiet >= 20) break;
  }
  print('done after ' + sw.elapsed.inSeconds.toString() + 's, events=' + lastLen.toString());

  final ledger = await tab.evaluate('JSON.stringify(window.__ledger)');
  File('/tmp/ring-ledger.json').writeAsStringSync(ledger as String);
  final png = await tab.screenshot();
  File('/tmp/studio-after.png').writeAsBytesSync(png);
  print('ledger + final screenshot written');
  await client.close();
}
