// lens_cursor_lock — LOCK LAW gate (2026-09-13 CTA sweep): parks the
// pointer on EVERY CTA of the app's inventory (the data-el="cta:*" set,
// submits, cookie/utility buttons — plus the target-marked tier CTA,
// footer pill and story pill) and asserts the orb LOCKS: belief.sticking
// true, belief.stickTarget the expected element, and the COLOR LAW floors
// (dot >= 3.0, idle >= 2.0, stuck >= 3.0) at the LAW position — where the
// ring is actually drawn (belief.lawX/lawY, v3.1). Negative checks pin
// the contract's other edge: text zones (FAQ question, footer info link)
// and card bodies must NOT stick, and the footer email stays HIDDEN
// (chrome.js's own copy pill owns it). Home + academy, default palette
// plus the seeded five. Usage:
//   dart run tool/lens_cursor_lock.dart <url> [--out dir] [--palette name]
import 'dart:io';
import 'dart:math' as math;
import 'package:arxa/cdp.dart';

List<int> parseHex(String h) {
  final b = h.replaceAll('#', '');
  return [int.parse(b.substring(0, 2), radix: 16), int.parse(b.substring(2, 4), radix: 16), int.parse(b.substring(4, 6), radix: 16)];
}

// the law's css() renders rgb(r, g, b); seeded palettes may hand back hex
List<int> parseColor(String s) {
  final hex = RegExp(r'#[0-9a-fA-F]{6}').firstMatch(s);
  if (hex != null) return parseHex(hex.group(0)!);
  final rgb = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)').firstMatch(s);
  if (rgb != null) {
    return [int.parse(rgb.group(1)!), int.parse(rgb.group(2)!), int.parse(rgb.group(3)!)];
  }
  throw FormatException('unparseable color: ' + s);
}

// law parity (cursor.js mixAt): t is the fraction of the FIRST argument
// (the stroke color) — mixAt(state, surface, alpha) is the exact blend of
// a stroke painted at that alpha over the surface.
List<int> mixAt(List<int> a, List<int> b, double t) => [
      (a[0] * t + b[0] * (1 - t)).round(),
      (a[1] * t + b[1] * (1 - t)).round(),
      (a[2] * t + b[2] * (1 - t)).round(),
    ];

