// Skeleton capture + diff — the content-free structural artifact.
//
// A skeleton is the diffable shape of a surface: per-element role, bounding
// box, z rank, font size and box sizing — never any text. It is the artefact
// two captures get diffed on; ADR-0001's observation-only spirit means no
// content strings ever enter it. Format tag `lens-skeleton/1` (renamed from
// the probe-runner's "probe" namespace — never "probe" in emitted identifiers).
//
// captureSkeleton walks the DOM in plain order (no elementsFromPoint) and reads
// getBoundingClientRect + getComputedStyle per element. diffSkeleton is a pure
// match-by-id compare that classifies deltas tree/pos/size/z with a 2px floor
// — the self-diff noise floor observed on lens-skeleton/1 captures.
library;

import 'package:appboxd/cdp.dart';

/// Capture the structural skeleton of [url] at [width]×[height].
///
/// Returns `{format, url, viewport, nodes, consoleErrors, certified}` where
/// each node is `{id, role, bbox:[x,y,w,h], z, fontSize, sizing}`. `certified`
/// is false when any console/page error fired during capture (lens doctrine:
/// a surface with a runtime bug fails the gate before any structural work).
Future<Map<String, dynamic>> captureSkeleton(
  String url, {
  int width = 390,
  int height = 844,
  int settleMs = 1500,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    final nodes = await tab.evaluate(_collectJs) as List;
    final nodeList = [
      for (final n in nodes) Map<String, dynamic>.from(n as Map),
    ];

    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    return {
      'format': 'lens-skeleton/1',
      'url': url,
      'viewport': [width, height],
      'nodes': nodeList,
      'consoleErrors': errors,
      'certified': errors.isEmpty,
    };
  } finally {
    await client.close();
  }
}

/// Pure structural diff of two skeletons (match nodes by `id`).
///
/// Classifies deltas as `tree` (id added/removed), `pos` (bbox origin moved
/// >2px), `size` (bbox extent changed >2px) or `z` (z rank changed). When an
/// element both moved and resized only the dominant `size` signal is emitted.
/// `certified` is true iff `deltas` is empty.
Map<String, dynamic> diffSkeleton(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final na = {
    for (final n in (a['nodes'] as List)) (n as Map)['id'] as String: n,
  };
  final nb = {
    for (final n in (b['nodes'] as List)) (n as Map)['id'] as String: n,
  };

  final deltas = <Map<String, dynamic>>[];
  final ids = <String>{...na.keys, ...nb.keys};
  for (final id in ids) {
    final inA = na[id], inB = nb[id];
    if (inA == null) {
      deltas.add({'type': 'tree', 'op': 'added', 'id': id});
      continue;
    }
    if (inB == null) {
      deltas.add({'type': 'tree', 'op': 'removed', 'id': id});
      continue;
    }
    final ba = _bbox(inA);
    final bb = _bbox(inB);
    final dw = (ba[2] - bb[2]).abs();
    final dh = (ba[3] - bb[3]).abs();
    if (dw > 2 || dh > 2) {
      deltas.add({
        'type': 'size',
        'id': id,
        'from': [ba[2], ba[3]],
        'to': [bb[2], bb[3]],
      });
    } else if ((ba[0] - bb[0]).abs() > 2 || (ba[1] - bb[1]).abs() > 2) {
      deltas.add({
        'type': 'pos',
        'id': id,
        'from': [ba[0], ba[1]],
        'to': [bb[0], bb[1]],
      });
    }
    if ((inA['z'] as num) != (inB['z'] as num)) {
      deltas.add({'type': 'z', 'id': id, 'from': inA['z'], 'to': inB['z']});
    }
  }

  return {'certified': deltas.isEmpty, 'deltas': deltas};
}

List<double> _bbox(Map node) =>
    (node['bbox'] as List).map((v) => (v as num).toDouble()).toList();

// Walks every element in plain DOM order, keeping only visible (non-zero-area)
// ones. Per element it reads the border-box rect and the computed style, infers
// an ARIA-ish role (explicit role attr → landmark/tag fallback) and assigns a
// stable content-free id (`#id` when present, else a structural nth-of-type
// path). No text content is ever read.
const String _collectJs = '''
(function () {
  var roleMap = {
    HEADER:'banner', NAV:'navigation', MAIN:'main', FOOTER:'contentinfo',
    ASIDE:'complementary', SECTION:'region', ARTICLE:'article', FORM:'form',
    BUTTON:'button', A:'link', IMG:'image', INPUT:'textbox',
    UL:'list', OL:'list', LI:'listitem',
    H1:'heading', H2:'heading', H3:'heading', H4:'heading', H5:'heading', H6:'heading',
    P:'paragraph', SPAN:'inline', DIV:'generic'
  };
  function roleOf(el) {
    var r = el.getAttribute('role');
    if (r) return r;
    return roleMap[el.tagName] || el.tagName.toLowerCase();
  }
  function idOf(el) {
    if (el.id) return '#' + el.id;
    var parts = [];
    var cur = el;
    while (cur && cur.nodeType === 1) {
      var parent = cur.parentElement;
      var seg = cur.tagName.toLowerCase();
      if (parent) {
        var same = 0;
        for (var i = 0; i < parent.children.length; i++) {
          if (parent.children[i].tagName === cur.tagName) same++;
          if (parent.children[i] === cur) { seg = seg + ':nth-of-type(' + same + ')'; break; }
        }
      }
      parts.unshift(seg);
      cur = parent;
    }
    return parts.join('>');
  }
  var out = [];
  var all = document.querySelectorAll('*');
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    var rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) continue;
    var cs = getComputedStyle(el);
    var zi = cs.zIndex;
    out.push({
      id: idOf(el),
      role: roleOf(el),
      bbox: [Math.round(rect.left), Math.round(rect.top),
             Math.round(rect.width), Math.round(rect.height)],
      z: zi === 'auto' ? 0 : (parseInt(zi, 10) || 0),
      fontSize: Math.round(parseFloat(cs.fontSize)),
      sizing: cs.display + '/' + cs.position
    });
  }
  return out;
})()
''';
