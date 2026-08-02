// generate_view — Dart port of tools/vendor/generate_view/generate_view.py.
//
// Composition spec → Flutter view Dart code. NO LLM, deterministic: each design
// node → a primitive/widget, static text straight from the spec, dynamic slots
// bound to the viewModel/Session via a documented design-field → data_model map.
//
// Home → bespoke dashboard composites; every other screen → generic translation.
// Pure Dart (dart:convert, dart:io, package:path only).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:appboxd/transform_tokens.dart';
import 'package:path/path.dart' as p;

/// A composition node (or style/props map).
typedef Node = Map<String, dynamic>;

/// A generation gate failed (legibility / content-parity / render-coverage) —
/// mirrors Python's SystemExit, surfaced as generateView → return 1.
class GateFailure implements Exception {
  final String message;
  GateFailure(this.message);
  @override
  String toString() => message;
}

// ──────────── node accessors ────────────

List<Node> kidsOf(Node n) {
  final c = n['children'];
  return c is List ? c.cast<Node>() : <Node>[];
}

List<String> classesOf(Node n) {
  final c = n['class'];
  return c is List ? c.cast<String>() : <String>[];
}

Node styleOf(Node n) {
  final s = n['style'];
  return s is Node ? s : <String, dynamic>{};
}

Node propsOf(Node n) {
  final s = n['props'];
  return s is Node ? s : <String, dynamic>{};
}

String? strGet(Node m, String k) {
  final v = m[k];
  return v is String ? v : null;
}

// ──────────── SHA-1 (pure Dart — no crypto package available) ────────────

int _rotl(int v, int n) => ((v << n) | (v >>> (32 - n))) & 0xffffffff;

String _hex32(int v) => v.toRadixString(16).padLeft(8, '0');