double channel(double c) {
  c = c / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(List<int> c) => 0.2126 * channel(c[0].toDouble()) + 0.7152 * channel(c[1].toDouble()) + 0.0722 * channel(c[2].toDouble());

double contrast(List<int> a, List<int> b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

// (name, selector, expect token in stickTarget, mode: lock|nolock|hidden, prep)
// prep: none | bottom (scroll to page bottom for the reveal footer) |
// stories (scroll to clientstories) | pricing | menu-open is not needed.
typedef Spot = (String, String, String, String, String);

Future<Map<String, Object?>?> park(CdpSession tab, String selector, String prep) async {
  final res = await tab.evaluate('''
    (async () => {
      const sel = ''' + "'" + selector + "'" + ''';
      const prep = ''' + "'" + prep + "'" + ''';
      if (prep === 'bottom') {
        window.scrollTo(0, document.documentElement.scrollHeight);
        await new Promise((r) => setTimeout(r, 1600));
      } else if (prep === 'middle') {
        window.scrollTo(0, document.documentElement.scrollHeight * 0.5);
        await new Promise((r) => setTimeout(r, 900));
      } else if (prep === 'pricing' || prep === 'stories') {
        const id = prep === 'pricing' ? 'pricing' : 'clientstories';
        const el = document.getElementById(id) || document.querySelector('.' + id);
        if (el) el.scrollIntoView({ block: 'center' });
        await new Promise((r) => setTimeout(r, 600));
      } else if (prep === 'scroll') {
        // generic: bring the target itself into view (academy's back link
        // sits below the fold at load)
        const el0 = document.querySelector(sel);
        if (el0) el0.scrollIntoView({ block: 'center' });
        await new Promise((r) => setTimeout(r, 600));
      }
      const el = document.querySelector(sel);
      if (!el) return { err: 'missing ' + sel };
      const r0 = el.getBoundingClientRect();
      if (r0.width < 4 || r0.height < 4) return { err: 'not visible ' + sel, rect: [r0.width, r0.height] };
      const x = Math.round(r0.left + r0.width / 2);
      const y = Math.round(r0.top + r0.height / 2);
      document.dispatchEvent(new MouseEvent('mousemove', { clientX: x, clientY: y }));
      await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      await new Promise((r) => setTimeout(r, 700));
      const b = document.__arxaCursor || null;
      return { x, y, belief: b };
    })()
  ''', awaitPromise: true);
  return res is Map<String, Object?> ? res : null;
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_cursor_lock.dart <url> [--out dir] [--palette name]');
    exit(2);
  }
  var url = argv[0];
  final outDir = argv.contains('--out') ? argv[argv.indexOf('--out') + 1] : null;
  final palette = argv.contains('--palette') ? argv[argv.indexOf('--palette') + 1] : null;
  if (palette != null) {
    final sep = url.contains('?') ? '&' : '?';
    url = url + sep + 'palette=' + palette;
  }
  final home = url.contains('academy');
  Directory? out;
  if (outDir != null) {
    out = Directory(outDir);
    await out.create(recursive: true);
  }

  // ---- the CTA inventory (LOCK LAW contract, Q1-Q4 of the sweep grill)
  final spots = <Spot>[
    ('nav-cta-hero', '.nav-cta-hero', 'cta:StartToday', 'lock', 'none'),
    ('tier-cta-1', '.tier-card:nth-child(1) .tier-cta', 'cta:Book', 'lock', 'pricing'),
    ('tier-cta-2', '.tier-card:nth-child(2) .tier-cta', 'cta:Book', 'lock', 'none'),
    ('story-pill', '.story-pill', 'story-pill', 'lock', 'stories'),
    ('cookie-accept', '.cookie-accept', 'cookie-button', 'lock', 'none'),
    // back-to-top is NOT in the inventory: chrome.js pins
    // data-visible='false' forever (VERIFY ADDENDUM 14 — the reference's
    // FAB never surfaces; the element stays mounted for keyboard/AT only,
    // so there is no hoverable pointer target to lock
    // after the cookie check the bar is dismissed — the reveal footer
    // (scroll to absolute bottom) is then hoverable
    ('footer-pill', '.site-footer-pill', 'cta:BookACallFooter', 'lock', 'bottom'),
    // negative contract: zones keep the riding orb, no glue
    ('tier-photo-nolock', '.tier-card:nth-child(1) .tier-photo', '', 'nolock', 'none'),
    ('faq-nolock', '.faq-question', '', 'nolock', 'none'),
    ('footer-link-nolock', '.site-footer-link', '', 'nolock', 'bottom'),
    ('footer-email-hidden', '.footer-email', '', 'hidden', 'bottom'),
  ];
  if (home) {
    spots
      ..clear()
      ..add(('waitlist-submit', '.waitlist-submit', 'waitlist-submit', 'lock', 'scroll'))
      ..add(('academy-back', '.academy-back', 'academy-back', 'lock', 'scroll'));
  }

  final client = await CdpClient.launch();
  var failures = 0;
  var checks = 0;
  final log = StringBuffer();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 832);
    await tab.navigateAndSettle(url, settleMs: 9000);
    var cookieDismissed = false;
    for (final s in spots) {
      final (name, sel, token, mode, prep) = s;
      final res = await park(tab, sel, prep);
      // the cookie bar overlays the page bottom (footer pill) — dismiss
      // it only AFTER its own lock has been audited
      if (name == 'cookie-accept' && !cookieDismissed) {
        await tab.evaluate('''
          (async () => {
            const btn = document.querySelector('[data-cookie-choice="reject"]');
            if (btn) btn.click();
            await new Promise((r) => setTimeout(r, 800));
            return true;
          })()
        ''', awaitPromise: true);
        cookieDismissed = true;
      }
      final b = res != null && res['belief'] != null ? (res['belief']! as Map).cast<String, Object?>() : null;
      var note = '';
      var ok = false;
      checks++;
      if (b == null) {
        note = 'NO BELIEF' + (res != null && res['err'] != null ? ' (' + res['err'].toString() + ')' : '');
      } else if (mode == 'hidden') {
        ok = b['sticking'] != true;
        note = ok ? 'stands down (hidden zone)' : 'stuck=' + (b['stickTarget'] ?? '?').toString();
      } else {
        final sticking = b['sticking'] == true;
        final target = (b['stickTarget'] ?? '').toString();
        if (mode == 'lock') {
          ok = sticking && (token.isEmpty || target.contains(token));
          if (!ok) note = sticking ? 'stuck WRONG target: ' + target : 'NOT LOCKED';
        } else {
          ok = !sticking;
          if (!ok) note = 'WRONGLY LOCKED on ' + target;
        }
      }
      // floors at the law position for locks: dot/idle/stuck vs surface
      var floorNote = '';
      if (ok && mode == 'lock' && b != null) {
        try {
          final surface = parseColor(b['surface'].toString());
          final state = parseColor(b['state'].toString());
          final alpha = double.parse(b['alpha'].toString());
          final dotR = contrast(state, surface);
          final idleR = contrast(mixAt(state, surface, 0.5), surface);
          final stuckR = contrast(mixAt(state, surface, alpha), surface);
          if (dotR < 3.0 || idleR < 2.0 || stuckR < 3.0) {
            ok = false;
            floorNote = ' FLOORS dot=' + dotR.toStringAsFixed(2) + ' idle=' + idleR.toStringAsFixed(2) + ' stuck=' + stuckR.toStringAsFixed(2);
          } else {
            floorNote = ' floors ' + dotR.toStringAsFixed(2) + '/' + idleR.toStringAsFixed(2) + '/' + stuckR.toStringAsFixed(2);
          }
        } catch (_) {
          floorNote = ' FLOOR-PARSE-FAIL';
          ok = false;
        }
      }
      final verdict = ok ? 'PASS' : 'FAIL';
      if (!ok) failures++;
      final line = (name).padRight(22) + ' ' + verdict.padRight(5) + ' ' + note + floorNote +
          (b != null ? '  surface=' + b['surface'].toString() + ' state=' + b['state'].toString() + ' a' + (b['alpha'] ?? '?').toString() : '');
      log.writeln(line);
      stdout.writeln(line);
      if (out != null && res != null) {
        final png = await tab.screenshot();
        await File(out.path + '/' + (home ? 'academy-' : 'home-') + name + (palette != null ? '-' + palette : '') + '.png').writeAsBytes(png);
      }
    }
    if (outDir != null) {
      await File(outDir + '/lock-log' + (palette != null ? '-' + palette : '') + '.txt').writeAsString(log.toString());
    }
    stdout.writeln(failures == 0 ? 'ALL LOCK CHECKS PASS (' + checks.toString() + ')' : 'LOCK FAILURES: ' + failures.toString() + '/' + checks.toString());
    await client.close();
    exit(failures == 0 ? 0 : 1);
  } catch (e) {
    stderr.writeln('lock probe error: ' + e.toString());
    await client.close();
    exit(1);
  }
}
