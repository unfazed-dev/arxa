// transform_tokens — Dart port of tools/vendor/stages/transform_tokens.py.
//
// W3C DTCG tokens.json → per-platform token files:
//   Dart:   <out>/dart/app_tokens.dart   (Color / double / String / List<double>)
//   Swift:  <out>/ios/AppTokens.swift     (UIColor / CGFloat)
//   XML:    <out>/android/tokens.xml      (<color> / <dimen> resources)
//
// Deterministic: same tokens.json → same files. Pure Dart
// (dart:convert, dart:io, package:path only).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// ──────────── identifier helpers ────────────

/// Split on non-alphanumeric runs, lowercase the head, Capitalize the rest.
/// Matches Python: re.split(r"[^0-9a-zA-Z]+", s) + str.lower / str.capitalize.
String camel(String s) {
  final parts = s
      .split(RegExp(r'[^0-9a-zA-Z]+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'token';
  var first = parts[0];
  final lead = RegExp(r'^[^a-zA-Z]+').stringMatch(first);
  if (lead != null) first = first.substring(lead.length);
  if (first.isEmpty) first = 't';
  final buf = StringBuffer(first.toLowerCase());
  for (var i = 1; i < parts.length; i++) {
    buf.write(_pyCapitalize(parts[i]));
  }
  return buf.toString();
}

/// Python str.capitalize(): first char uppercased, rest lowercased.
String _pyCapitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

bool _isAlphaCode(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
bool _isAlphaNumCode(int c) =>
    (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

/// Identifier for a token. A leaf that starts with a letter is used as-is
/// (legacy contract: color.accent → accent, NOT colorAccent). A numeric or
/// symbol leaf is namespaced under the nearest alpha group (brand+0 → brand0;
/// symbol-only → group alone). Always yields a valid identifier.
String tokenName(List<String> groupPath, String key) {
  if (key.isNotEmpty && _isAlphaCode(key.codeUnitAt(0))) {
    return camel(key);
  }
  final suffix = StringBuffer();
  for (final c in key.codeUnits) {
    if (_isAlphaNumCode(c)) suffix.writeCharCode(c);
  }
  final suffixStr = suffix.toString();
  for (var i = groupPath.length - 1; i >= 0; i--) {
    final g = camel(groupPath[i]);
    if (g.isNotEmpty && _isAlphaCode(g.codeUnitAt(0))) {
      return g + suffixStr;
    }
  }
  return suffixStr.isEmpty ? 'token0' : 'token$suffixStr';
}

// ──────────── color parsing ────────────

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);
double _clamp255d(double v) => v < 0 ? 0.0 : (v > 255 ? 255.0 : v);
double _clamp01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);

/// Python's round() is round-half-to-even (banker's rounding); Dart's
/// num.round() is round-half-away-from-zero. They only diverge on exact .5.
int _pyRound(double x) {
  final away = x.round();
  if ((x - away).abs() != 0.5) return away;
  if (away.isEven) return away;
  return x >= 0 ? away - 1 : away + 1;
}

/// Parse a CSS color to [r, g, b, a] (0–255 ints, clamped), or null.
///
/// Handles #rgb, #rrggbb, #aarrggbb (alpha first), rgb(), rgba(). rgba()
/// alpha is CSS-spec 0–1 (clamped before ×255 so rgba(...,255) → opaque,
/// not 65025). rgb channels clamped to [0,255].
List<int>? parseColor(String v) {
  v = v.trim();
  if (v.startsWith('#')) {
    var h = v.substring(1);
    if (h.length == 3) {
      h = h.split('').map((c) => c + c).join();
    }
    if (h.length == 6) {
      h = 'FF$h';
    }
    if (h.length != 8) return null;
    int a, r, g, b;
    try {
      a = int.parse(h.substring(0, 2), radix: 16);
      r = int.parse(h.substring(2, 4), radix: 16);
      g = int.parse(h.substring(4, 6), radix: 16);
      b = int.parse(h.substring(6, 8), radix: 16);
    } on FormatException {
      return null;
    }
    return [_clamp255(r), _clamp255(g), _clamp255(b), _clamp255(a)];
  }
  final m = RegExp(r'^rgba?\(([^)]+)\)').firstMatch(v);
  if (m != null) {
    final parts = m.group(1)!.split(',').map((s) => s.trim()).toList();
    if (parts.length < 3) return null;
    try {
      final r = _clamp255d(double.parse(parts[0]));
      final g = _clamp255d(double.parse(parts[1]));
      final b = _clamp255d(double.parse(parts[2]));
      var a = 255.0;
      if (parts.length > 3) {
        a = _clamp01(double.parse(parts[3])) * 255;
      }
      return [_pyRound(r), _pyRound(g), _pyRound(b), _pyRound(a)];
    } on FormatException {
      return null;
    }
  }
  return null;
}

String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

bool _isHexCode(int c) =>
    (c >= 48 && c <= 57) || // 0-9
    (c >= 65 && c <= 70) || // A-F
    (c >= 97 && c <= 102); // a-f

/// A color $value → 6-digit UPPERCASE hex (#1A1714), or null. Accepts #rgb,
/// #rrggbb, #aarrggbb (alpha discarded — a token-level tint).
String? _normHex(dynamic val) {
  if (val is! String) return null;
  final v = val.trim();
  if (!v.startsWith('#')) return null;
  var h = v.substring(1);
  if (h.length == 3) {
    h = h.split('').map((c) => c + c).join();
  }
  if (h.length == 8) {
    h = h.substring(2); // drop alpha pair
  }
  if (h.length != 6) return null;
  for (final c in h.codeUnits) {
    if (!_isHexCode(c)) return null;
  }
  return '#${h.toUpperCase()}';
}

// ──────────── numeric helpers ────────────

/// Strip common CSS length units → pixels as a double, or null.
/// rem/em → ×16, pt → ×4/3, % → null (not a static length).
double? parseNum(String v) {
  v = v.trim();
  final m = RegExp(r'^(-?\d+(?:\.\d+)?)(px|rem|em|pt|%)?$').firstMatch(v);
  if (m == null) return null;
  var n = double.parse(m.group(1)!);
  final unit = m.group(2);
  if (unit == 'rem' || unit == 'em') {
    n *= 16;
  } else if (unit == 'pt') {
    n *= 4 / 3;
  } else if (unit == '%') {
    return null;
  }
  return n;
}

double? _toFloat(dynamic x) {
  if (x is num) return x.toDouble();
  if (x is String) return double.tryParse(x);
  return null;
}

/// A cubic-bezier control-point list from either DTCG $value form:
/// the CSS string "cubic-bezier(0.2, 0.85, 0.2, 1)" or the W3C list
/// [0.2, 0.85, 0.2, 1.0]. The list form requires exactly 4 elements.
List<double>? bezierVals(dynamic v) {
  if (v is List) {
    final pts = <double>[];
    for (final x in v) {
      final d = _toFloat(x);
      if (d == null) return null;
      pts.add(d);
    }
    return pts.length == 4 ? pts : null;
  }
  if (v is! String) return null;
  final m = RegExp(r'^cubic-bezier\(([^)]+)\)').firstMatch(v);
  if (m == null) return null;
  final pts = <double>[];
  for (final x in m.group(1)!.split(',')) {
    final d = double.tryParse(x.trim());
    if (d == null) return null;
    pts.add(d);
  }
  return pts; // string form: no length check (matches Python)
}

/// A control-point number as a double literal: 1.0 stays 1.0, 0.85 stays 0.85.
String _fmtNum(num x) {
  var s = x.toDouble().toStringAsFixed(6);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s.contains('.') ? s : '$s.0';
}

int _exp10(double x) {
  if (x == 0) return 0;
  var e = 0;
  var v = x.abs();
  while (v >= 10) {
    v /= 10;
    e++;
  }
  while (v < 1) {
    v *= 10;
    e--;
  }
  return e;
}

/// Python f"{x:g}" — 6 significant digits, trailing zeros stripped.
String _pyG(double x) {
  if (x == 0.0) return '0';
  if (x.isNaN) return 'nan';
  if (x.isInfinite) return x.isNegative ? '-inf' : 'inf';
  final exp = _exp10(x);
  String s;
  if (exp >= -4 && exp < 6) {
    s = x.toStringAsFixed(5 - exp);
  } else {
    // exponential — best-effort (token values never reach this branch).
    s = x.toStringAsExponential(5);
  }
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

// ──────────── token iteration ────────────

class _Token {
  final List<String> groupPath;
  final String key;
  final String type;
  final dynamic value;
  _Token(this.groupPath, this.key, this.type, this.value);
}

/// Yield (group_path, key, type, value) for every DTCG token (a node with
/// $type), recursing through groups of arbitrary depth.
List<_Token> _iterTokens(Map<String, dynamic> tree) {
  final out = <_Token>[];
  _iterInto(tree, <String>[], out);
  return out;
}

void _iterInto(
    Map<String, dynamic> tree, List<String> path, List<_Token> out) {
  for (final entry in tree.entries) {
    final key = entry.key;
    if (key.startsWith(r'$')) continue;
    final node = entry.value;
    if (node is! Map<String, dynamic>) continue;
    if (node.containsKey(r'$type')) {
      final t = node[r'$type'];
      final v = node.containsKey(r'$value') ? node[r'$value'] : '';
      out.add(_Token(path, key, t is String ? t : '', v));
    } else {
      _iterInto(node, [...path, key], out);
    }
  }
}

/// Resolve a dotted token path ('color.brand.0') to its $value, or null.
dynamic _resolveAliasRef(dynamic tree, String ref) {
  dynamic node = tree;
  for (final part in ref.split('.')) {
    if (node is! Map<String, dynamic> || !node.containsKey(part)) {
      return null;
    }
    node = node[part];
  }
  if (node is Map<String, dynamic>) {
    return node[r'$value'];
  }
  return node;
}

// ──────────── platform emitters ────────────

class _PlatformSpec {
  final List<String> header;
  final List<String> footer;
  final String indent;
  final String Function(String group) groupComment;
  _PlatformSpec(this.header, this.footer, this.indent, this.groupComment);
}

final Map<String, _PlatformSpec> _platforms = {
  'dart': _PlatformSpec(
    [
      '// AUTO-GENERATED by factory/stages/transform_tokens.py — do not edit.',
      '// The shared token layer (identical across platforms).',
      "import 'package:flutter/material.dart';",
      '',
      'abstract final class AppTokens {',
    ],
    ['}'],
    '  ',
    (g) => '  // $g',
  ),
  'swift': _PlatformSpec(
    [
      '// AUTO-GENERATED by factory/stages/transform_tokens.py — do not edit.',
      'import UIKit',
      '',
      'public enum AppTokens {',
    ],
    ['}'],
    '    ',
    (g) => '    // $g',
  ),
  'android': _PlatformSpec(
    [
      '<?xml version="1.0" encoding="utf-8"?>',
      '<!-- AUTO-GENERATED by factory/stages/transform_tokens.py -->',
      '<resources>',
    ],
    ['</resources>'],
    '    ',
    (g) => '    <!-- $g -->',
  ),
};

const _aliasExt = 'com.fluttercrew.aliases';
const _aliasExtLegacy = 'com.atlet.arxa.aliases';

/// Render one token's platform line, or null to skip.
String? _line(String spec, String indent, String name, String t, dynamic val) {
  if (t == 'color') {
    final c = val is String ? parseColor(val) : null;
    if (c == null) {
      final repr = val is String ? "'$val'" : '$val';
      return '$indent// ponytail: unparseable color $repr for $name';
    }
    final a = _hex2(c[3]);
    final r = _hex2(c[0]);
    final g = _hex2(c[1]);
    final b = _hex2(c[2]);
    if (spec == 'dart') {
      return '${indent}static const Color $name = Color(0x$a$r$g$b);';
    }
    if (spec == 'swift') {
      return '${indent}public static let $name = UIColor(red: '
          '${_pyG(c[0] / 255)}, green: ${_pyG(c[1] / 255)}, '
          'blue: ${_pyG(c[2] / 255)}, alpha: ${_pyG(c[3] / 255)})';
    }
    return '$indent<color name="$name">#$a$r$g$b</color>';
  }
  if (t == 'dimension' || t == 'number') {
    final n = val is String ? parseNum(val) : null;
    if (n == null) return null;
    if (spec == 'dart') return '${indent}static const double $name = ${_pyG(n)};';
    if (spec == 'swift') {
      return '${indent}public static let $name: CGFloat = ${_pyG(n)}';
    }
    return '$indent<dimen name="$name">${_pyG(n)}dp</dimen>';
  }
  if (t == 'fontFamily') {
    final v = val is String ? val : '';
    if (spec == 'dart') {
      return '${indent}static const String ${name}Family = ${jsonEncode(v)};';
    }
    if (spec == 'swift') {
      return '${indent}public static let ${name}Family = ${jsonEncode(v)}';
    }
    return '$indent<!-- ponytail: fontFamily $name = $v (bind via res/font/) -->';
  }
  if (t == 'cubicBezier') {
    List<double>? bv = bezierVals(val);
    if (bv == null && val == 'ease-in-out') {
      bv = [0.4, 0.0, 0.2, 1.0];
    }
    if (bv == null) return null;
    final pts = bv.map(_fmtNum).join(', ');
    if (spec == 'dart') {
      return '${indent}static const List<double> $name = [$pts];';
    }
    if (spec == 'swift') {
      return '${indent}public static let $name: [CGFloat] = [$pts]';
    }
    return '$indent<!-- ponytail: cubicBezier $name = [$pts] (apply via Animator) -->';
  }
  if (t == 'shadow') {
    if (spec == 'dart') {
      return '$indent// ponytail: shadow token $name (apply via BoxDecoration)';
    }
    if (spec == 'swift') {
      return '$indent// ponytail: shadow token $name (apply via CALayer)';
    }
    return '$indent<!-- ponytail: shadow token $name (apply via elevation/shapeAppearance) -->';
  }
  return null;
}

/// The canonical baseline vocabulary the shared primitives library hardcodes.
/// Guarantees these compile even when a design defines no tokens for them.
final Map<String, String> _canonBaseline = {
  'accent': '#3F51B5',
  'accent2': '#303F9F',
  'accentSoft': '#1A3F51B5',
  'paper': '#FFFBFE',
  'bone': '#F5F0E8',
  'bone2': '#EAE3D6',
  'bone3': '#DDD3C0',
  'ink': '#1C1B1F',
  'ink2': '#3A3530',
  'ink3': '#6E6760',
  'ink4': '#9E9E9E',
  'rule': '#CAC4D0',
  'danger': '#B3261E',
  'color24': '#FFFFFF',
};

String _emit(Map<String, dynamic> tree, String specKey) {
  final s = _platforms[specKey]!;
  final lines = <String>[...s.header];
  String? curGroup;
  for (final tok in _iterTokens(tree)) {
    final glabel = tok.groupPath.isNotEmpty ? tok.groupPath.join('.') : 'tokens';
    if (glabel != curGroup) {
      lines.add(s.groupComment(glabel));
      curGroup = glabel;
    }
    final name = tokenName(tok.groupPath, tok.key);
    final line = _line(specKey, s.indent, name, tok.type, tok.value);
    if (line != null) lines.add(line);
  }
  // canonical-alias layer
  final aliasLines = _emitAliases(tree, specKey);
  if (aliasLines.isNotEmpty) {
    lines.add(s.groupComment('arxa.aliases'));
    lines.addAll(aliasLines);
  }
  // canonical-baseline layer
  final existing = <String>{};
  for (final tok in _iterTokens(tree)) {
    existing.add(tokenName(tok.groupPath, tok.key));
  }
  final ext = tree[r'$extensions'];
  final extMap = ext is Map<String, dynamic> ? ext : <String, dynamic>{};
  final aliasRaw = extMap[_aliasExt] ?? extMap[_aliasExtLegacy];
  final aliasBlock =
      aliasRaw is Map<String, dynamic> ? aliasRaw : <String, dynamic>{};
  existing.addAll(aliasBlock.keys);
  final baseLines = <String>[];
  for (final entry in _canonBaseline.entries) {
    if (!existing.contains(entry.key)) {
      final l = _line(specKey, s.indent, entry.key, 'color', entry.value);
      if (l != null) baseLines.add(l);
    }
  }
  if (baseLines.isNotEmpty) {
    lines.add(s.groupComment('arxa.baseline'));
    lines.addAll(baseLines);
  }
  lines.addAll(s.footer);
  return '${lines.join('\n')}\n';
}

/// Emit the canonical-alias Color lines. Each alias resolves to a hex via
/// $ref (preferred) or literal $value. Skipped if it can't resolve or
/// collides with an existing semantic token name.
List<String> _emitAliases(Map<String, dynamic> tree, String specKey) {
  final s = _platforms[specKey]!;
  final ext = tree[r'$extensions'];
  final extMap = ext is Map<String, dynamic> ? ext : <String, dynamic>{};
  final aliasRaw = extMap[_aliasExt] ?? extMap[_aliasExtLegacy];
  final aliases =
      aliasRaw is Map<String, dynamic> ? aliasRaw : <String, dynamic>{};
  if (aliases.isEmpty) return [];
  final existing = <String>{};
  for (final tok in _iterTokens(tree)) {
    existing.add(tokenName(tok.groupPath, tok.key));
  }
  final out = <String>[];
  for (final entry in aliases.entries) {
    final name = entry.key;
    final spec = entry.value;
    if (spec is! Map<String, dynamic>) continue;
    if (existing.contains(name)) continue;
    dynamic raw;
    if (spec.containsKey(r'$ref')) {
      raw = _resolveAliasRef(tree, spec[r'$ref'] as String);
    }
    if (raw == null && spec.containsKey(r'$value')) {
      raw = spec[r'$value'];
    }
    if (raw == null) continue;
    final line = _line(specKey, s.indent, name, 'color', raw);
    if (line != null) out.add(line);
  }
  return out;
}

String emitDart(Map<String, dynamic> tree) => _emit(tree, 'dart');
String emitSwift(Map<String, dynamic> tree) => _emit(tree, 'swift');
String emitAndroid(Map<String, dynamic> tree) => _emit(tree, 'android');

// ──────────── alias hex map ────────────

/// The reverse of the alias layer: hex (UPPERCASE) → `AppTokens.<name>`.
///
/// Two sources unioned: (1) every color token's own name, (2) each alias
/// resolved to its hex. Alias wins on collision (those are the names the
/// builder actually references).
Map<String, String> aliasHexMapFromTree(Map<String, dynamic> tree) {
  final out = <String, String>{};
  // 1. semantic color leaves (floor — overridden by aliases on collision)
  for (final tok in _iterTokens(tree)) {
    if (tok.type != 'color') continue;
    final hexv = _normHex(tok.value);
    if (hexv != null) {
      out[hexv] = 'AppTokens.${tokenName(tok.groupPath, tok.key)}';
    }
  }
  // 2. alias block — WINS on collision
  final ext = tree[r'$extensions'];
  final extMap = ext is Map<String, dynamic> ? ext : <String, dynamic>{};
  final aliasRaw = extMap[_aliasExt] ?? extMap[_aliasExtLegacy];
  final aliases =
      aliasRaw is Map<String, dynamic> ? aliasRaw : <String, dynamic>{};
  for (final entry in aliases.entries) {
    final name = entry.key;
    final spec = entry.value;
    if (spec is! Map<String, dynamic>) continue;
    if (name.startsWith('_')) continue;
    dynamic raw;
    if (spec.containsKey(r'$ref')) {
      raw = _resolveAliasRef(tree, spec[r'$ref'] as String);
    }
    if (raw == null && spec.containsKey(r'$value')) {
      raw = spec[r'$value'];
    }
    final hexv = _normHex(raw);
    if (hexv != null) {
      out[hexv] = 'AppTokens.$name';
    }
  }
  return out;
}

/// The reverse hex→token-name map, reading tokens.json from [tokensPath].
/// Returns an empty map on read/parse failure.
Map<String, String> aliasHexMap(String tokensPath) {
  try {
    final decoded = jsonDecode(File(tokensPath).readAsStringSync());
    if (decoded is! Map<String, dynamic>) return {};
    return aliasHexMapFromTree(decoded);
  } catch (e) {
    return {};
  }
}

// ──────────── entry point ────────────

/// Transform W3C DTCG tokens.json → per-platform token files under [outDir].
/// Returns 0 on success, 1 on failure.
int transformTokens(String tokensPath, String outDir) {
  Map<String, dynamic> tree;
  try {
    final decoded = jsonDecode(File(tokensPath).readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('transform_tokens: $tokensPath is not a JSON object');
      return 1;
    }
    tree = decoded;
  } catch (e) {
    stderr.writeln('transform_tokens: failed to read/parse $tokensPath — $e');
    return 1;
  }
  try {
    Directory(p.join(outDir, 'dart')).createSync(recursive: true);
    Directory(p.join(outDir, 'ios')).createSync(recursive: true);
    Directory(p.join(outDir, 'android')).createSync(recursive: true);
    File(p.join(outDir, 'dart', 'app_tokens.dart'))
        .writeAsStringSync(emitDart(tree));
    File(p.join(outDir, 'ios', 'AppTokens.swift'))
        .writeAsStringSync(emitSwift(tree));
    File(p.join(outDir, 'android', 'tokens.xml'))
        .writeAsStringSync(emitAndroid(tree));
  } catch (e) {
    stderr.writeln('transform_tokens: failed to write output — $e');
    return 1;
  }
  stdout.writeln(
      'wrote dart/app_tokens.dart, ios/AppTokens.swift, android/tokens.xml → $outDir');
  return 0;
}