String _sha1Hex(String input) {
  final bytes = utf8.encode(input);
  final origLen = bytes.length;
  final msg = List<int>.from(bytes);
  msg.add(0x80);
  while (msg.length % 64 != 56) {
    msg.add(0);
  }
  final bitLen = origLen * 8;
  for (int i = 7; i >= 0; i--) {
    msg.add((bitLen >> (i * 8)) & 0xff);
  }
  int h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476,
      h4 = 0xC3D2E1F0;
  for (int chunk = 0; chunk < msg.length; chunk += 64) {
    final w = List<int>.filled(80, 0);
    for (int i = 0; i < 16; i++) {
      w[i] = (msg[chunk + i * 4] << 24) |
          (msg[chunk + i * 4 + 1] << 16) |
          (msg[chunk + i * 4 + 2] << 8) |
          (msg[chunk + i * 4 + 3]);
    }
    for (int i = 16; i < 80; i++) {
      w[i] = _rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    int a = h0, b = h1, c = h2, d = h3, e = h4;
    for (int i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((b ^ 0xffffffff) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (_rotl(a, 5) + f + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = _rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
  }
  return _hex32(h0) + _hex32(h1) + _hex32(h2) + _hex32(h3) + _hex32(h4);
}

/// `svg_<sha1[:10]>` — content-hash asset id (machine-independent, golden-safe).
String svgId(String svg) => 'svg_${_sha1Hex(svg).substring(0, 10)}';

// ──────────── pure leaf helpers ────────────

/// Strip "px" / bare number → double, else null.
double? px(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : '$v';
  if (s.isEmpty) return null;
  final m = RegExp(r'^(-?[\d.]+)px$').firstMatch(s) ??
      RegExp(r'^(-?[\d.]+)$').firstMatch(s);
  return m != null ? double.parse(m.group(1)!) : null;
}

/// A bare numeric literal: integral floats drop the trailing ".0".
String numFmt(num x) =>
    x == x.truncateToDouble() ? '${x.toInt()}' : '$x';

String? weight(dynamic v) {
  if (v == null) return null;
  final s = (v is String ? v : '$v').trim();
  if (s.isEmpty) return null;
  if (s == 'bold' || s == '700') return 'FontWeight.w700';
  if (const {'600', '500', '800', '900', '400', '300'}.contains(s)) {
    return 'FontWeight.w$s';
  }
  return null;
}

/// A Python str → a Dart single-quoted string literal with escapes.
String dartStr(String s) {
  s = s.replaceAll('\\', '\\\\');
  if (s.contains("'") && !s.contains('"')) {
    return '"${s.replaceAll(r'$', r'\$')}"';
  }
  return "'${s.replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
}

/// Seed literal quoting (single-quote only, no $ escaping — design seed values).
String dartStrSeed(dynamic s) {
  final t = (s is String ? s : '$s')
      .replaceAll('\\', '\\\\')
      .replaceAll("'", r"\'");
  return "'$t'";
}

String pascalCase(String s) {
  final parts = s
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty);
  return parts.map((w) => w[0].toUpperCase() + w.substring(1)).join();
}

String snakeCase(String s) {
  var t = s.replaceAll(RegExp(r'[\-\s]+'), '_');
  t = t.replaceAll(RegExp(r'^_+'), '').replaceAll(RegExp(r'_+$'), '');
  return t.toLowerCase();
}

/// Relative luminance of a #rrggbb hex (for contrast math).
double lum(String? hexcol) {
  final h = (hexcol ?? '').replaceAll('#', '');
  if (h.length != 6) return 1.0;
  final r = int.parse(h.substring(0, 2), radix: 16);
  final g = int.parse(h.substring(2, 4), radix: 16);
  final b = int.parse(h.substring(4, 6), radix: 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

/// WCAG relative-luminance contrast ratio between two #rrggbb hexes.
double wcagContrast(String h1, String h2) {
  double lin(String h) {
    h = h.replaceAll('#', '');
    final ch = <double>[];
    for (final i in [0, 2, 4]) {
      var x = int.parse(h.substring(i, i + 2), radix: 16) / 255;
      ch.add(x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble());
    }
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
  }

  final a = lin(h1);
  final b = lin(h2);
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

// ──────────── expression splitters ────────────

/// Split `s` on top-level `op` (&& / ||), ignoring operators inside (), [], {},
/// or string/template quotes. Returns [s] (single element, stripped) if no split.
List<String> splitTop(String s, String op) {
  final out = <String>[];
  var depth = 0;
  String? q;
  var i = 0;
  var last = 0;
  while (i < s.length) {
    final ch = s[i];
    if (q != null) {
      if (ch == q) q = null;
    } else if (ch == "'" || ch == '"' || ch == '`') {
      q = ch;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0 && s.substring(i, i + op.length) == op) {
      out.add(s.substring(last, i));
      i += op.length;
      last = i;
      continue;
    }
    i++;
  }
  out.add(s.substring(last));
  return out.length > 1
      ? out.map((p) => p.trim()).toList()
      : [s.trim()];
}

/// True iff the leading `(` matches the trailing `)` (whole expr parenthesised).
bool outerParens(String s) {
  if (!s.startsWith('(') || !s.endsWith(')')) return false;
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) return i == s.length - 1;
    }
  }
  return false;
}

/// `COND ? A : B` → (cond, a, b) at the TOP level, else null.
List<String>? splitTernary(String b) {
  var depth = 0;
  String? q;
  var qpos = -1;
  for (var i = 0; i < b.length; i++) {
    final ch = b[i];
    if (q != null) {
      if (ch == q) q = null;
    } else if (ch == "'" || ch == '"' || ch == '`') {
      q = ch;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0 && ch == '?' && qpos < 0) {
      qpos = i;
    }
  }
  if (qpos < 0) return null;
  depth = 0;
  q = null;
  for (var i = qpos + 1; i < b.length; i++) {
    final ch = b[i];
    if (q != null) {
      if (ch == q) q = null;
    } else if (ch == "'" || ch == '"' || ch == '`') {
      q = ch;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (depth == 0 && ch == ':') {
      return [
        b.substring(0, qpos).trim(),
        b.substring(qpos + 1, i).trim(),
        b.substring(i + 1).trim(),
      ];
    }
  }
  return null;
}

// ──────────── default binding / token maps (legacy floor) ────────────

const Map<String, String> bindDefault = {
  'w.name': 's.title',
  'bigVal': 's.metric',
  'bigUnit': 's.unit',
  'w.notes': 's.note ?? ""',
  'w.streak': 's.streak',
  'w.target': 's.metric',
  'meta.label': 's.type',
};

const Map<String, String> hex2tokDefault = {
  '#1A1714': 'AppTokens.ink',
  '#3A3530': 'AppTokens.ink2',
  '#6E6760': 'AppTokens.ink3',
  '#A39A8E': 'AppTokens.ink4',
  '#F5F0E8': 'AppTokens.bone',
  '#DDD3C0': 'AppTokens.bone3',
  '#FBF8F2': 'AppTokens.paper',
  '#D2522B': 'AppTokens.accent',
  '#B8431F': 'AppTokens.accent2',
  '#D8CFBE': 'AppTokens.rule',
};

// ──────────── render-fidelity / icon / field constants ────────────

const Map<String, String> primCanonical = {
  'AdaptiveButton': 'action.button',
  'AdaptiveIconButton': 'action.icon-button',
  'AdaptiveTextField': 'input.text-field',
  'svg': 'display.media',
};

const List<String> nativePrimPrefixes = [
  'AdaptiveButton(',
  'AdaptiveIconButton(',
  'AdaptiveAuthButton(',
  'AdaptiveSwitch(',
  'AdaptiveSlider(',
  'AdaptiveChip(',
  'AdaptiveCard(',
];

const String inkHex = '#141414';
const double legibleMin = 4.5;

const Map<String, List<String>> iconMap = {
  'play': ["KitGlyphs.lucide('play')", 'play.fill'],
  'pause': ["KitGlyphs.lucide('pause')", 'pause.fill'],
  'reset': ["KitGlyphs.lucide('refresh-cw')", 'arrow.clockwise'],
  'back': ["KitGlyphs.lucide('chevron-left')", 'chevron.left'],
  'chevron-left': ["KitGlyphs.lucide('chevron-left')", 'chevron.left'],
  'chevron-right': ["KitGlyphs.lucide('chevron-right')", 'chevron.right'],
  'chevron': ["KitGlyphs.lucide('chevron-right')", 'chevron.right'],
  'edit': ["KitGlyphs.lucide('pencil')", 'pencil'],
  'check': ["KitGlyphs.lucide('check')", 'checkmark'],
  'sound': ["KitGlyphs.lucide('volume-2')", 'speaker.wave.2.fill'],
  'close': ["KitGlyphs.lucide('x')", 'xmark'],
  'plus': ["KitGlyphs.lucide('plus')", 'plus'],
};

const List<String> defaultIcon = ["KitGlyphs.lucide('circle')", 'circle'];

const List<String> inlineUnderline = ['u', 'a'];

const Set<String> selfPad = {
  'AdaptiveButton',
  'AdaptiveCard',
  'AdaptiveTextField',
  'IconButton',
  'Pip',
};

const Set<String> bespokeBoxClasses = {'auth-divider', 'splash-bottom'};

const Set<String> nativePrims = {'AdaptiveButton', 'IconButton', 'Segmented'};

const List<String> boxKeywords = ['auto', 'inherit', 'initial', 'normal'];

const double chPx = 7.0;

const Map<String, String> seedDefaultMap = {
  'name': 'title',
  'target': 'metric',
  'notes': 'note',
  'last': 'occurredOn',
};

const List<String> sessionFields = [
  'id',
  'title',
  'type',
  'metric',
  'unit',
  'note',
  'streak',
  'occurredOn',
];

const Map<String, Map<String, String?>> authFieldTypes = {
  'email': {
    'ctl': 'emailController',
    'kt': 'TextInputType.emailAddress',
    're': r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    'err': 'Enter a valid email',
  },
  'tel': {
    'ctl': 'phoneController',
    'kt': 'TextInputType.phone',
    're': r'^\+?[\d\s\-()]{7,}$',
    'err': 'Enter a valid phone number',
  },
  'password': {
    'ctl': 'passwordController',
    'kt': 'TextInputType.visiblePassword',
    're': r'^.{8,}$',
    'err': 'At least 8 characters',
  },
  'text': {
    'ctl': 'inputController',
    'kt': 'TextInputType.text',
    're': null,
    'err': null,
  },
};

final Map<String, String> textFieldKt = {
  for (final t in authFieldTypes.keys) t: authFieldTypes[t]!['kt']!,
};

final RegExp providerRe = RegExp(r'\b(google|apple)\b');

final RegExp overlayClassRe = RegExp(
    r'(^|[-_ ])(sheet|scrim|modal|backdrop|overlay|popover)([-_ ]|$)|^(fb-|create-|edit-|plan-|product-|cart-|checkout-)');

final RegExp degenBoxRe = RegExp(
    r'Container\(\s*decoration:\s*BoxDecoration\(\s*shape:\s*BoxShape\.circle\s*\)\s*\)|Container\(\s*\)');

const List<String> homeAssetsShellWidgets = ['RiseIn', 'StatsCarousel', 'DashedLine'];

const Set<String> homeAssetsExclude = {
  'HomeView', 'HomeViewModel', 'Widget', 'StatelessWidget', 'StatefulWidget',
  'Container', 'Column', 'Row', 'Padding', 'Center', 'SizedBox', 'Expanded',
  'Flexible', 'Stack', 'Positioned', 'Text', 'Icon', 'GestureDetector',
  'AdaptiveScaffold', 'AdaptiveRefresh', 'AdaptiveCard', 'AdaptiveButton',
  'AdaptiveSegmented', 'AdaptiveChip', 'AdaptiveIconButton',
  'AdaptiveButtonVariant', 'AdaptiveTextField', 'AdaptiveAuthButton',
  'AnnotatedRegion', 'SystemUiOverlayStyle', 'ListView', 'BoxDecoration',
  'BorderRadius', 'BorderAll', 'Border', 'EdgeInsets', 'MainAxisAlignment',
  'CrossAxisAlignment', 'MainAxisSize', 'Alignment', 'Offset', 'TextStyle',
  'FontWeight', 'Brightness', 'Colors', 'HitTestBehavior', 'ScrollPhysics',
  'AlwaysScrollableScrollPhysics', 'StackedView', 'BaseViewModel', 'Session',
  'Navigator', 'Material', 'InkWell', 'Tooltip', 'Hero', 'DefaultTextStyle',
  'Color', 'ColorSwatch', 'MaterialAccentColor', 'MaterialColor',
};

// ──────────── templates: HEAD / TAIL / GENERIC_HEAD ────────────

const String headTpl = '''// AUTO-GENERATED by flutter_crew generate_view.py from the design composition
// spec (capture_design.py). Do NOT hand-edit — regenerate. Graded against the
// DESIGN by design_gate, never against the hand-authored view.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemUiOverlayStyle (reactive status bar)
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:stacked/stacked.dart';

import '../app_tokens.dart';
import '../domain/ports/session_repository.dart';
import '../ui/primitives.dart' hide RiseIn; // home keeps its own RiseIn (home_assets)
import 'home_assets.dart';
import 'home_viewmodel.dart';

class HomeView extends StackedView<HomeViewModel> {
  const HomeView({super.key});

  @override
  Widget builder(BuildContext context, HomeViewModel viewModel, Widget? child) {
    if (viewModel.isBusy && !viewModel.dataReady) {
      // The design has no loading view — show the paper background (continuous with
      // splash→home), NOT a bare centered spinner. The session fetch is sub-second and
      // the splash's own progress bar already carried the "loading" signal.
      return const AdaptiveScaffold(body: SizedBox.shrink());
    }
    if (viewModel.hasError) {
      // TWO affordances, deliberately: the pull gesture is NOT discoverable on an
      // error screen, so an explicit button has to carry the retry too. And the
      // child must be SCROLLABLE — RefreshIndicator can only detect a pull over a
      // scrollable, so the bare Center() this used to be silently defeated it.
      return AdaptiveScaffold(
        body: AdaptiveRefresh(
          onRefresh: viewModel.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 120, 20, 32),
            children: [
              // A HUMAN message — never the raw error object (the bad-state leak).
              Text('Could not load your sessions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTokens.ink3, fontSize: 15)),
              const SizedBox(height: 16),
              Center(
                child: AdaptiveButton(
                    label: 'Try again', onPressed: viewModel.refresh),
              ),
            ],
          ),
        ),
      );
    }
    final sessions = viewModel.filtered;
    // Light paper surface → DARK status-bar icons, declared HERE (not just globally) so
    // returning from a dark screen (Detail) reactively restores it (Flutter #54029).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light),
      child: AdaptiveScaffold(
        body: AdaptiveRefresh(
          onRefresh: viewModel.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _header(viewModel),
              const SizedBox(height: 20),
              _statsDeck(viewModel),
              const SizedBox(height: 22),
              _filterRow(viewModel),
              const SizedBox(height: 16),
              for (var i = 0; i < sessions.length; i++)
                RiseIn(delayMs: 70 * i, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _sessionCard(sessions[i]))),
              // The empty state already scrolled correctly (this ListView +
              // AlwaysScrollableScrollPhysics under AdaptiveRefresh) — it only
              // lacked the explicit retry affordance, so only that is added.
              if (sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Text('No sessions yet.', style: TextStyle(color: AppTokens.ink3)),
                      const SizedBox(height: 16),
                      AdaptiveButton(label: 'Refresh', onPressed: viewModel.refresh),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
''';

const String tailTpl = '''
  /// Relative "Last" label from the date (design's `last`): today / Nd / Nw.
  String _lastLabel(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'today';
    if (days < 7) return '\$days d';
    return '\${(days / 7).floor()}w';
  }

  @override
  HomeViewModel viewModelBuilder(BuildContext context) => HomeViewModel();
}
''';

const String fmtSecHelper = '''

/// Formats a seconds count as MM:SS (the design's `fmtSec`). Emitted only when a
/// kept bind uses it (e.g. the countdown readout's start value).
String fmtSec(int s) {
  if (s < 0) s = 0;
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final c = (s % 60).toString().padLeft(2, '0');
  return '\$m:\$c';
}
''';

String genericHead({
  required String imports,
  required String name,
  required String body,
  required String ready,
  required String busyGate,
  required String scaffoldBg,
  required String ctorArgs,
  required String fields,
  required String modelLocal,
  required String vmArgs,
  required String overlayOpen,
  required String overlayClose,
}) {
  return '''// AUTO-GENERATED by flutter_crew generate_view.py from the design composition
// spec (capture_design.py). Do NOT hand-edit — regenerate. Graded against the
// DESIGN by design_gate, never against the hand-authored view.
$imports

class ${name}View extends StackedView<${name}ViewModel> {
  const ${name}View({super.key$ctorArgs});
$fields
  @override
  Widget builder(BuildContext context, ${name}ViewModel viewModel, Widget? child) {
$busyGate$modelLocal    return ${overlayOpen}AdaptiveScaffold($scaffoldBg body: $body)$overlayClose;
  }
$ready
  @override
  ${name}ViewModel viewModelBuilder(BuildContext context) => ${name}ViewModel($vmArgs);
}
''';
}

// ──────────── design_to_glass (best-effort; glass_entrance.py not in ported set) ────────────
// kimitail: maps a captured rise (durMs/curve/dy) to a SwiftUI spring + entrance
// params heuristically. Only reached when spec.riseDurMs is set; inert otherwise.
Map<String, dynamic> designToGlass(Map<String, dynamic> spec) {
  final durMs = (spec['durMs'] as num?)?.toDouble() ?? 300;
  final dy = (spec['dy'] as num?)?.toDouble() ?? 0;
  final responseS = durMs / 1000;
  return {
    'response_s': responseS,
    'bounce': 0.0,
    'opacityFrom': 0.0,
    'scaleFrom': 0.96,
    'liftPx': dy,
  };
}

// ──────────── tree walkers ────────────

Iterable<Node> walk(Iterable<Node> nodes) sync* {
  for (final n in nodes) {
    yield n;
    yield* walk(kidsOf(n));
  }
}

Node? findNode(Iterable<Node> nodes, bool Function(Node) pred) {
  for (final n in walk(nodes)) {
    if (pred(n)) return n;
  }
  return null;
}

List<Node> statCards(Node spec) =>
    walk(treeOf(spec)).where((n) => classesOf(n).contains('stat-card')).toList();

Node? workoutCard(Node spec) =>
    findNode(treeOf(spec), (n) => classesOf(n).contains('workout-card'));

List<Node> treeOf(Node spec) {
  final t = spec['tree'];
  return t is List ? t.cast<Node>() : <Node>[];
}

// ──────────── pure box-model helpers ────────────

String mainAxis(Node style) {
  final j = style['justify-content']?.toString();
  switch (j) {
    case 'space-between':
      return 'spaceBetween';
    case 'center':
      return 'center';
    case 'flex-end':
      return 'end';
    case 'space-around':
      return 'spaceAround';
    default:
      return 'start';
  }
}

String crossAxis(Node style) {
  final a = style['align-items']?.toString();
  switch (a) {
    case 'center':
      return 'center';
    case 'flex-end':
      return 'end';
    case 'stretch':
      return 'stretch';
    case 'baseline':
      return 'baseline';
    default:
      return 'start';
  }
}

String? gapBox(Node style, bool horizontal) {
  final g = px(style['gap']);
  if (g == null) return null;
  return "SizedBox(${horizontal ? 'width' : 'height'}: ${numFmt(g)})";
}

String adaptiveGap(String sb) {
  final m = RegExp(r'height:\s*([0-9.]+)').firstMatch(sb);
  final n = m != null ? double.parse(m.group(1)!) : 0.0;
  return 'const AdaptiveGap(${numFmt(n)})';
}

double oneEdge(String tok) {
  if (boxKeywords.contains(tok)) return 0.0;
  final v = px(tok);
  return v ?? 0.0;
}

List<double>? edges(Node style, String prop) {
  var top = 0.0, right = 0.0, bottom = 0.0, left = 0.0;
  var any = false;
  final sh = style[prop]?.toString().split(RegExp(r'\s+')) ?? <String>[];
  final cleaned = sh.where((s) => s.isNotEmpty).toList();
  if (cleaned.isNotEmpty) {
    var v = cleaned.map(oneEdge).toList();
    if (v.length == 1) {
      v = [v[0], v[0], v[0], v[0]];
    } else if (v.length == 2) {
      v = [v[0], v[1], v[0], v[1]];
    } else if (v.length == 3) {
      v = [v[0], v[1], v[2], v[1]];
    }
    top = v[0];
    right = v[1];
    bottom = v[2];
    left = v[3];
    any = true;
  }
  for (final side in ['top', 'right', 'bottom', 'left']) {
    final lv = style['$prop-$side'];
    if (lv != null) {
      final val = oneEdge(lv.toString());
      if (side == 'top') top = val;
      if (side == 'right') right = val;
      if (side == 'bottom') bottom = val;
      if (side == 'left') left = val;
      any = true;
    }
  }
  if (!any) return null;
  return [top, right, bottom, left];
}

String? edgeInsets(List<double>? e) {
  if (e == null) return null;
  var t = e[0] < 0 ? 0.0 : e[0];
  var r = e[1] < 0 ? 0.0 : e[1];
  var b = e[2] < 0 ? 0.0 : e[2];
  var l = e[3] < 0 ? 0.0 : e[3];
  if (t == 0 && r == 0 && b == 0 && l == 0) return null;
  if (t == b && r == l) {
    final a = <String>[];
    if (t != 0) a.add('vertical: ${numFmt(t)}');
    if (r != 0) a.add('horizontal: ${numFmt(r)}');
    return 'EdgeInsets.symmetric(${a.join(', ')})';
  }
  return 'EdgeInsets.fromLTRB(${numFmt(l)}, ${numFmt(t)}, ${numFmt(r)}, ${numFmt(b)})';
}

bool flexGrows(Node style) {
  final f = style['flex'] ?? style['flex-grow'];
  final s = f?.toString();
  final first = (s == null || s.isEmpty) ? '' : s.split(RegExp(r'\s+'))[0];
  return first != '' && first != '0' && first != 'none' && first != 'initial';
}

bool scrolls(Node style) =>
    (style['overflow-y']?.toString() ?? style['overflow']?.toString() ?? '') ==
        'auto' ||
    (style['overflow-y']?.toString() ?? style['overflow']?.toString() ?? '') ==
        'scroll';

// ──────────── node predicates ────────────

bool hasRealText(Node n) {
  if (strGet(n, 'text') != null && n['text'].toString().trim().isNotEmpty) {
    return true;
  }
  return kidsOf(n).any(hasRealText);
}

bool isIconButton(Node n) =>
    n['tag'] == 'button' &&
    kidsOf(n).any((c) => c['tag'] == 'Icon') &&
    !hasRealText(n);

Node? findSvg(Node n) {
  for (final c in kidsOf(n)) {
    if (classesOf(c).contains('spinner')) continue;
    if (c['prim'] == 'svg') return c;
    final d = findSvg(c);
    if (d != null) return d;
  }
  return null;
}

bool modelBound(Node spec) =>
    walk(treeOf(spec)).any((n) => (bindsOf(n)).any((b) => RegExp(r'\bw\.').hasMatch(b)));

List<String> bindsOf(Node n) {
  final b = n['bind'];
  return b is List ? b.cast<String>() : <String>[];
}

String authField(Node spec) {
  for (final n in walk(treeOf(spec))) {
    if (n['prim']?.toString() != 'AdaptiveTextField') continue;
    final t = propsOf(n)['type']?.toString() ?? '';
    return authFieldTypes.containsKey(t) ? t : 'text';
  }
  return 'text';
}

Set<String> specProviders(Node spec) {
  final found = <String>{};
  for (final n in walk(treeOf(spec))) {
    final prim = n['prim']?.toString();
    if (prim != 'AdaptiveButton' && prim != 'AdaptiveAuthButton') continue;
    final cls = classesOf(n).join(' ');
    final m = providerRe.firstMatch(cls);
    if (m != null) found.add(m.group(1)!);
  }
  return found;
}

bool isOverlayRoot(Node n) {
  if (kidsOf(n).isEmpty) return false;
  return classesOf(n).any((c) => overlayClassRe.hasMatch(c));
}

String overlayGate(Node n) {
  final cls = classesOf(n).join(' ');
  if (cls.contains('fb-')) return 'viewModel.done';
  final m = RegExp(r'(create|edit|plan|product|cart|checkout)[-_]?sheet').firstMatch(cls);
  if (m != null) return 'viewModel.${m.group(1)}Open';
  return 'false';
}

List<String> overlayWrap(bool iconsLight) {
  return [
    "AnnotatedRegion<SystemUiOverlayStyle>(value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.${iconsLight ? 'light' : 'dark'}, statusBarBrightness: Brightness.${iconsLight ? 'dark' : 'light'}), child: ",
    ')',
  ];
}

double? maxWidthOf(Node style) {
  final mw = style['max-width'];
  if (mw == null) return null;
  final s = mw.toString().trim();
  var m = RegExp(r'^(\d+(?:\.\d+)?)ch$').firstMatch(s);
  if (m != null) return _round1(double.parse(m.group(1)!) * chPx);
  m = RegExp(r'^(\d+(?:\.\d+)?)px$').firstMatch(s);
  if (m != null) return double.parse(m.group(1)!);
  return null;
}

double _round1(double x) => (x * 10).roundToDouble() / 10;

// ──────────── seed → Session reconciliation ────────────

/// Design seed rows → a list of `Session(...)` Dart constructor-literal strings.
List<String> seedToSessionLiterals(List<dynamic> seedRows,
    {Map<String, String>? fieldMap}) {
  if (seedRows.isEmpty) return <String>[];
  // entityField ← seedKey; build rev (entityField → seedKey), explicit wins.
  // Mirrors Python exactly: rev is keyed on the RAW field_map keys (the camelCased
  // fmap the Python builds is never used for the lookup), so a field_map with
  // already-camelCase keys (occurredOn) resolves, matching Python's actual behavior.
  final rev = <String, String>{};
  if (fieldMap != null) {
    fieldMap.forEach((seedKey, entField) {
      rev.putIfAbsent(entField, () => seedKey);
    });
  }
  seedDefaultMap.forEach((seedKey, entField) {
    rev.putIfAbsent(entField, () => seedKey);
  });
  const anchor = AnchorDate(2025, 4, 18);
  final out = <String>[];
  for (final row in seedRows) {
    if (row is! Node) continue;
    final idKey = rev['id'] ?? 'id';
    final titleKey = rev['title'] ?? 'name';
    if (!row.containsKey(idKey) || !row.containsKey(titleKey)) continue;

    dynamic rawVal(String entField, [dynamic dflt]) {
      final sk = rev[entField] ?? entField;
      return row.containsKey(sk) ? row[sk] : dflt;
    }

    final args = <String, String>{
      'id': dartStrSeed(rawVal('id', '')),
      'title': dartStrSeed(rawVal('title', '')),
      'type': dartStrSeed(rawVal('type', '') ?? ''),
      'metric': '${(rawVal('metric', 0) ?? 0).toInt()}',
      'unit': dartStrSeed(rawVal('unit', '') ?? ''),
      'streak': '${(rawVal('streak', 0) ?? 0).toInt()}',
    };
    final note = rawVal('note');
    args['note'] = note != null ? dartStrSeed(note) : 'null';

    final last = (rawVal('occurredOn', '') ?? '').toString().trim().toLowerCase();
    var days = 0;
    if (last == 'yesterday') {
      days = 1;
    } else {
      final mt = RegExp(r'^(\d+)\s*([dw])').firstMatch(last);
      if (mt != null) {
        days = int.parse(mt.group(1)!) * (mt.group(2) == 'w' ? 7 : 1);
      }
    }
    final occurred = anchor.minusDays(days);
    args['occurredOn'] = "DateTime.parse('$occurred')";

    final body =
        sessionFields.where(args.containsKey).map((f) => '$f: ${args[f]}').join(', ');
    out.add('Session($body)');
  }
  return out;
}

/// A fixed ISO-date anchor (deterministic; matches blueprint._date_from_last).
class AnchorDate {
  final int year, month, day;
  const AnchorDate(this.year, this.month, this.day);
  String minusDays(int n) {
    final d = DateTime(year, month, day).subtract(Duration(days: n));
    return d.toIso8601String().substring(0, 10);
  }
}

// ──────────── VM templates (pure string emission) ────────────

String tplVmHomeBase(String name, String snake, [List<String>? seedRows]) {
  String filteredBody;
  String dataReady;
  if (seedRows == null || seedRows.isEmpty) {
    filteredBody = 'const []';
    dataReady = 'false';
  } else {
    final rows = seedRows.map((r) => '      $r,\n').join();
    filteredBody = '<Session>[\n$rows    ]';
    dataReady = 'true';
  }
  return '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name home VM base.
// Regenerated every run; do not hand-edit. ${name}ViewModel extends this and fills
// the real business logic (fetch sessions, filter by segment, derive initials).
// The stubs are honest defaults so the app compiles + shows empty state until wired.
import 'package:stacked/stacked.dart';

import '../domain/ports/session_repository.dart';

abstract class ${name}ViewModelBase extends BaseViewModel {
  // data-loading state. When the design declares seed rows, `filtered` returns them
  // (the seed is reachable on frame 1 — the design's workout cards render, not the
  // empty state). Override to drive from a repository fetch in a real backend build.
  bool get dataReady => $dataReady;
  List<Session> get filtered => $filteredBody;
  Future<void> refresh() async {}

  // profile — override to read from a profile repository.
  String get firstName => '';
  String get initials => '';

  // segmented filter — override with the design's categories + counts. segLabels is
  // emitted on the STUB (below), not here — the bespoke home_view references it at the
  // class level (HomeViewModel.segLabels), and Dart statics aren't inherited, so a
  // static on the base wouldn't reach HomeViewModel.segLabels.
  int get filter => 0;
  void setFilter(int i) {}
  int countFor(int seg) => 0;
}
''';
}

String tplVmHomeStub(String name, String snake) => '''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the stubbed home members), never this file once you add logic.
// @appbox-extension-point: presentation/${snake}_viewmodel
import '${snake}_viewmodel.gen.dart';

class ${name}ViewModel extends ${name}ViewModelBase {
  ${name}ViewModel();
  // The design's segment labels (a const — referenced at the class level by the view).
  // TODO(builder): replace with the design's category labels (CATEGORIES in data.jsx).
  static List<String> get segLabels => const [];
  // TODO(builder): wire the real logic — fetch sessions (filtered/refresh/dataReady),
  // read the profile (firstName/initials), drive the segment filter (filter/setFilter/
  // countFor). The base stubs return empty defaults until you do.
}
''';

String tplVmStub(String name, String snake) => '''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the countdown state machine), never this file once you add logic.
// @appbox-extension-point: presentation/${snake}_viewmodel
import '${snake}_viewmodel.gen.dart';

class ${name}ViewModel extends ${name}ViewModelBase {
  ${name}ViewModel(super.workout);
  // TODO(builder): override start/pause/reset or add screen actions here.
}
''';

String tplVmOverlaysBase(String name, String snake, List<String> flags) {
  if (flags.isEmpty) return '';
  final fields = flags.map((f) => '  bool _$f' 'Open = false;').join('\n');
  final getters = flags.map((f) => '  bool get ${f}Open => _$f' 'Open;').join('\n');
  final methods = flags
      .map((f) =>
          '  void open${_cap(f)}() { _$f' 'Open = true; notifyListeners(); }\n'
          '  void close${_cap(f)}() { _$f' 'Open = false; notifyListeners(); }')
      .join('\n');
  return '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name overlay-state
// base. Regenerated every run; do not hand-edit. ${name}ViewModel extends this.
// The `<flag>Open` bools drive the gated sheet/modal overlays the view emits
// (Option C: sheets/scrims as Visibility-gated Stack layers).
import 'package:stacked/stacked.dart';

abstract class ${name}ViewModelBase extends BaseViewModel {
$fields
$getters
$methods
}
''';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String tplVmOverlaysStub(String name, String snake) => '''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the overlay-state flags), never this file once you add logic.
// @appbox-extension-point: presentation/${snake}_viewmodel
import '${snake}_viewmodel.gen.dart';

class ${name}ViewModel extends ${name}ViewModelBase {
  ${name}ViewModel();
  // TODO(builder): add screen actions / data here. Overlay flags are on the base.
}
''';

String tplVmSplashBase(String name, String snake, String nextPascal,
    {bool smokeAutologin = true, String homeRoute = 'homeShellView'}) {
  final autologin = smokeAutologin
      ? '''
  static const _autoLoginEmail = String.fromEnvironment('SMOKE_AUTOLOGIN');
  static const _autoLoginPassword = String.fromEnvironment('SMOKE_PASSWORD');
'''
      : '';
  final autologinImport = smokeAutologin
      ? "import '../infrastructure/supabase_auth_service.dart';\n"
      : '';
  final autologinBranch = smokeAutologin
      ? '''
      if (_autoLoginEmail.isNotEmpty && _autoLoginPassword.isNotEmpty) {
        await locator<SupabaseAuthService>().signInWithPassword(
            email: _autoLoginEmail, password: _autoLoginPassword);
        await _navigationService.clearStackAndShow(Routes.$homeRoute);
        return;
      }'''
      : '';
  return '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name startup VM.
// Regenerated every run from the design SSOT (screenFlow + captured splash
// timing); do not hand-edit. ${name}ViewModel extends this and IS the hand-editable
// extension point.
import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import 'motion.dart';  // kSplashHoldMs — splash hold CAPTURED from the design (not a stub)
$autologinImport
/// Built by `flutter_crew` from breakdown `screenFlow` (authStage: splash →
/// $nextPascal). On ready, hold the designed splash then REPLACE (not push)
/// so back doesn't return to the splash. busy/error wrap is mandatory on async
/// (ADR-0003).
///
/// Smoke hook: when SMOKE_AUTOLOGIN (a --dart-define) is set, sign the seeded
/// user in and go straight to home — lets the smoke render real seeded data
/// headlessly. Compile-time const → tree-shaken out of normal builds.
abstract class ${name}ViewModelBase extends BaseViewModel {
  final _navigationService = locator<NavigationService>();$autologin

  Future<void> runStartupLogic() async {
    setError(null);
    setBusy(true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: kSplashHoldMs));$autologinBranch
      await _navigationService.replaceWith${nextPascal}View();
    } catch (e) {
      setError(e);
      await _navigationService.replaceWith${nextPascal}View();
    } finally {
      setBusy(false);
    }
  }
}
''';
}

String tplVmSplashStub(String name, String snake) => '''// FACTORY EXTENSION POINT — hand-edit freely; the factory regenerates ONLY the
// `.gen.dart` base (the splash startup state machine), never this file once you
// add logic. @appbox-extension-point: presentation/${snake}_viewmodel
import '${snake}_viewmodel.gen.dart';

class ${name}ViewModel extends ${name}ViewModelBase {
  // The base's runStartupLogic() holds the designed splash then routes to the
  // next authStage screen (splash→signin). Override it here to customise.
  // TODO(builder): override runStartupLogic() or add splash-specific actions.
}
''';

String tplVmAuth(String name, String snake,
    {List<String> oauth = const [],
    String fieldType = 'email',
    String homeRoute = 'homeShellView'}) {
  final ft = authFieldTypes[fieldType] ?? authFieldTypes['text']!;
  final ctl = ft['ctl']!;
  final gateRe = ft['re'];
  final gateErr = ft['err'];
  String gateBlock = '';
  String sendGuard = '';
  if (gateRe != null) {
    gateBlock = '''  static final RegExp _fieldRe = RegExp(r'$gateRe');
  bool formValid = false;
  /// Live validity — the design's submit CTA is disabled until this field
  /// passes (its disabled={!valid} gate). Lifted to a VM observable so the
  /// generated AdaptiveButton binds enabled: formValid. Derived from the
  /// field's DECLARED type ('$fieldType'), never a hardcoded literal.
  void onFieldChanged(String v) {
    final next = _fieldRe.hasMatch(v.trim());
    if (next != formValid) {
      formValid = next;
      notifyListeners();
    }
  }

''';
    sendGuard = '''    if (!_fieldRe.hasMatch(email)) {
      setError(${dartStr(gateErr ?? '')});
      return;
    }
''';
  }
  String goBody;
  String goDoc;
  if (oauth.isNotEmpty) {
    final cases = oauth
        .map((pr) => '        case \'$pr\':\n'
            '          await _auth.signInWith${_cap(pr)}();\n'
            '          break;\n')
        .join();
    final oauthConfigured = (['GOOGLE_SERVER_CLIENT_ID', 'APPLE_SERVICE_ID'])
        .map((d) => "const String.fromEnvironment('$d') != ''")
        .join(' || ');
    goBody = '''    setError(null);
    setBusy(true);
    try {
      const _oauthConfigured = $oauthConfigured;
      if (!_oauthConfigured) {
        // Preview mode (no OAuth defines) → run the design's mock intent:
        // the social button advances to Home. Visible, not silent.
        await _nav.clearStackAndShow(Routes.$homeRoute);
        return;
      }
      switch (provider) {
$cases        default:
          setError('\$provider sign-in is not configured.');
          return;
      }
      await _nav.clearStackAndShow(Routes.$homeRoute);
    } catch (e) {
      setError(e);
      // A HUMAN message — never the raw exception (the bad-state leak). The
      // object stays on setError for logging/debug; only this string is shown.
      locator<FeedbackService>().error('Could not sign you in. Please try again.');
    } finally {
      setBusy(false);
    }''';
    goDoc = '  /// Native provider sign-in (${oauth.join('/')}): obtains an '
        'idToken via\n  /// the platform plugin and exchanges it with Supabase, '
        'then clears the stack to\n  /// Home. UNCONFIGURED OAuth defines '
        '(preview) → advances to Home (the design\'s mock\n  /// intent); '
        'CONFIGURED → real OAuth, failures surface via FeedbackService.';
  } else {
    goBody =
        "    setError('\$provider sign-in needs OAuth setup (no provider buttons in the design).');";
    goDoc = '  /// Provider sign-in placeholder — the design declared no '
        "go('<provider>')\n  /// buttons.\n  /// ponytail: no-op notice; a design "
        'with Google/Apple buttons wires the real path.';
  }
  return '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name auth ViewModel.
// Regenerated every run from the design SSOT; do not hand-edit (auth logic is generated,
// not hand-authored — ADR-0013; no extension seam for auth screens).
import 'package:flutter/widgets.dart';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../infrastructure/supabase_auth_service.dart';
import '../ui/feedback_service.dart';

class ${name}ViewModel extends BaseViewModel {
  final SupabaseAuthService _auth = locator<SupabaseAuthService>();
  final NavigationService _nav = locator<NavigationService>();

  final TextEditingController $ctl = TextEditingController();

$gateBlock  /// The design's "Send code" CTA: emails a one-time code, then advances to the
  /// OTP screen (no deep link — the code is entered in-app).
  Future<void> sendCode() async {
    final email = $ctl.text.trim();
$sendGuard    setError(null);
    setBusy(true);
    try {
      await _auth.sendEmailOtp(email: email);
      await _nav.navigateToOtpView(email: email);
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

$goDoc
  Future<void> go(String provider) async {
$goBody
  }

  @override
  void dispose() {
    $ctl.dispose();
    super.dispose();
  }
}
''';
}

String tplVmWelcome(String name, String snake, {String homeRoute = 'homeShellView'}) =>
    '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name interstitial VM.
// Regenerated every run from the design SSOT; do not hand-edit.
import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../domain/ports/profile_repository.dart';

class ${name}ViewModel extends BaseViewModel {
  final _profiles = locator<ProfileRepository>();

  ${name}ViewModel() {
    _loadName();
    // Design pulse: hold the greeting, then advance to Home
    // (auth.jsx WelcomeView: setTimeout(onDone, 1400)).
    Timer(const Duration(milliseconds: 1400), _toHome);
  }

  /// Signed-in athlete's display name → the design's "Welcome, {name}." bind
  /// (auth.jsx WelcomeView `name` prop). Same profile Port Home's greeting reads;
  /// falls back to "Athlete" before the (cached, fast) profile resolves.
  String? _athleteName;

  String get firstName {
    final n = _athleteName?.trim() ?? '';
    return n.isEmpty ? 'Athlete' : n.split(RegExp(r'\\s+')).first;
  }

  Future<void> _loadName() async {
    try {
      final ps = await _profiles.all();
      if (ps.isNotEmpty) {
        _athleteName = ps.first.displayName;
        notifyListeners();
      }
    } catch (_) {/* greeting keeps its fallback */}
  }

  void _toHome() => locator<NavigationService>().clearStackAndShow(Routes.$homeRoute);
}
''';

String tplVmOtp(String name, String snake) => '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name OTP-verify
// ViewModel. Regenerated every run from the design SSOT; do not hand-edit.
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app/app.locator.dart';
import '../app/app.router.dart';
import '../infrastructure/supabase_auth_service.dart';

class ${name}ViewModel extends BaseViewModel {
  ${name}ViewModel(this.email);

  /// The address the one-time code was sent to (passed from the sign-in screen).
  final String email;

  final SupabaseAuthService _auth = locator<SupabaseAuthService>();
  final NavigationService _nav = locator<NavigationService>();

  /// Set when verifyOtp rejects the code → the boxes turn accent + the inline
  /// "that code didn't match" message shows. Cleared on the next attempt.
  bool codeError = false;

  /// Auto-called by the 6-box input once all digits are filled (design UX).
  Future<void> verify(String code) async {
    codeError = false;
    setError(null);
    setBusy(true);
    try {
      await _auth.verifyEmailOtp(email: email, token: code);
      await _nav.clearStackAndShow(Routes.welcomeView);
    } catch (e) {
      codeError = true;
      setBusy(false);
      notifyListeners();
      return;
    }
    setBusy(false);
  }

  /// Re-request a code (design's "Resend" affordance).
  Future<void> resend() async {
    setError(null);
    try {
      await _auth.sendEmailOtp(email: email);
    } catch (e) {
      setError(e);
    }
  }
}
''';

String tplViewOtp(String name, String snake) => '''// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name OTP-verify
// view. Targeted auth-flow template (functional 6-box code input the generic
// translator can't produce). Regenerated every run; do not hand-edit.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import '../app_tokens.dart';
import '../app/app.locator.dart';
import '../ui/primitives.dart';
import '${snake}_viewmodel.dart';

class ${name}View extends StackedView<${name}ViewModel> {
  const ${name}View({super.key, this.email = ''});

  final String email;

  @override
  Widget builder(BuildContext context, ${name}ViewModel viewModel, Widget? child) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: AdaptiveScaffold(
        backgroundColor: AppTokens.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 12, 26, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: AppTokens.ink,
                    onPressed: () => locator<NavigationService>().back(),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset('assets/svg/svg_ee30f39c9f.svg',
                          width: 64, height: 64),
                      const SizedBox(height: 22),
                      Text('VERIFY EMAIL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppTokens.accent)),
                      const SizedBox(height: 8),
                      Text('Enter your code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, color: AppTokens.ink)),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 14, color: AppTokens.ink3),
                          children: [
                            const TextSpan(text: 'We sent a 6-digit code to '),
                            TextSpan(
                                text: email.isEmpty ? 'your email' : email,
                                style: TextStyle(
                                    color: AppTokens.ink,
                                    fontWeight: FontWeight.w600)),
                            const TextSpan(text: '.'),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _OtpBoxes(
                          hasError: viewModel.codeError,
                          enabled: !viewModel.isBusy,
                          onCompleted: viewModel.verify),
                      const SizedBox(height: 14),
                      if (viewModel.codeError)
                        Text("That code didn't match. Try again.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppTokens.accent))
                      else if (viewModel.isBusy)
                        const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: AdaptiveProgress()),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: viewModel.isBusy ? null : viewModel.resend,
                        child: Text('Resend code',
                            style: TextStyle(fontSize: 13, color: AppTokens.ink3)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  ${name}ViewModel viewModelBuilder(BuildContext context) =>
      ${name}ViewModel(email);
}

/// Functional 6-box one-time-code field: each box holds one digit, auto-advances on
/// entry, steps back on delete, and fires [onCompleted] once all six are filled (the
/// design's auto-verify UX). The generic spec translator can't produce this.
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({
    required this.onCompleted,
    required this.hasError,
    required this.enabled,
  });

  final ValueChanged<String> onCompleted;
  final bool hasError;
  final bool enabled;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  late final List<TextEditingController> _c =
      List.generate(6, (_) => TextEditingController());
  late final List<FocusNode> _f = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    for (final n in _f) {
      n.dispose();
    }
    super.dispose();
  }

  void _onChanged(int i, String v) {
    if (v.isNotEmpty && i < 5) {
      _f[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _f[i - 1].requestFocus();
    }
    final code = _c.map((c) => c.text).join();
    if (code.length == 6) {
      FocusScope.of(context).unfocus();
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 6; i++)
          SizedBox(
            width: 46,
            height: 56,
            child: TextField(
              controller: _c[i],
              focusNode: _f[i],
              enabled: widget.enabled,
              autofocus: i == 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600, color: AppTokens.ink),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: AppTokens.paper,
                contentPadding: EdgeInsets.zero,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: widget.hasError ? AppTokens.accent : AppTokens.rule,
                      width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTokens.ink, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTokens.rule, width: 1.5),
                ),
              ),
              onChanged: (v) => _onChanged(i, v),
            ),
          ),
      ],
    );
  }
}
''';

/// A VM stub with no hand-written behavior → safe to upgrade to `extends …Base`.
bool stubIsDefault(String text) {
  if (!text.contains('@appbox-extension-point')) return false;
  final m = RegExp(r'class\s+\w+ViewModel\b.*?\{(.*)\}', dotAll: true).firstMatch(text);
  var inner = (m?.group(1) ?? '').trim();
  inner = inner.replaceAll(RegExp(r'//[^\n]*|/\*.*?\*/', dotAll: true), '').trim();
  return inner.isEmpty;
}

// ──────────── home_assets.dart symbol extraction (pure) ────────────

Map<String, dynamic> extractCallSites(String homeViewSrc) {
  final localClasses = RegExp(r'class\s+([A-Z][A-Za-z0-9]*)\b')
      .allMatches(homeViewSrc)
      .map((m) => m.group(1)!)
      .toSet();
  final sites = <String, Map<String, dynamic>>{};
  for (final m in RegExp(r'\b([A-Z][A-Za-z0-9]*)\s*\(').allMatches(homeViewSrc)) {
    final name = m.group(1)!;
    if (homeAssetsExclude.contains(name) || localClasses.contains(name)) continue;
    var depth = 1;
    var i = m.end;
    final named = <String>[];
    var hasPos = false;
    while (i < homeViewSrc.length && depth > 0) {
      final c = homeViewSrc[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (depth == 1 && c != ' ' && c != '\t' && c != '\n' && c != ',') {
        final km = RegExp(r'^([a-z][A-Za-z0-9]*)\s*:').firstMatch(homeViewSrc.substring(i));
        if (km != null) {
          named.add(km.group(1)!);
          i += km.end;
          continue;
        }
        hasPos = true;
      }
      i++;
    }
    final entry = sites.putIfAbsent(name, () => {'named_params': <String>[], 'has_positional': false});
    for (final p in named) {
      if (!(entry['named_params'] as List).contains(p)) {
        (entry['named_params'] as List).add(p);
      }
    }
    if (hasPos) entry['has_positional'] = true;
  }
  return sites;
}

Map<String, dynamic> homeAssetsSymbols(String homeViewSrc) {
  final sites = extractCallSites(homeViewSrc);
  final classes = sites.entries
      .map((e) => <String, dynamic>{
            'name': e.key,
            'named_params': e.value['named_params'],
            'has_positional': e.value['has_positional'],
          })
      .toList();
  final names = classes.map((c) => c['name'] as String).toSet();
  for (final w in homeAssetsShellWidgets) {
    if (RegExp('\\b$w\\s*\\(').hasMatch(homeViewSrc) && !names.contains(w)) {
      classes.add(<String, dynamic>{
        'name': w,
        'named_params': <String>[],
        'has_positional': false,
      });
    }
  }
  final consts = <String>[];
  final seenK = <String>{};
  for (final m in RegExp(r'\b(k[A-Z][A-Za-z0-9]*)\b').allMatches(homeViewSrc)) {
    final n = m.group(1)!;
    if (!seenK.contains(n) &&
        !const {'kRiseMs', 'kRiseCurve', 'kRiseDy', 'kSplashFillMs', 'kSplashHoldMs'}
            .contains(n)) {
      seenK.add(n);
      consts.add(n);
    }
  }
  return {'classes': classes, 'consts': consts};
}

String tplHomeAssetsStub(Map<String, dynamic> symbols) {
  final clsDecls = <String>[];
  for (final c in (symbols['classes'] as List).cast<Map<String, dynamic>>()) {
    final name = c['name'] as String;
    final params = (c['named_params'] as List?)?.cast<String>() ?? <String>[];
    if (params.isNotEmpty) {
      final fields = params.map((p) => '  final dynamic $p;').join('\n');
      final ctorParams = params.map((p) => 'this.$p').join(', ');
      clsDecls.add('class $name extends StatelessWidget {\n'
          '  const $name({super.key, $ctorParams});\n'
          '$fields\n'
          '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox.shrink();  // TODO: real painter\n'
          '}\n');
    } else {
      clsDecls.add('class $name extends StatelessWidget {\n'
          '  const $name({super.key});\n'
          '  @override\n'
          '  Widget build(BuildContext context) => const SizedBox.shrink();  // TODO: real painter\n'
          '}\n');
    }
  }
  final constDecls = (symbols['consts'] as List)
      .map((k) => 'const List<dynamic> $k = [];  // TODO: wire real data (data.jsx)\n')
      .toList();
  final body = clsDecls.join() + constDecls.join();
  return '// FACTORY EXTENSION POINT — hand-edit freely; the factory will NOT overwrite this\n'
      '// file once you add real chart painters. @appbox-extension-point: presentation/home_assets\n'
      '//\n'
      '// The bespoke home chart widgets + data constants the generated home_view.dart imports.\n'
      '// These are the generation FRONTIER (no CSS→CustomPainter codegen): the operator authors\n'
      '// the real painters parameterized by the k* data constants (derived from data.jsx). This\n'
      '// STUB declares each referenced symbol with a constructor MATCHING the call-site\'s named\n'
      '// params so `dart analyze` passes out-of-the-box; replace each body with the design\'s real\n'
      '// widget. GENERIC: the symbol set + signatures are derived from what the emitted home_view\n'
      '// actually references, so any design\'s chart vocabulary (StatBars/DonutChart/...) is\n'
      '// declared here with the right signature, not a hardcoded list.\n'
      "import 'package:flutter/material.dart';\n\n$body";
}

// ──────────── gates (raise on failure) ────────────

void assertContentParity(Node spec, String dart) {
  final low = dart.toLowerCase();
  final missing = <String>[];
  for (final n in walk(treeOf(spec))) {
    for (final seg in inlinesOf(n)) {
      final t = (seg['text']?.toString() ?? '').trim();
      if (seg.containsKey('tag') && t.isNotEmpty && !low.contains(t.toLowerCase())) {
        missing.add(t);
      }
    }
  }
  if (missing.isNotEmpty) {
    throw GateFailure('CONTENT-PARITY GATE FAILED — inline label(s) present in the '
        'design but dropped from the view: $missing. Emit a Text.rich span, don\'t flatten.');
  }
}

List<Node> inlinesOf(Node n) {
  final i = n['inlines'];
  return i is List ? i.cast<Node>() : <Node>[];
}

void assertNoDegenerateBox(String dart) {
  if (degenBoxRe.hasMatch(dart)) {
    throw GateFailure('RENDER-COVERAGE GATE FAILED — a node rendered to a degenerate '
        '(sizeless + colourless) Container; a visible element was dropped. '
        'Route dynamic/complex elements to a bespoke widget, or fix the styled box.');
  }
}

String wireNavImports(String dart) {
  final need = <String>[];
  if (dart.contains('locator<NavigationService>')) {
    need.addAll([
      'package:stacked_services/stacked_services.dart',
      '../app/app.locator.dart',
      '../app/app.router.dart'
    ]);
  }
  if (dart.contains('locator<RootNavigationViewModel>')) {
    need.add('root_navigation_viewmodel.dart');
  }
  if (dart.contains('locator<SupabaseAuthService>')) {
    need.addAll([
      '../app/app.locator.dart',
      '../infrastructure/supabase_auth_service.dart'
    ]);
  }
  final seen = <String>{};
  final inject = StringBuffer();
  for (final pkg in need) {
    if (seen.contains(pkg)) continue;
    seen.add(pkg);
    if (!dart.contains("'$pkg'")) {
      inject.write("import '$pkg';\n");
    }
  }
  if (inject.isEmpty) return dart;
  final ms = RegExp(r'^import .*;\n', multiLine: true).allMatches(dart).toList();
  final pos = ms.isEmpty ? 0 : ms.last.end;
  return dart.substring(0, pos) + inject.toString() + dart.substring(pos);
}

// ──────────── the generator (per-build mutable state + emit) ────────────

class GenerateView {
  // per-run state (reset in buildView)
  final Map<String, Map<String, String>> svgAssets = {};
  final Map<String, Node> svgLedger = {};
  Map<String, String> bind = Map.of(bindDefault);
  Map<String, String> hex2tok = Map.of(hex2tokDefault);
  Node tokens = <String, dynamic>{};
  Node state = <String, dynamic>{};
  bool needsFmtSec = false;
  String overlay = '';
  Node? timer;
  Node render = <String, dynamic>{'fidelity': 'native', 'overrides': <String, dynamic>{}};
  Node? glassEntrance;
  List<Node> handlers = <Node>[];
  Map<String, int> tabTargets = <String, int>{};
  bool rowWUnbounded = false;
  bool homeCard = false;
  bool formVm = false;
  String authFieldType = 'text';
  int? entranceDelay;
  bool applyBox = false;

  // ── SVG asset registry ──

  String svgAsset(String svg, {String origin = ''}) {
    final path = 'assets/svg/${svgId(svg)}.svg';
    svgAssets[path] = {'svg': svg};
    svgLedger.putIfAbsent(path, () => {
          'id': path,
          'origin': origin,
          'rendered': true,
        });
    return path;
  }

  void dropGlyph(Node node, String origin, String reason) {
    final svg = node['svg']?.toString() ?? '';
    final w = px(node['svgw']?.toString() ?? '') ?? px(styleOf(node)['width']);
    final h = px(node['svgh']?.toString() ?? '') ?? px(styleOf(node)['height']);
    svgLedger.putIfAbsent(svgId(svg), () => {
          'id': svgId(svg),
          'origin': origin,
          'w': w,
          'h': h,
          'rendered': false,
          'dropReason': reason,
          'svg': svg,
        });
  }

  // ── var() resolution + color ──

  dynamic resolveVar(dynamic v) {
    var seen = 0;
    while (v is String && v.startsWith('var(') && seen < 8) {
      final m = RegExp(r'^var\(\s*(--[\w-]+)\s*(?:,([^()]*))?\)').firstMatch(v);
      if (m == null) break;
      final tk = tokens[m.group(1)];
      final fb = m.group(2)?.trim() ?? '';
      v = tk ?? fb;
      seen++;
    }
    return v;
  }

  String? colorDart(dynamic v) {
    if (v == null) return null;
    final sv = v is String ? v : '$v';
    final val = resolveVar(sv.trim());
    if (val == null || val is! String || val.isEmpty) return null;
    final up = val.toUpperCase();
    if (hex2tok.containsKey(up)) return hex2tok[up];
    final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(val);
    if (m != null) return 'const Color(0xFF${m.group(1)!.toUpperCase()})';
    if (const {'#fff', '#ffffff', '#FFF', '#FFFFFF', 'white'}.contains(val)) {
      return 'Colors.white';
    }
    final rm = RegExp(
            r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$')
        .firstMatch(val);
    if (rm != null) {
      final r = rm.group(1)!, g = rm.group(2)!, b = rm.group(3)!;
      final a = rm.group(4) ?? '1';
      return 'Color.fromRGBO($r, $g, $b, $a)';
    }
    return null;
  }

  // ── box decoration ──

  String? borderDart(Node style) {
    final b = style['border']?.toString().trim() ?? '';
    if (b.isEmpty || b.toLowerCase() == 'none') return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)px').firstMatch(b);
    final bw = m?.group(1) ?? '1';
    final cm = RegExp(r'#[0-9A-Fa-f]{3,8}|rgba?\([^)]*\)|var\([^)]*\)').firstMatch(b);
    final col = cm != null ? colorDart(cm.group(0)) : null;
    if (col == null) return null;
    return 'Border.all(color: $col, width: $bw)';
  }

  /// Returns (sizeArgs, decoration, visible).
  List<dynamic> decoArgs(Node style) {
    final args = <String>[];
    final w = px(style['width']);
    final h = px(style['height']);
    if (w != null) args.add('width: ${numFmt(w)}');
    if (h != null) args.add('height: ${numFmt(h)}');
    final deco = <String>[];
    final bg = colorDart(style['background'] ?? style['background-color']);
    if (bg != null) deco.add('color: $bg');
    final bd = borderDart(style);
    if (bd != null) deco.add('border: $bd');
    final br = style['border-radius']?.toString().trim() ?? '';
    if (br == '50%' || br == '999px' || br.endsWith('9999px')) {
      deco.add('shape: BoxShape.circle');
    } else {
      final r = px(br);
      if (r != null) deco.add('borderRadius: BorderRadius.circular(${numFmt(r)})');
    }
    final decoration = deco.isNotEmpty ? 'BoxDecoration(${deco.join(', ')})' : null;
    final visible = bg != null || bd != null || w != null || h != null;
    return [args, decoration, visible];
  }

  String styledBox(Node style) {
    final r = decoArgs(style);
    final args = (r[0] as List).cast<String>();
    final deco = r[1] as String?;
    final visible = r[2] as bool;
    if (!visible) return '';
    if (deco != null) args.add('decoration: $deco');
    return 'Container(${args.join(', ')})';
  }

  String textStyle(Node style, List<String> classes) {
    final parts = <String>[];
    final fs = px(style['font-size']);
    if (fs != null) parts.add('fontSize: ${numFmt(fs)}');
    final fw = weight(style['font-weight']);
    if (fw != null) parts.add('fontWeight: $fw');
    final col = colorDart(style['color']);
    if (col != null) parts.add('color: $col');
    if (classes.contains('num') || classes.contains('big')) {
      parts.add('fontFeatures: const [FontFeature.tabularFigures()]');
    }
    return 'TextStyle(${parts.join(', ')})';
  }

  // ── bind / label helpers ──

  String? bindExpr(List<String> binds) {
    for (final b in binds) {
      if (bind.containsKey(b)) return bind[b];
    }
    if (binds.any((b) => b.contains('notes'))) return 's.note ?? ""';
    return null;
  }

  String buttonLabel(Node n) {
    final texts = <String>[];
    void collect(Node n) {
      final t = n['text']?.toString().trim() ?? '';
      if (t.isNotEmpty && t != ':' && t != '·') texts.add(t);
      for (final c in kidsOf(n)) {
        collect(c);
      }
    }

    collect(n);
    var label = texts.join(' ').trim();
    label = label.startsWith(':') ? label.substring(1).trim() : label;
    return label.isEmpty ? 'Continue' : label;
  }

  String fieldPlaceholder(Node n) {
    final p = propsOf(n)['placeholder']?.toString();
    if (p != null && p.isNotEmpty) return p;
    for (final c in kidsOf(n)) {
      final t = c['text']?.toString().trim() ?? '';
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  String svgWidget(Node n, {String? tint}) {
    final svg = n['svg']?.toString() ?? '';
    final w = px(n['svgw']?.toString() ?? '') ?? px(styleOf(n)['width']);
    final h = px(n['svgh']?.toString() ?? '') ?? px(styleOf(n)['height']);
    final args = <String>[dartStr(svgAsset(svg))];
    if (w != null) args.add('width: ${numFmt(w)}');
    if (h != null) args.add('height: ${numFmt(h)}');
    if (tint != null && svg.contains('currentColor')) {
      args.add('colorFilter: ColorFilter.mode($tint, BlendMode.srcIn)');
    }
    return 'SvgPicture.asset(${args.join(', ')})';
  }

  // ── render fidelity ──

  String renderMode(Node node) {
    final cid = primCanonical[node['prim']?.toString() ?? ''];
    final ov = (render['overrides'] as Map?)?.cast<String, String>() ?? {};
    if (cid != null && ov.containsKey(cid)) return ov[cid]!;
    return (render['fidelity']?.toString() ?? 'native');
  }

  // ── legibility (contrast) ──

  String contrastFg(String bgHex) =>
      wcagContrast(bgHex, '#FFFFFF') >= wcagContrast(bgHex, inkHex)
          ? 'Colors.white'
          : 'AppTokens.ink';

  double assertLegible(String fgDart, String bgHex, String ctx) {
    final fgHex = fgDart == 'Colors.white' ? '#FFFFFF' : inkHex;
    final r = wcagContrast(fgHex, bgHex);
    if (r < legibleMin) {
      throw GateFailure('LEGIBILITY GATE FAILED — $ctx: label $fgDart on $bgHex = '
          '${r.toStringAsFixed(1)}:1 (< ${legibleMin.toStringAsFixed(1)}:1 WCAG AA)');
    }
    return r;
  }

  // ── icon mapping ──

  List<String> iconFor(String name) {
    var n = name.trim();
    final tern = splitTernary(n);
    if (tern != null) {
      final cond = tern[0], a = tern[1], c = tern[2];
      final rc = reactiveVar(cond.trim());
      if (rc != null) {
        final ma = iconFor(a);
        final mc = iconFor(c);
        return ['($rc ? ${ma[0]} : ${mc[0]})', '($rc ? ${ma[1]} : ${mc[1]})'];
      }
      return iconFor(condValue(cond) == true ? a : c);
    }
    if (n.isNotEmpty && (n[0] == "'" || n[0] == '"' || n[0] == '`')) {
      n = n.substring(1, n.length - 1);
    }
    final pair = iconMap[n] ?? defaultIcon;
    return [pair[0], "'${pair[1]}'"];
  }

  String? trailingIcon(Node node) {
    Node? iconChild;
    for (final c in kidsOf(node)) {
      if (c['prim'] == 'Icon') iconChild = c;
    }
    if (iconChild == null) return null;
    final name = propsOf(iconChild)['name']?.toString() ?? '';
    final styleStr = '${iconChild['style'] ?? ''}';
    final propsJson = jsonEncode(iconChild['props'] ?? {});
    final rotated = styleStr.contains('rotate(180') ||
        styleStr.contains('rotate(-180') ||
        propsJson.contains('rotate(180');
    final sf = iconFor(name)[1].replaceAll("'", '');
    if (rotated && (sf == 'chevron.left' || sf == 'chevron.right')) {
      return sf == 'chevron.left' ? 'chevron.right' : 'chevron.left';
    }
    return sf;
  }

  String iconAction(String name) {
    final n = name.toLowerCase();
    final stripped = n.trim().replaceAll("'", '').replaceAll('"', '');
    if (const {'back', 'chevron-left', 'close', 'xmark'}.contains(stripped)) {
      return "() => locator<NavigationService>().back()";
    }
    if (timer != null) {
      final running = timer!['running']?.toString() ?? 'x';
      if (n.contains('play') || n.contains('pause') || running.isNotEmpty && n.contains(running)) {
        return '() => viewModel.toggle()';
      }
      if (n.contains('reset')) return '() => viewModel.reset()';
    }
    return '() {}';
  }

  String iconButton(Node node) {
    final iconChild = kidsOf(node).firstWhere((c) => c['tag'] == 'Icon',
        orElse: () => <String, dynamic>{});
    final name = propsOf(iconChild)['name']?.toString();
    final pair = iconFor(name ?? '');
    final mat = pair[0], sf = pair[1];
    final action = iconAction(name ?? '');
    final cls = classesOf(node);
    final primary = cls.contains('primary');
    final tint = primary ? 'AppTokens.accent' : 'AppTokens.ink2';
    final sem = action.contains('toggle')
        ? 'Play or pause'
        : action.contains('reset')
            ? 'Reset'
            : ((name ?? 'button').replaceAll(RegExp(r'\W+'), ' ').trim().isEmpty
                ? 'button'
                : (name ?? 'button').replaceAll(RegExp(r'\W+'), ' ').trim());
    return 'AdaptiveIconButton(icon: $mat, sfSymbol: $sf, tint: $tint, '
        'foreground: AppTokens.bone, size: ${primary ? 44 : 36}, '
        'semanticLabel: ${dartStr(sem)}, onPressed: $action)';
  }

  String iconWidget(Node node) {
    final props = propsOf(node);
    final pair = iconFor(props['name']?.toString() ?? '');
    final size = px(props['size']?.toString() ?? '');
    final own = colorDart(styleOf(node)['color']);
    final args = <String>[pair[0]];
    if (size != null) args.add('size: ${numFmt(size)}');
    if (own != null) args.add('color: $own');
    return 'Icon(${args.join(', ')})';
  }

  // ── reactive / state resolution ──

  String? reactiveVar(String name) {
    if (timer != null) {
      final running = timer!['running']?.toString();
      final value = timer!['value']?.toString();
      if (name == running || name == value) return 'viewModel.$name';
    }
    return null;
  }

  bool? condValue(String cond) {
    var c = cond.trim();
    while (outerParens(c)) {
      c = c.substring(1, c.length - 1).trim();
    }
    if (reactiveVar(c) != null) return null;
    for (final op in ['||', '&&']) {
      final parts = splitTop(c, op);
      if (parts.length > 1) {
        final vals = parts.map(condValue).toList();
        if (op == '&&' && vals.any((v) => v == false)) return false;
        if (op == '||' && vals.any((v) => v == true)) return true;
        if (vals.every((v) => v != null)) {
          return op == '||' ? vals.any((v) => v == true) : vals.every((v) => v == true);
        }
        return null;
      }
    }
    if (c.startsWith('!')) {
      final inner = condValue(c.substring(1));
      return inner == null ? null : !inner;
    }
    final m = RegExp(r"^([\w.]+)\s*===?\s*'([^']*)'$").firstMatch(c);
    if (m != null) {
      final v = state[m.group(1)];
      return v == null ? null : v.toString() == m.group(2);
    }
    final v = state[c];
    return v is bool ? v : null;
  }

  bool condHidden(Node c) {
    final v = condValue(c['expr']?.toString() ?? '');
    if (v == null) return false;
    return c['branch'] == 'then' ? !v : v;
  }

  String? resolveValue(String b) {
    final key = b.trim();
    if (key.isEmpty) return null;
    final rv = reactiveVar(key);
    if (rv != null) return rv;
    if (bind.containsKey(key)) return bind[key];
    final v = state[key];
    if (v is String && v.isNotEmpty && v != key) return resolveValue(v);
    return null;
  }

  String? resolveOne(String b) {
    var key = b.trim();
    while (outerParens(key)) {
      key = key.substring(1, key.length - 1).trim();
    }
    final tern = splitTernary(key);
    if (tern != null) {
      final cond = tern[0], a = tern[1], c = tern[2];
      final val = condValue(cond);
      if (val == true) return resolveOne(a);
      if (val == false) return resolveOne(c);
      final rc = reactiveVar(cond.trim());
      if (rc != null) {
        final ra = resolveOne(a) ?? "''";
        final rcc = resolveOne(c) ?? "''";
        return '($rc ? $ra : $rcc)';
      }
      return null;
    }
    if (key.isNotEmpty && (key[0] == "'" || key[0] == '"' || key[0] == '`')) {
      final inner = key.substring(1, key.length - 1);
      if (!inner.contains('\${')) {
        // Note: Dart string '\${' check mirrors Python '"${"'.
        if (!inner.contains(r'${')) {
          return "'${inner.replaceAll('\\', '\\\\').replaceAll("'", r"\'")}'";
        }
      }
      return null;
    }
    final m = RegExp(r'^(fmtSec|fmtSecMs)\((.+)\)$').firstMatch(key);
    if (m != null) {
      final arg = resolveValue(m.group(2)!.trim());
      if (arg != null) {
        needsFmtSec = true;
        return "'\${fmtSec($arg)}'";
      }
      return null;
    }
    final val = resolveValue(key);
    return val != null ? "'\${$val}'" : null;
  }

  String? resolveBindContent(List<String> binds) {
    for (final b in binds) {
      final c = resolveOne(b);
      if (c != null) return c;
    }
    if (binds.any((b) => b.contains('notes'))) {
      return "'\${s.note ?? \"\"}'";
    }
    return null;
  }

  // ── buttons ──

  String nativeButton(Node node, String label) {
    final cls = classesOf(node);
    final style = styleOf(node);
    String variant;
    if (cls.contains('google')) {
      variant = 'outline';
    } else if (cls.contains('ghost') || cls.contains('nav-plain')) {
      variant = 'ghost';
    } else if (cls.any((c) => c.contains('destructive'))) {
      variant = 'destructive';
    } else if (cls.contains('tinted') || cls.contains('secondary')) {
      variant = 'secondary';
    } else if (cls.contains('primary')) {
      variant = 'primary';
    } else {
      variant = 'primary';
    }
    final raw = resolveVar(
        (style['background'] ?? style['background-color'] ?? '').toString().trim());
    var tint = colorDart(raw);
    final bgHex =
        (raw is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) ? raw : '#FBF8F2';
    String? fg;
    final capFgHex = resolveVar(style['color']?.toString().trim() ?? '');
    final capFgDart = colorDart(capFgHex);
    if (capFgDart != null) {
      fg = capFgDart;
      if (capFgHex is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(capFgHex)) {
        final r = wcagContrast(capFgHex, bgHex);
        if (r < legibleMin) {
          stderr.writeln('  note: button[${cls.join(' ')}] label uses the '
              "design's authored colour ($capFgHex on $bgHex = "
              '${r.toStringAsFixed(1)}:1, < ${legibleMin.toStringAsFixed(1)}:1 AA) — '
              'honoured as a deliberate design choice, not generator-introduced.');
        }
      }
    } else {
      fg = contrastFg(bgHex);
      final ctxCls = classesOf(node).join(' ');
      assertLegible(fg, bgHex, 'button[${ctxCls.isEmpty ? '?' : ctxCls}]');
    }
    final isFormGated = formVm &&
        variant == 'primary' &&
        (authFieldTypes[authFieldType]?['re'] != null);
    if (isFormGated) {
      tint = null;
      fg = null;
    }
    final args = <String>[
      'label: ${dartStr(label)}',
      'variant: AdaptiveButtonVariant.$variant',
      'expand: true',
    ];
    if (glassEntrance != null && entranceDelay != null) {
      final g = glassEntrance!;
      args.add('enterOnAppear: GlassEntrance(delayMs: $entranceDelay, '
          'responseS: ${g['response_s']}, bounce: ${g['bounce']}, '
          'opacityFrom: ${g['opacityFrom']}, scaleFrom: ${g['scaleFrom']}, '
          'liftPx: ${(g['liftPx'] as num).toDouble()})');
    }
    final glyph = findSvg(node);
    if (glyph != null) {
      final originCls = classesOf(node).join(' ');
      dropGlyph(
          glyph,
          '${originCls.isEmpty ? 'button' : originCls} (native action.button)',
          'native Liquid Glass button accepts only SF Symbols, not a custom brand graphic');
    }
    if (tint != null) args.add('tint: $tint');
    if (fg != null) args.add('foreground: $fg');
    final trailing = trailingIcon(node);
    if (trailing != null) args.add('trailingSfSymbol: ${dartStr(trailing)}');
    if (formVm) {
      String on;
      if (cls.contains('primary')) {
        on = 'viewModel.sendCode()';
        if (authFieldTypes[authFieldType]?['re'] != null) {
          args.add('enabled: viewModel.formValid');
        }
        args.add('busy: viewModel.isBusy');
      } else if (cls.contains('google')) {
        on = "viewModel.go('google')";
        args.add('busy: viewModel.isBusy');
      } else {
        on = "viewModel.go('apple')";
        args.add('busy: viewModel.isBusy');
      }
      args.add('onPressed: () => $on');
    } else {
      final h = handlerForNode(node);
      args.add('onPressed: ${h ?? '() {}'}');
    }
    return 'AdaptiveButton(${args.join(', ')})';
  }

  String styledButton(Node node, String label) {
    final style = styleOf(node);
    final raw = resolveVar(
        (style['background'] ?? style['background-color'] ?? '#FBF8F2').toString().trim());
    final bgd = colorDart(raw) ?? 'AppTokens.paper';
    final fg = (raw is String &&
            RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw) &&
            lum(raw) < 0.5)
        ? 'Colors.white'
        : 'AppTokens.ink';
    final border = style['border']?.toString() ?? '';
    final bm = RegExp(r'#[0-9A-Fa-f]{6}').firstMatch(border);
    final rad = px(style['border-radius']?.toString() ?? '');
    final mh = px(style['min-height']?.toString() ?? '') ?? 52;
    final shape = rad != null
        ? 'RoundedRectangleBorder(borderRadius: BorderRadius.circular(${numFmt(rad)}))'
        : 'StadiumBorder()';
    final common = 'minimumSize: Size.fromHeight(${numFmt(mh)}), shape: $shape';
    final glyph = findSvg(node);
    final txt = 'Text(${dartStr(label)})';
    String child;
    if (glyph != null) {
      child =
          'Row(mainAxisSize: MainAxisSize.min, children: [${svgWidget(glyph, tint: fg)}, '
          'const SizedBox(width: 10), $txt])';
    } else {
      child = txt;
    }
    if (border.contains('solid') && bm != null) {
      final bcd = colorDart(bm.group(0)) ?? 'AppTokens.rule';
      return 'SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () {}, '
          'style: OutlinedButton.styleFrom(backgroundColor: $bgd, foregroundColor: $fg, '
          'side: BorderSide(color: $bcd), $common), child: $child))';
    }
    return 'SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, '
        'style: FilledButton.styleFrom(backgroundColor: $bgd, foregroundColor: $fg, '
        '$common), child: $child))';
  }

  // ── box/motion wrapping ──

  String boxWrap(Node node, String widget) {
    if (!applyBox || widget.isEmpty) return widget;
    final prim = node['prim'].toString();
    final style = styleOf(node);
    if (!selfPad.contains(prim) && !prim.startsWith('chart:')) {
      final pad = edgeInsets(edges(style, 'padding'));
      if (pad != null) widget = 'Padding(padding: $pad, child: $widget)';
    }
    if ((prim == 'Box' || prim == 'Row' || prim == 'Column') &&
        kidsOf(node).isNotEmpty &&
        bespokeBoxClasses.intersection(classesOf(node).toSet()).isEmpty) {
      final r = decoArgs(style);
      final args = (r[0] as List).cast<String>();
      final deco = r[1] as String?;
      final visible = r[2] as bool;
      if (visible) {
        var inner = widget;
        final col = colorDart(style['color']);
        if (col != null) {
          inner = 'IconTheme.merge(data: IconThemeData(color: $col), child: $inner)';
        }
        if (deco != null) args.add('decoration: $deco');
        args.add('child: $inner');
        widget = 'Container(${args.join(', ')})';
      }
    }
    final mar = edgeInsets(edges(style, 'margin'));
    if (mar != null) widget = 'Padding(padding: $mar, child: $widget)';
    return widget;
  }

  bool hasNative(Node node) =>
      walk([node]).any((n) => nativePrims.contains(n['prim']?.toString()));

  String motionWrap(Node node, String widget) {
    if (!applyBox || widget.isEmpty) return widget;
    final mo = node['motion'];
    if (mo is! Node) return widget;
    final kind = mo['kind']?.toString();
    if (kind == 'pulse') {
      return 'PulseRing(durationMs: ${mo['durMs']}, child: $widget)';
    }
    if (kind == 'pop') {
      return 'PopIn(durationMs: ${mo['durMs']}, child: $widget)';
    }
    if (kind != 'rise-in') return widget;
    final safe = !hasNative(node) ? 'skipOnGlass: false, ' : '';
    return 'RiseIn(delayMs: ${mo['delayMs']}, durationMs: kRiseMs, '
        'curve: kRiseCurve, dy: kRiseDy, ${safe}child: $widget)';
  }

  List<String> children(List<Node> nodes, bool sess) =>
      nodes.map((n) => emit(n, sess)).where((e) => e.isNotEmpty).toList();

  String rowOrCol(Node node, bool sess, bool horizontal) {
    final raw = kidsOf(node);
    final sb = gapBox(styleOf(node), horizontal);
    final ma = mainAxis(styleOf(node));
    final parts = <String>[];
    for (final c in raw) {
      final cprim = c['prim']?.toString() ?? '';
      final willFlex = horizontal &&
          parts.isEmpty &&
          raw.length > 1 &&
          !rowWUnbounded &&
          (cprim == 'Column' || cprim == 'Box' || (cprim == 'Text' && ma == 'spaceBetween'));
      final prev = rowWUnbounded;
      if (horizontal) rowWUnbounded = !willFlex;
      String e;
      try {
        e = emit(c, sess);
      } finally {
        rowWUnbounded = prev;
      }
      if (e.isEmpty) continue;
      e = motionWrap(c, boxWrap(c, e));
      if (willFlex) {
        final wrap = cprim == 'Column' || cprim == 'Box' ? 'Expanded' : 'Flexible';
        e = '$wrap(child: $e)';
      }
      if (parts.isNotEmpty && sb != null) {
        if (!horizontal &&
            formVm &&
            providerRe.hasMatch(classesOf(c).join(' '))) {
          parts.add(adaptiveGap(sb));
        } else {
          parts.add(sb);
        }
      }
      parts.add(e);
    }
    if (parts.isEmpty) return '';
    final kids = parts.join(',\n');
    final widget = horizontal ? 'Row' : 'Column';
    var extra = horizontal ? '' : 'mainAxisSize: MainAxisSize.min, ';
    final ca = crossAxis(styleOf(node));
    extra += 'crossAxisAlignment: CrossAxisAlignment.$ca, ';
    if (ca == 'baseline') extra += 'textBaseline: TextBaseline.alphabetic, ';
    if (ma != 'start') extra += 'mainAxisAlignment: MainAxisAlignment.$ma, ';
    return '$widget($extra children: [\n$kids,\n])';
  }

  // ── handler / nav wiring ──

  String? handlerForNode(Node node) {
    if (handlers.isEmpty) return null;
    final label = node['text']?.toString().trim() ?? '';
    final classes = classesOf(node);
    for (final e in handlers) {
      final sel = (e['selector'] as Map?)?.cast<String, dynamic>() ?? {};
      final selLabel = sel['label']?.toString();
      final selClass = sel['class']?.toString();
      final match = (label.isNotEmpty && selLabel == label) ||
          (selClass != null && selLabel == null && classes.contains(selClass));
      if (!match) continue;
      if (e['kind'] == 'auth' &&
          e['target'] == 'splash' &&
          (e['prop']?.toString().toLowerCase() ?? '').contains('signout')) {
        return '() async { await locator<SupabaseAuthService>().signOut(); '
            'locator<NavigationService>().clearStackAndShow(Routes.signinView); }';
      }
      final nav = navCall(e);
      if (nav != null) return '() => $nav';
    }
    return null;
  }

  String? navCall(Node? edge) {
    if (edge == null) return null;
    final k = edge['kind']?.toString();
    final t = edge['target']?.toString();
    if (k == 'nav-back') return 'locator<NavigationService>().back()';
    if ((k == 'nav' || k == 'modal') && t != null && t.isNotEmpty) {
      if (tabTargets.containsKey(t)) {
        return 'locator<RootNavigationViewModel>().onTabSelected(${tabTargets[t]})';
      }
      final view = '${t.split(RegExp(r'[_-]')).map((w) => _cap(w)).join()}View';
      return 'locator<NavigationService>().navigateTo$view()';
    }
    return null;
  }

  // ── emit dispatch ──

  String emit(Node node, bool sess) {
    final cond = node['cond'];
    if (cond is Node && condHidden(cond)) return '';
    final mo = node['motion'];
    if (mo is Node && mo['kind'] == 'rise-in') {
      final prev = entranceDelay;
      entranceDelay = mo['delayMs'] is int
          ? mo['delayMs'] as int
          : int.tryParse('${mo['delayMs']}');
      final out = emitImpl(node, sess);
      entranceDelay = prev;
      if (out.isNotEmpty && handlers.isNotEmpty &&
          !nativePrimPrefixes.any((p) => out.startsWith(p))) {
        final h = handlerForNode(node);
        if (h != null) {
          return 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: $h, child: $out)';
        }
      }
      return out;
    }
    final out = emitImpl(node, sess);
    if (out.isNotEmpty && handlers.isNotEmpty &&
        !nativePrimPrefixes.any((p) => out.startsWith(p))) {
      final h = handlerForNode(node);
      if (h != null) {
        return 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: $h, child: $out)';
      }
    }
    return out;
  }

  String emitImpl(Node node, bool sess) {
    final prim = node['prim']?.toString() ?? '';
    final cls = classesOf(node);
    final style = styleOf(node);

    if (node['svg'] != null && !cls.contains('spinner')) {
      return svgWidget(node);
    }

    if (cls.contains('auth-divider')) {
      var txt = '';
      for (final c in kidsOf(node)) {
        final t = c['text']?.toString() ?? '';
        if (t.isNotEmpty) {
          txt = t;
          break;
        }
      }
      return 'Row(children: [const Expanded(child: Divider(color: AppTokens.rule)), '
          'Padding(padding: const EdgeInsets.symmetric(horizontal: 12), '
          'child: Text(${dartStr(txt.toUpperCase())}, style: const TextStyle(fontSize: 11, '
          'letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppTokens.ink3))), '
          'const Expanded(child: Divider(color: AppTokens.rule))])';
    }

    if (cls.contains('splash-bottom')) {
      return 'SplashProgress(durationMs: kSplashFillMs)';
    }

    if (prim.startsWith('chart:')) {
      final tag = node['tag']?.toString() ?? 'Chart';
      final kind = prim.split(':')[1];
      final constName = 'k$tag';
      if (kind == 'bars') {
        return '$tag(values: ${constName}Values, labels: ${constName}Labels, max: 0)';
      }
      if (kind == 'heat') return '$tag(weeks: $constName)';
      if (kind == 'trend') return '$tag(points: $constName)';
      return '$tag()';
    }

    if (prim == 'IconButton') {
      return "AdaptiveIconButton(icon: KitGlyphs.lucide('play'), sfSymbol: 'play.fill', "
          'tint: AppTokens.ink, foreground: AppTokens.bone, size: 36, '
          "onPressed: () {}, semanticLabel: 'Start workout')";
    }

    if (isIconButton(node)) {
      return iconButton(node);
    }

    if (prim == 'Pip') {
      final label = (sess && homeCard) ? 's.type.toUpperCase()' : "''";
      return 'Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), '
          'decoration: BoxDecoration(color: AppTokens.bone, borderRadius: BorderRadius.circular(999), '
          'border: Border.all(color: AppTokens.rule)), '
          'child: Row(mainAxisSize: MainAxisSize.min, children: [ '
          'Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTokens.accent, shape: BoxShape.circle)), '
          'const SizedBox(width: 6), '
          'Text($label, style: const TextStyle(fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w600, color: AppTokens.ink2)) ]))';
    }

    if (prim == 'AdaptiveButton') {
      if (formVm && providerRe.hasMatch(classesOf(node).join(' '))) {
        final provider = classesOf(node).contains('google') ? 'google' : 'apple';
        final label = buttonLabel(node);
        return 'AdaptiveAuthButton(provider: ${dartStr(provider)}, '
            'label: ${dartStr(label)}, busy: viewModel.isBusy, '
            'onPressed: () => viewModel.go(${dartStr(provider)}))';
      }
      if (renderMode(node) == 'design') {
        return styledButton(node, buttonLabel(node));
      }
      return nativeButton(node, buttonLabel(node));
    }

    if (prim == 'AdaptiveTextField') {
      final ph = fieldPlaceholder(node);
      if (formVm) {
        final ft = authFieldTypes[authFieldType] ?? authFieldTypes['text']!;
        final ctl = ft['ctl']!;
        final kt = ft['kt']!;
        final hook = ft['re'] != null ? ', onChanged: viewModel.onFieldChanged' : '';
        final phArg = ph.isNotEmpty ? ', placeholder: ${dartStr(ph)}' : '';
        return 'AdaptiveTextField(controller: viewModel.$ctl, keyboardType: $kt$phArg$hook)';
      }
      final kt = textFieldKt[propsOf(node)['type']?.toString() ?? ''];
      final ktArg = kt != null ? ', keyboardType: $kt' : '';
      final phArg = ph.isNotEmpty ? ', placeholder: ${dartStr(ph)}' : '';
      return 'AdaptiveTextField(controller: TextEditingController()$ktArg$phArg)';
    }

    if (prim == 'AdaptiveCard') {
      final bg = colorDart(style['background']);
      final stat = cls.contains('stat-card');
      final handler = handlerForNode(node);
      final pad = stat
          ? 'const EdgeInsets.fromLTRB(20, 18, 20, 16)'
          : 'const EdgeInsets.symmetric(horizontal: 18, vertical: 16)';
      final col = colBody(node, sess);
      final args = <String>[];
      if (bg != null) args.add('tint: $bg');
      args.add('lite: true');
      if (stat) args.add('radius: 24');
      if (handler != null) args.add('onTap: $handler');
      args.add('padding: $pad');
      args.add('child: $col');
      return 'AdaptiveCard(${args.join(', ')})';
    }

    if (prim == 'AdaptiveChip') {
      final label = buttonLabel(node);
      final selCls = {'active', 'current', 'selected'};
      final selected = cls.toSet().intersection(selCls).isNotEmpty;
      final handler = handlerForNode(node);
      final tint = colorDart(style['background']);
      final args = <String>[
        'label: ${dartStr(label)}',
        'selected: ${selected ? 'true' : 'false'}',
      ];
      if (tint != null) args.add('tint: $tint');
      args.add('onTap: ${handler ?? '() {}'}');
      return 'AdaptiveChip(${args.join(', ')})';
    }

    if (prim == 'AdaptiveSwitch') {
      final on = cls.contains('on');
      final tint = colorDart(style['background']);
      final args = <String>['value: ${on ? 'true' : 'false'}'];
      if (tint != null) args.add('tint: $tint');
      args.add('onChanged: (v) {}');
      return 'AdaptiveSwitch(${args.join(', ')})';
    }

    if (prim == 'AdaptiveSlider') {
      final props = propsOf(node);
      var mn = props['min'] != null ? px(props['min'].toString()) : null;
      var mx = props['max'] != null ? px(props['max'].toString()) : null;
      mn ??= 0.0;
      mx ??= 1.0;
      final rawVal = props['value'] != null ? px(props['value'].toString()) : null;
      final val = rawVal ?? mn;
      final rawStep = props['step'] != null ? px(props['step'].toString()) : null;
      int? divisions;
      if (rawStep != null && rawStep > 0 && mx > mn) {
        divisions = (((mx - mn) / rawStep).round()).clamp(1, 1 << 31);
        if (divisions < 1) divisions = 1;
      }
      final tint = colorDart(style['accent-color'] ?? style['color']);
      final args = <String>[
        'value: ${numFmt(val)}',
        'min: ${numFmt(mn)}',
        'max: ${numFmt(mx)}',
      ];
      if (divisions != null) args.add('divisions: $divisions');
      if (tint != null) args.add('tint: $tint');
      args.add('onChanged: (v) {}');
      return 'AdaptiveSlider(${args.join(', ')})';
    }

    if (prim == 'Text') {
      return text(node, sess);
    }

    if (prim == 'Icon') {
      return iconWidget(node);
    }

    if ((prim == 'Row' || prim == 'Column' || prim == 'Box') &&
        kidsOf(node).isNotEmpty &&
        kidsOf(node)
            .any((c) => styleOf(c)['position']?.toString() == 'absolute')) {
      return stackBody(node, sess);
    }

    if (prim == 'Row') return rowOrCol(node, sess, true);
    if (prim == 'Column') return rowOrCol(node, sess, false);

    if (node['inlines'] != null) {
      return text(node, sess);
    }
    if (kidsOf(node).isNotEmpty) {
      return colBody(node, sess).isNotEmpty
          ? colBody(node, sess)
          : (node['text'] != null || node['bind'] != null
              ? text(node, sess)
              : styledBox(style));
    }
    if (node['text'] != null || node['bind'] != null) {
      return text(node, sess);
    }
    return styledBox(style);
  }

  String stackBody(Node node, bool sess) {
    final parts = <String>[];
    for (final c in kidsOf(node)) {
      final e = emit(c, sess);
      if (e.isEmpty) continue;
      final we = motionWrap(c, boxWrap(c, e));
      final st = styleOf(c);
      final inset = st['inset']?.toString().trim() ?? '';
      if (st['position']?.toString() == 'absolute' &&
          (inset == '0' || inset == '0px')) {
        parts.add('Positioned.fill(child: $we)');
      } else {
        parts.add(we);
      }
    }
    if (parts.isEmpty) return '';
    return 'Stack(alignment: Alignment.center, children: [\n${parts.join(',\n')},\n])';
  }

  String colBody(Node node, bool sess) {
    final raw = kidsOf(node);
    final sb = gapBox(styleOf(node), false);
    final parts = <String>[];
    for (final c in raw) {
      final e = emit(c, sess);
      if (e.isEmpty) continue;
      final we = motionWrap(c, boxWrap(c, e));
      if (parts.isNotEmpty && sb != null) parts.add(sb);
      if (classesOf(c).contains('footer')) {
        parts.add('const DashedLine()');
        parts.add('const SizedBox(height: 12)');
      }
      parts.add(we);
    }
    if (parts.isEmpty) return '';
    final ca = styleOf(node)['align-items'] != null
        ? crossAxis(styleOf(node))
        : 'start';
    return 'Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: '
        'CrossAxisAlignment.$ca, children: [\n${parts.join(',\n')},\n])';
  }

  String richText(Node node, Node style, List<String> cls) {
    final up = style['text-transform']?.toString() == 'uppercase';
    final segs = inlinesOf(node);
    final last = segs.length - 1;
    final spans = <String>[];
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      var txt = (s['t'] ?? s['text'] ?? '').toString();
      if (up) txt = txt.toUpperCase();
      if (i == 0) txt = txt.replaceFirst(RegExp(r'^\s+'), '');
      if (i == last) txt = txt.replaceFirst(RegExp(r'\s+$'), '');
      if (txt.isEmpty) continue;
      if (inlineUnderline.contains(s['tag']?.toString() ?? '')) {
        spans.add('TextSpan(text: ${dartStr(txt)}, '
            'style: const TextStyle(decoration: TextDecoration.underline))');
      } else {
        spans.add('TextSpan(text: ${dartStr(txt)})');
      }
    }
    var head =
        'Text.rich(TextSpan(style: ${textStyle(style, cls)}, children: [${spans.join(', ')}])';
    final align = const {'center': 'TextAlign.center', 'right': 'TextAlign.right', 'end': 'TextAlign.right'}[style['text-align']?.toString()];
    if (align != null) head += ', textAlign: $align';
    return '$head)';
  }

  String text(Node node, bool sess) {
    final cls = classesOf(node);
    final style = styleOf(node);
    final binds = bindsOf(node);
    String content;
    if (sess && homeCard && cls.contains('caption') && cls.contains('num')) {
      content = "'Last \${_lastLabel(s.occurredOn)} · \${s.streak}× streak'";
    } else if (sess && binds.isNotEmpty) {
      content = resolveBindContent(binds) ?? "''";
    } else if (node['inlines'] != null) {
      return richText(node, style, cls);
    } else {
      var t = node['text']?.toString() ?? '';
      if (t.isEmpty) return '';
      content = '';
      if (binds.isNotEmpty &&
          binds.any((b) => b.contains("''") || b.contains('""'))) {
        if (binds.any((b) => RegExp(r'\$\{name\}').hasMatch(b))) {
          final bound = t.replaceFirstMapped(RegExp(r'\s*([.!?,;:])\s*$'),
              (m) => ', \${viewModel.firstName}${m.group(1)}');
          if (bound != t) content = "'$bound'";
        }
        if (content.isEmpty) {
          t = t.replaceAllMapped(RegExp(r'\s+([.!?,;:])'), (m) => m.group(1)!);
        }
      }
      if (content.isEmpty) {
        if (style['text-transform']?.toString() == 'uppercase') t = t.toUpperCase();
        content = dartStr(t);
      }
    }
    final align = const {'center': 'TextAlign.center', 'right': 'TextAlign.right', 'end': 'TextAlign.right'}[style['text-align']?.toString()];
    final ta = align != null ? 'textAlign: $align, ' : '';
    final txt = 'Text($content, ${ta}style: ${textStyle(style, cls)})';
    final mw = maxWidthOf(style);
    if (mw != null) {
      return 'ConstrainedBox(constraints: const BoxConstraints(maxWidth: $mw), child: $txt)';
    }
    return txt;
  }

  // ── home assembly ──

  String statsDeckMethod(Node spec) {
    final cards = statCards(spec)
        .map((c) => emit(c, false))
        .where((c) => c.isNotEmpty)
        .toList();
    // A design with no `.stat-card` nodes has no deck. Emitting the carousel
    // anyway produced `cards: [\n            ,\n    ]` — the trailing comma
    // belongs to the template, not to the list, so an empty $body left a bare
    // comma and the whole file stopped parsing (task #45). Same answer as
    // sessionCardMethod below, for the same reason: no source nodes, no widget.
    if (cards.isEmpty) {
      return '  Widget _statsDeck(HomeViewModel vm) {\n'
          '    // The design declares no stat-cards.\n'
          '    return const SizedBox.shrink();\n  }';
    }
    final body = cards.join(',\n            ');
    return '  Widget _statsDeck(HomeViewModel vm) {\n'
        '    // Spec-driven: the 4 cards (eyebrow/note/big/unit + chart kind +\n'
        '    // variant tint) are translated from the design composition. Only the\n'
        '    // chart curve data is fixed (the frontier).\n'
        '    return StatsCarousel(cards: [\n            $body,\n    ]);\n  }';
  }

  String sessionCardMethod(Node spec, String? cardNav) {
    final card = workoutCard(spec);
    if (card == null) {
      return '  Widget _sessionCard(Session s) {\n'
          '    return const SizedBox.shrink();\n  }';
    }
    homeCard = true;
    String body;
    try {
      body = emit(card, true);
    } finally {
      homeCard = false;
    }
    if (cardNav != null) {
      final nav = cardNav.replaceAll('navigateToDetailView()',
          'navigateToDetailView(workout: s)');
      body = 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => '
          '$nav, child: $body)';
    }
    return '  /// Spec-driven: structure + metric-right-of-title / play-on-footer\n'
        '  /// ordinals come from the design\'s workout-card subtree; field slots\n'
        '  /// are bound to the Session via the design→data_model map.\n'
        '  Widget _sessionCard(Session s) {\n'
        '    return $body;\n  }';
  }

  String yourWorkoutsText(Node spec) {
    var n = findNode(
        treeOf(spec), (x) => classesOf(x).contains('workouts-title') && x['text'] != null);
    n ??= findNode(treeOf(spec),
        (x) => (x['text']?.toString().toLowerCase() ?? '').startsWith('your workout'));
    return n != null ? n['text'].toString() : 'Your workouts';
  }

  String headerSrc(String? avatarNav) {
    final avatarBuf = StringBuffer()
      ..writeln('Container(')
      ..writeln('          width: 38, height: 38, alignment: Alignment.center,')
      ..writeln('          decoration: const BoxDecoration(color: AppTokens.ink, shape: BoxShape.circle),')
      ..writeln('          child: Text(vm.initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppTokens.bone)),')
      ..write('        )');
    var avatar = avatarBuf.toString();
    if (avatarNav != null) {
      avatar =
          'GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => $avatarNav, child: $avatar)';
    }
    return '  /// Composite (atlet-generic shell, not design-structure the gate grades):\n'
        '  /// eyebrow `WEEKDAY · HH:MM` over `{greeting,\\n{firstName}.` + initials avatar.\n'
        '  Widget _header(HomeViewModel vm) {\n'
        '    final now = DateTime.now();\n'
        "    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];\n"
        "    final hh = now.hour.toString().padLeft(2, '0');\n"
        "    final mm = now.minute.toString().padLeft(2, '0');\n"
        "    final eyebrow = '\${days[now.weekday - 1]} · \$hh:\$mm';\n"
        "    final greet = now.hour < 12 ? 'Morning' : now.hour < 18 ? 'Afternoon' : 'Evening';\n"
        '    return Row(\n'
        '      mainAxisAlignment: MainAxisAlignment.spaceBetween,\n'
        '      crossAxisAlignment: CrossAxisAlignment.start,\n'
        '      children: [\n'
        '        Expanded(\n'
        '          child: Column(\n'
        '            crossAxisAlignment: CrossAxisAlignment.start,\n'
        '            children: [\n'
        '              Text(eyebrow.toUpperCase(),\n'
        '                  style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: AppTokens.ink3)),\n'
        '              const SizedBox(height: 6),\n'
        "              Text('\$greet,\\n\${vm.firstName}.',\n"
        '                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.5, color: AppTokens.ink)),\n'
        '            ],\n'
        '          ),\n'
        '        ),\n'
        '        const SizedBox(width: 12),\n'
        '        $avatar,\n'
        '      ],\n'
        '    );\n'
        '  }';
  }

  String filterRowMethod(Node spec) {
    final title = dartStr(yourWorkoutsText(spec));
    return '  /// Composite: spec "Your workouts" title + count badge + New + the\n'
        '  /// AdaptiveSegmented filter (renders native glass on iOS / M3 on Android).\n'
        '  Widget _filterRow(HomeViewModel vm) {\n'
        '    return Column(\n'
        '      crossAxisAlignment: CrossAxisAlignment.stretch,\n'
        '      children: [\n'
        '        Row(\n'
        '          mainAxisAlignment: MainAxisAlignment.spaceBetween,\n'
        '          children: [\n'
        '            Row(children: [\n'
        '              Text($title,\n'
        '                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),\n'
        '              const SizedBox(width: 8),\n'
        '              Container(\n'
        '                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),\n'
        '                decoration: BoxDecoration(color: AppTokens.accentSoft, borderRadius: BorderRadius.circular(20)),\n'
        "                child: Text('\${vm.countFor(vm.filter)}',\n"
        '                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTokens.accent)),\n'
        '              ),\n'
        '            ]),\n'
        "            AdaptiveButton(label: 'New', variant: AdaptiveButtonVariant.secondary, sfSymbol: 'plus', icon: LucideIcons.plus, onPressed: () {}),\n"
        '          ],\n'
        '        ),\n'
        '        const SizedBox(height: 14),\n'
        '        AdaptiveSegmented(labels: HomeViewModel.segLabels, selectedIndex: vm.filter, onChanged: vm.setFilter),\n'
        '      ],\n'
        '    );\n'
        '  }';
  }

  // ── generic screen ──

  List<String> collectOverlays(List<Node> siblings) {
    final out = <String>[];
    for (final n in siblings) {
      if (!isOverlayRoot(n)) continue;
      final gate = overlayGate(n);
      final cls = classesOf(n).join(' ');
      final inner = emit(n, false);
      if (inner.trim().isEmpty) continue;
      final isScrim = cls.contains('scrim') || cls.contains('backdrop');
      String layer;
      if (isScrim) {
        layer = 'Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black54)))';
      } else {
        layer = 'Positioned(left: 0, right: 0, bottom: 0, child: SafeArea('
            'top: false, child: Material(color: Colors.transparent, child: $inner)))';
      }
      out.add('Visibility(visible: $gate, child: $layer)');
    }
    return out;
  }

  List<dynamic> genericBody(Node spec, {bool sess = false}) {
    final roots = treeOf(spec);
    final screens = roots
        .where((r) =>
            kidsOf(r).isNotEmpty &&
            !classesOf(r).any((c) => c.contains('spinner') || c.contains('overlay')))
        .toList();
    Node? root = screens.isNotEmpty ? screens.first : (roots.isNotEmpty ? roots.first : null);
    if (root == null) return ['const SizedBox.shrink()', '', <String>[]];
    final overlays = collectOverlays(roots.where((r) => !identical(r, root)).toList());
    final rs = styleOf(root);
    final rootBg = colorDart(rs['background'] ?? rs['background-color']);
    final rootColor = colorDart(rs['color']);
    final scaffoldBg = rootBg != null ? 'backgroundColor: $rootBg, ' : '';
    final rawBg = rs['background']?.toString() ?? rs['background-color']?.toString() ?? '';
    final bgM = RegExp(r'#[0-9A-Fa-f]{6}').firstMatch(rawBg);
    overlay = (bgM != null && contrastFg(bgM.group(0)!) == 'Colors.white') ? 'dark' : 'light';

    String finish(String body) {
      var b = body;
      if (rootColor != null) {
        b = 'DefaultTextStyle.merge(style: TextStyle(color: $rootColor), child: $b)';
      }
      return b;
    }

    final src = kidsOf(root).isNotEmpty ? kidsOf(root) : [root];
    final kids = <String>[];
    var hasExpanded = false;
    for (final c in src) {
      var e = emit(c, sess);
      if (e.isEmpty) continue;
      e = motionWrap(c, boxWrap(c, e));
      if (flexGrows(styleOf(c))) {
        if (scrolls(styleOf(c))) {
          final cma = mainAxis(styleOf(c));
          if (cma != 'start') {
            e = 'LayoutBuilder(builder: (ctx, _c) => '
                'SingleChildScrollView(child: ConstrainedBox('
                'constraints: BoxConstraints(minHeight: _c.maxHeight), '
                'child: Column(mainAxisSize: MainAxisSize.max, '
                'mainAxisAlignment: MainAxisAlignment.$cma, '
                'crossAxisAlignment: CrossAxisAlignment.stretch, '
                'children: [$e]))))';
          } else {
            e = 'SingleChildScrollView(child: $e)';
          }
        }
        e = 'Expanded(child: $e)';
        hasExpanded = true;
      }
      kids.add(e);
    }
    if (kids.isEmpty) return ['const SizedBox.shrink()', scaffoldBg, overlays];
    final ma = mainAxis(styleOf(root));
    final scrollPad = edgeInsets(edges(styleOf(root), 'padding'));
    String pad(String w) => scrollPad != null ? 'Padding(padding: $scrollPad, child: $w)' : w;

    if (hasExpanded) {
      final col = 'Column(crossAxisAlignment: CrossAxisAlignment.stretch, '
          'mainAxisAlignment: MainAxisAlignment.$ma, children: [\n${kids.join(',\n')},\n])';
      return [finish('SafeArea(child: ${pad(col)})'), scaffoldBg, overlays];
    }
    final padPrefix = scrollPad != null ? 'padding: $scrollPad, ' : '';
    if (ma != 'start') {
      final ca = crossAxis(styleOf(root));
      var sb = gapBox(styleOf(root), false);
      var kidList = kids;
      if (sb != null && kids.length > 1) {
        final spaced = <String>[];
        for (var i = 0; i < kids.length; i++) {
          if (i != 0) spaced.add(sb);
          spaced.add(kids[i]);
        }
        kidList = spaced;
      }
      var col = 'Column(mainAxisAlignment: MainAxisAlignment.$ma, '
          'crossAxisAlignment: CrossAxisAlignment.$ca, children: [\n${kidList.join(',\n')},\n])';
      if (ca == 'center' || ca == 'end') {
        col = 'SizedBox(width: double.infinity, child: $col)';
      }
      return [finish('SafeArea(child: ${pad(col)})'), scaffoldBg, overlays];
    }
    final col = 'Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: '
        'CrossAxisAlignment.stretch, children: [\n${kids.join(',\n')},\n])';
    return [finish('SingleChildScrollView(${padPrefix}child: $col)'), scaffoldBg, overlays];
  }

  String genericView(Node spec, String screenId, {String? startup}) {
    tokens = spec['tokens'] is Node ? spec['tokens'] as Node : <String, dynamic>{};
    final name = pascalCase(screenId);
    final snake = snakeCase(screenId);
    formVm = walk(treeOf(spec)).any((n) => n['prim']?.toString() == 'AdaptiveTextField');
    authFieldType = authField(spec);
    final model = modelBound(spec);
    final gb = genericBody(spec, sess: model);
    var body = gb[0] as String;
    final scaffoldBg = gb[1] as String;
    final overlays = (gb[2] as List).cast<String>();
    if (overlays.isNotEmpty) {
      body = 'Stack(children: [$body, ${overlays.join(', ')}])';
    }
    final ow = overlayWrap(overlay == 'dark');
    final overlayOpen = ow[0];
    final overlayClose = ow[1];
    final ctorArgs = model ? ', required this.workout' : '';
    final fields = model ? '  final Session workout;\n' : '';
    final modelLocal = model ? '    final s = workout;\n' : '';
    final vmArgs = (model && timer != null) ? 'workout' : '';
    // Splash is the one screen with no states: it IS the loading screen, so a
    // busy gate there would replace it with a blank one.
    //
    // Loading AND error, but no retry and no empty (task #43):
    //  * `isBusy` / `hasError` are both on Stacked's BaseViewModel, so every
    //    generated view compiles against them with no new ViewModel surface.
    //  * NO retry button. It would have to call `viewModel.refresh`, which only
    //    tplVmHomeBase declares — the generic VM templates have no such method,
    //    so emitting one here would produce a view that does not compile. The
    //    blueprint/scaffold generators emit view+ViewModel as a pair and DO get
    //    a retry; this path emits the view alone and therefore cannot.
    //  * NO empty state. Nothing here binds a collection, and a generated
    //    `isEmpty` branch over nothing can only ever pass.
    final busyGate = snake == 'splash'
        ? ''
        : '    if (viewModel.isBusy) {\n'
            '      return const AdaptiveScaffold($scaffoldBg body: SizedBox.shrink());\n'
            '    }\n'
            '    if (viewModel.hasError) {\n'
            '      return const AdaptiveScaffold($scaffoldBg body: Center(\n'
            "        child: Text('Something went wrong loading this screen.'),\n"
            '      ));\n'
            '    }\n';
    String ready = '';
    if (startup != null && startup.isNotEmpty) {
      ready = '\n  @override\n  void onViewModelReady($name viewModel)'
          ' => viewModel.$startup();\n';
    }
    final pkgs = <String>[
      "import 'package:flutter/material.dart';",
      "import 'package:stacked/stacked.dart';",
    ];
    if (overlayOpen.isNotEmpty) {
      pkgs.add("import 'package:flutter/services.dart';");
    }
    if (body.contains('Shad')) {
      pkgs.add("import 'package:shadcn_ui/shadcn_ui.dart';");
    }
    if (body.contains('SvgPicture')) {
      pkgs.add("import 'package:flutter_svg/flutter_svg.dart';");
    }
    if (body.contains('GlassEntrance(')) {
      pkgs.add("import 'package:native_liquid_glass/native_liquid_glass.dart';");
    }
    final rels = <String>[
      "import '../app_tokens.dart';",
      "import '../ui/primitives.dart';",
      "import '${snake}_viewmodel.dart';",
    ];
    if (body.contains('SplashProgress') || body.contains('RiseIn(')) {
      rels.add("import 'motion.dart';");
    }
    if (model) {
      rels.add("import '../domain/ports/session_repository.dart';");
    }
    pkgs.sort();
    rels.sort();
    final importsStr = [...pkgs, '', ...rels].join('\n');
    var out = genericHead(
      imports: importsStr,
      name: name,
      body: body,
      ready: ready,
      busyGate: busyGate,
      scaffoldBg: scaffoldBg,
      ctorArgs: ctorArgs,
      fields: fields,
      modelLocal: modelLocal,
      vmArgs: vmArgs,
      overlayOpen: overlayOpen,
      overlayClose: overlayClose,
    );
    if (needsFmtSec) out += fmtSecHelper;
    return out;
  }

  // ── timer VM base (needs resolveValue) ──

  String tplVmBase(String name, String snake, Node timerSpec) {
    final init = resolveValue(timerSpec['init']?.toString() ?? '') ?? '0';
    final initWorkout = init.replaceAll('s.', 'workout.');
    final value = timerSpec['value']?.toString() ?? 'remaining';
    final running = timerSpec['running']?.toString() ?? 'running';
    return '// AUTO-GENERATED by flutter_crew (generate_view.py) — the $name countdown state\n'
        '// machine. Regenerated every run; do NOT hand-edit. ${name}ViewModel extends this and\n'
        '// IS the hand-editable extension point. Pattern detected by capture_data (ticker +\n'
        '// `$running` + `$value`<-record field).\n'
        "import 'dart:async';\n\n"
        "import 'package:stacked/stacked.dart';\n\n"
        "import '../domain/ports/session_repository.dart';\n\n"
        'abstract class ${name}ViewModelBase extends BaseViewModel {\n'
        '  ${name}ViewModelBase(this.workout);\n'
        '  final Session workout;\n\n'
        '  late int $value = $initWorkout;  // initial = the record\'s target/duration\n'
        '  bool $running = false;\n'
        '  Timer? _ticker;\n\n'
        '  void start() {\n'
        '    if ($running) return;\n'
        '    $running = true;\n'
        '    notifyListeners();\n'
        '    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {\n'
        '      if ($value <= 0) {\n'
        '        pause();\n'
        '        return;\n'
        '      }\n'
        '      $value -= 1;\n'
        '      notifyListeners();\n'
        '    });\n'
        '  }\n\n'
        '  void pause() {\n'
        '    $running = false;\n'
        '    _ticker?.cancel();\n'
        '    notifyListeners();\n'
        '  }\n\n'
        '  void toggle() => $running ? pause() : start();\n\n'
        '  void reset() {\n'
        '    pause();\n'
        '    $value = $initWorkout;\n'
        '    notifyListeners();\n'
        '  }\n\n'
        '  // Workout complete: the timer ran down to 0 and is no longer running. Drives the\n'
        '  // post-completion FeedbackSheet overlay (the design\'s `useFeedback(done)` → sheet\n'
        '  // opens 700ms after done). Derived — no separate `done` field to keep in sync.\n'
        '  bool get done => !$running && $value <= 0;\n\n'
        '  @override\n'
        '  void dispose() {\n'
        '    _ticker?.cancel();\n'
        '    super.dispose();\n'
        '  }\n'
        '}\n';
  }

  // ── main entry: build_view ──

  String buildView(Node spec,
      {String? screenId,
      String? startup,
      Node? render,
      List<Node>? interactions,
      Node? state}) {
    rowWUnbounded = false;
    needsFmtSec = false;
    overlay = '';
    formVm = false;
    authFieldType = 'text';
    this.state = <String, dynamic>{};
    timer = null;
    if (state != null) {
      final derived = state['_derived'];
      state.forEach((k, v) {
        if (k != '_derived' && k != '_timer') this.state[k] = v;
      });
      if (derived is Node) {
        derived.forEach((k, v) => this.state[k] = v);
      }
      timer = state['_timer'] is Node ? state['_timer'] as Node : null;
    }
    tokens = spec['tokens'] is Node ? spec['tokens'] as Node : <String, dynamic>{};
    if (spec['aliasHexMap'] is Map) {
      hex2tok = {...hex2tok, ...(spec['aliasHexMap'] as Map).cast<String, String>()};
    }
    if (spec['bindMap'] is Map) {
      bind = {...bind, ...(spec['bindMap'] as Map).cast<String, String>()};
    }
    this.render = render ?? <String, dynamic>{'fidelity': 'native', 'overrides': <String, dynamic>{}};
    glassEntrance = null;
    final rd = spec['riseDurMs'];
    if (rd is num && rd > 0) {
      glassEntrance = designToGlass(<String, dynamic>{
        'delayMs': 0,
        'durMs': rd,
        'curve': spec['riseCurve'] is List ? spec['riseCurve'] : [0.215, 0.61, 0.355, 1.0],
        'dy': spec['riseDy'] ?? 0,
      });
    }
    final sid = screenId != null
        ? snakeCase(screenId)
        : snakeCase((spec['entry'] ?? 'home').toString().replaceFirst(RegExp(r'View$'), ''));
    if (sid == 'home' || spec['entry'] == 'Home') {
      applyBox = false;
      handlers = <Node>[];
      final edges = interactions ?? <Node>[];
      Node? avatar;
      Node? card;
      for (final e in edges) {
        final sel = (e['selector'] as Map?)?.cast<String, dynamic>() ?? {};
        if (avatar == null && sel['class'] == 'avatar' && e['target'] != null) {
          avatar = e;
        }
        if (card == null &&
            sel['component'] == 'WorkoutCard' &&
            e['kind'] == 'nav') {
          card = e;
        }
      }
      final parts = <String>[
        headTpl,
        headerSrc(avatar != null ? navCall(avatar) : null),
        '',
        statsDeckMethod(spec),
        '',
        filterRowMethod(spec),
        '',
        sessionCardMethod(spec, card != null ? navCall(card) : null),
        tailTpl,
      ];
      var out = wireNavImports(parts.join('\n'));
      assertContentParity(spec, out);
      assertNoDegenerateBox(out);
      return out;
    } else {
      applyBox = true;
      handlers = interactions ?? <Node>[];
      var out = wireNavImports(genericView(spec, sid, startup: startup));
      assertContentParity(spec, out);
      assertNoDegenerateBox(out);
      return out;
    }
  }
}

