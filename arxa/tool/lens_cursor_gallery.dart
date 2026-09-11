// lens_cursor_gallery — operator-visible evidence for the cursor COLOR
// LAW v3 pixel truth (2026-09-13): drives the real page, parks the pointer
// on the surfaces the operator called out — the pricing tier PHOTO, the
// card body, the CTA tile, the stories/hero VIDEO frames, the hiw zoom
// media — waits for the ring to settle, and screenshots WITH the cursor
// layer visible (the truth probe hides it; this one SHOWS it), logging the
// law's belief (surface/state/alpha/sampled) beside every shot. Usage:
//   dart run tool/lens_cursor_gallery.dart <url> --out <dir> [--palette name]
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty || !argv.contains('--out')) {
    stderr.writeln('usage: dart run tool/lens_cursor_gallery.dart <url> --out <dir> [--palette name]');
    exit(2);
  }
  var url = argv[0];
  final out = Directory(argv[argv.indexOf('--out') + 1]);
  final palette = argv.contains('--palette') ? argv[argv.indexOf('--palette') + 1] : null;
  if (palette != null) {
    final sep = url.contains('?') ? '&' : '?';
    url = url + sep + 'palette=' + palette;
  }
  await out.create(recursive: true);

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url, settleMs: 9000);

    // (name, scroll target id, progress or center, point selector, point mode)
    final shots = <List<String>>[
      ['pricing-photo', 'pricing', 'center', '.tier-card:nth-child(1) .tier-photo', 'center'],
      ['pricing-photo-2', 'pricing', 'center', '.tier-card:nth-child(2) .tier-photo', 'center'],
      ['pricing-body', 'pricing', 'center', '.tier-card:nth-child(1) .tier-description', 'center'],
      ['pricing-cta', 'pricing', 'center', '.tier-card:nth-child(1) .tier-cta', 'center'],
      ['hero-video', 'hero-section', 'center', '.stage-notify-video', 'center'],
      ['hiw-zoom', 'how-it-works', '0.9', '', 'viewport'],
      ['stories-video', 'clientstories', '0.15', '.story-media video', 'center'],
      ['stories-video-late', 'clientstories', '0.85', '.story-media video', 'center'],
    ];
    final log = StringBuffer();
    for (final s in shots) {
      final name = s[0];
      final info = await tab.evaluate('''
        (async () => {
          const id = ''' + "'" + s[1] + "'" + ''';
          const mode = ''' + "'" + s[2] + "'" + ''';
          const el = document.getElementById(id) || document.querySelector('.' + id);
          if (el) {
            if (mode === 'center') {
              el.scrollIntoView({ block: 'center' });
            } else {
              const p = parseFloat(mode);
              const rect = el.getBoundingClientRect();
              const top = rect.top + window.scrollY;
              window.scrollTo(0, top + p * Math.max(1, el.offsetHeight - window.innerHeight));
            }
          }
          await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
          await new Promise((r) => setTimeout(r, mode === 'center' ? 350 : 550));
          return true;
        })()
      ''', awaitPromise: true);
      if (info != true) continue;
      final point = await tab.evaluate('''
        (async () => {
          const sel = ''' + (s[3].isEmpty ? 'null' : "'" + s[3] + "'") + ''';
          const mode = ''' + "'" + s[4] + "'" + ''';
          let x = Math.round(window.innerWidth / 2);
          let y = Math.round(window.innerHeight / 2);
          if (sel && mode === 'center') {
            const el = document.querySelector(sel);
            if (el) {
              const r = el.getBoundingClientRect();
              if (r.width > 4 && r.height > 4) {
                x = Math.round(r.left + r.width / 2);
                y = Math.round(r.top + r.height / 2);
              }
            }
          }
          x = Math.max(12, Math.min(window.innerWidth - 12, x));
          y = Math.max(12, Math.min(window.innerHeight - 12, y));
          document.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y }));
          await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
          await new Promise((r) => setTimeout(r, 500));
          const b = document.__arxaCursor || null;
          return { x, y, belief: b };
        })()
      ''', awaitPromise: true);
      final png = await tab.screenshot();
      final f = File(out.path + '/' + name + '.png');
      await f.writeAsBytes(png);
      final b = point is Map ? point['belief'] : null;
      final line = name + ' @' + (point is Map ? point['x'].toString() + ',' + point['y'].toString() : '?') +
          '  law=' + (b == null ? 'null' : b.toString());
      log.writeln(line);
      stdout.writeln(line);
    }
    await File(out.path + '/gallery-log.txt').writeAsString(log.toString());
    stdout.writeln('GALLERY DONE -> ' + out.path);
    await client.close();
    exit(0);
  } catch (e) {
    stderr.writeln('gallery error: ' + e.toString());
    await client.close();
    exit(1);
  }
}
