// Interaction-state capture — before/after screenshots around an input action.
//
// For each trigger captureStates screenshots the surface, dispatches the action
// (click at box-centre / hover via mouseMoved / focus via .focus()), settles,
// screenshots again, reads any active WAAPI transition, and pixelDiffs the two
// shots. `changed:false` is an observation, not a failure; `certified` rides on
// console/page errors only (lens doctrine).
//
// NOTE: the plan (§5.3) wanted a thin `CdpSession.hover(x,y)` added next to
// `click()` in cdp.dart. The task constraint forbids editing cdp.dart, so the
// `Input.dispatchMouseEvent` (type `mouseMoved`) dispatch is inlined here via
// `tab.send(...)`. Functionally identical — three lines, same shape as click().
library;

import 'dart:async';
import 'dart:convert';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/lens/pixels.dart';

/// One interaction to drive: query [selector], perform [action].
/// [action] is `'click'`, `'hover'` or `'focus'`.
class StateTrigger {
  const StateTrigger(this.selector, this.action);
  final String selector;
  final String action;
}

/// Capture before/after interaction states for [url].
///
/// Returns `{url, states, certified}` where each state is
/// `{selector, action, before, after, changed, diffPixels, transition,
/// consoleErrors}`. `before`/`after` are FNV-1a hashes of the PNG bytes (a
/// content-free identity, not the image itself). `transition` is the WAAPI
/// summary map when an animation is active right after the action, else null.
Future<Map<String, dynamic>> captureStates(
  String url, {
  required List<StateTrigger> triggers,
  int width = 390,
  int height = 844,
  int settleMs = 1500,
  int settleAfterMs = 600,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    final states = <Map<String, dynamic>>[];
    for (final t in triggers) {
      tab.clearErrors();
      final beforePng = await tab.screenshot();

      final center = await _boxCenter(tab, t.selector);
      if (center == null) {
        states.add({
          'selector': t.selector,
          'action': t.action,
          'before': _hash(beforePng),
          'after': _hash(beforePng),
          'changed': false,
          'diffPixels': 0,
          'transition': null,
          'consoleErrors': [...tab.consoleErrors],
          'error': 'element not found',
        });
        continue;
      }

      await _dispatch(tab, t, center);
      await Future.delayed(Duration(milliseconds: settleAfterMs));
      final transition = await _readAnimations(tab);
      final afterPng = await tab.screenshot();

      final diff = pixelDiff(decodePng(beforePng), decodePng(afterPng));
      states.add({
        'selector': t.selector,
        'action': t.action,
        'before': _hash(beforePng),
        'after': _hash(afterPng),
        'changed': diff.diffPixels > 0,
        'diffPixels': diff.diffPixels,
        'transition': transition,
        'consoleErrors': [...tab.consoleErrors],
      });
    }

    final anyErrors = states.any(
      (s) => (s['consoleErrors'] as List).isNotEmpty,
    );
    return {'url': url, 'states': states, 'certified': !anyErrors};
  } finally {
    await client.close();
  }
}

// ── helpers ────────────────────────────────────────────────────────

Future<List<double>?> _boxCenter(CdpSession tab, String selector) async {
  final r = await tab.evaluate(
    '(function(){var el=document.querySelector(${jsonEncode(selector)});'
    'if(!el)return null;var r=el.getBoundingClientRect();'
    'return [r.x+r.width/2, r.y+r.height/2];})()',
  );
  if (r == null) return null;
  return (r as List).map((v) => (v as num).toDouble()).toList();
}

Future<void> _dispatch(
  CdpSession tab,
  StateTrigger t,
  List<double> center,
) async {
  final cx = center[0].round();
  final cy = center[1].round();
  switch (t.action) {
    case 'click':
      await tab.click(cx, cy);
      break;
    case 'hover':
      // Inlined CdpSession.hover (see module note) — mouseMoved over the
      // element's centre applies :hover in headless Chrome.
      await tab.send('Input.dispatchMouseEvent', {
        'type': 'mouseMoved',
        'x': cx.toDouble(),
        'y': cy.toDouble(),
      });
      break;
    case 'focus':
      await tab.evaluate(
        'document.querySelector(${jsonEncode(t.selector)}).focus()',
      );
      break;
    default:
      throw ArgumentError("unknown action: '${t.action}'");
  }
}

/// WAAPI read right after the action + settle: a one-map summary of the first
/// active animation, or null when nothing is running. Self-contained (Task 4's
/// WAAPI helper lives outside lens/ and is not depended on here).
Future<Map<String, dynamic>?> _readAnimations(CdpSession tab) async {
  final r = await tab.evaluate(
    '(function(){var a=(document.getAnimations?document.getAnimations():[]);'
    'if(!a.length)return null;var f=a[0];'
    'return {count:a.length,'
    'name:f.animationName||f.transitionProperty||null,'
    'playState:f.playState};})()',
  );
  if (r == null) return null;
  return Map<String, dynamic>.from(r as Map);
}

/// FNV-1a 64-bit of the PNG bytes → hex. Kept positive (63-bit mask) so Dart's
/// signed int never yields a leading '-'. A content-free identity for before/after.
String _hash(List<int> bytes) {
  // kimitail: 63-bit FNV over full bytes — cheap, deterministic, no deps.
  // Upgrade to crypto digest if collision sensitivity ever matters.
  const mask = 0x7FFFFFFFFFFFFFFF;
  var h = 0x84222325 ^ 0xcbf29ce4; // FNV offset basis (kept positive)
  for (final b in bytes) {
    h = (h ^ b) & mask;
    h = (h * 0x100000001b3) & mask;
  }
  return h.toRadixString(16);
}