// ──────────── entry point ────────────

/// Read the composition spec at [specPath], translate it to a Flutter view, and
/// write the Dart source to [outPath]. When [tokensPath] is given, the design's
/// token alias hex→name map (transform_tokens.aliasHexMap) augments the resolver
/// so the builder carries zero design-specific hex literals. Returns 0 on
/// success, 1 on failure (bad spec, a gate failure, or a write error).
int generateView(String specPath, String outPath, {String? tokensPath}) {
  Node spec;
  try {
    final decoded = jsonDecode(File(specPath).readAsStringSync());
    if (decoded is! Node) {
      stderr.writeln('generate_view: $specPath is not a JSON object');
      return 1;
    }
    spec = decoded;
  } catch (e) {
    stderr.writeln('generate_view: failed to read/parse $specPath — $e');
    return 1;
  }
  if (tokensPath != null) {
    spec['aliasHexMap'] = aliasHexMap(tokensPath);
  }
  String out;
  try {
    out = GenerateView().buildView(spec);
  } on GateFailure catch (e) {
    stderr.writeln('generate_view: ${e.message}');
    return 1;
  } catch (e) {
    stderr.writeln('generate_view: build failed — $e');
    return 1;
  }
  try {
    final outFile = File(outPath);
    if (p.dirname(outPath).isNotEmpty) {
      outFile.parent.createSync(recursive: true);
    }
    outFile.writeAsStringSync(out);
  } catch (e) {
    stderr.writeln('generate_view: failed to write $outPath — $e');
    return 1;
  }
  stdout.writeln('generated ${out.split('\n').length} lines → $outPath');
  return 0;
}
