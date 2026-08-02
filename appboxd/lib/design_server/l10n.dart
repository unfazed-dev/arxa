// L10n primitives shared by the designer tools — ported from
// skills/appbox-designer/runtime/lib/l10n.mjs.
//
// THIS task (19) ports only the two pieces pseudolocalize needs: the ICU
// plural brace-walker (`parsePlural`) and the comment-tolerant ARB parse
// (`parseArb`). Task 20 extends this file with the full createT/resolveLocale
// port for the Dart design server.

import 'dart:convert';
import 'dart:io';

/// `{count, plural, =0{…} one{…} other{…}}` → varName + option bodies.
///
/// Ported rule-for-rule from l10n.mjs's `parsePlural`. Option bodies may nest
/// one level of `{var}` placeholders — braces are balanced by walking, not by
/// regex. Returns null for non-plural values.
class Plural {
  final String varName;
  final Map<String, String> options;
  Plural(this.varName, this.options);
}

Plural? parsePlural(String str) {
  final head = RegExp(r'^\{\s*(\w+)\s*,\s*plural\s*,\s*').firstMatch(str);
  if (head == null || !str.endsWith('}')) return null;
  final options = <String, String>{};
  var i = head.end;
  final last = str.length - 1; // index of the closing '}'
  while (i < last) {
    while (i < str.length && str[i] == ' ') {
      i++;
    }
    final kw = RegExp(r'^(=\d+|zero|one|two|few|many|other)\s*\{')
        .firstMatch(str.substring(i));
    if (kw == null) return null;
    final kwFull = kw.group(0)!;
    final kwStr = kw.group(1)!;
    var depth = 1;
    var j = i + kwFull.length; // absolute index just past '{'
    final bodyStart = j;
    while (j < str.length && depth > 0) {
      if (str[j] == '{') {
        depth++;
      } else if (str[j] == '}') {
        depth--;
      }
      if (depth > 0) j++;
    }
    if (depth != 0) return null;
    options[kwStr] = str.substring(bodyStart, j);
    i = j + 1;
  }
  return Plural(head.group(1)!, options);
}

/// ARB files may carry `//` comment lines — strip them before JSON.parse.
/// Ported from l10n.mjs's `parseArb`.
Map<String, dynamic> parseArb(String file) {
  final text = File(file).readAsStringSync();
  final stripped = text
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  return (jsonDecode(stripped) as Map).cast<String, dynamic>();
}

/// A Dart-side `t()` for the design server's own error surface (task #46).
///
/// WHY THIS IS NOT THE WORKER'S `t()`. The worker owns translation for every
/// rendered page — but the error surface exists precisely for the case where a
/// request could not be served, and the thing that failed may BE the worker.
/// Routing the "something went wrong" copy through the component that just went
/// wrong is how you get an error page that itself 500s. So this reads the ARB
/// files straight off disk, shares no state with the tab, and cannot be taken
/// down by it.
///
/// Two deliberate differences from the worker's `t()`:
///
///  * A miss returns the caller's authored English [fallback], not the key.
///    `t()` in a template rendering `nav.home` can afford to show "nav.home";
///    an error page showing "errorSurface.serverError" to a user is a second
///    failure on top of the first.
///  * `{var}` substitution only — no ICU plural walk. The five error strings
///    have no plurals, and a parser that is never exercised is a parser that is
///    silently broken when it finally is.
///
/// ponytail: no cache. An error surface renders on failures, not in a loop, so
/// re-reading three small files costs nothing and cannot go stale against a
/// hot-reloaded ARB. Add one only if error rendering ever lands on a hot path.
class ErrorCatalog {
  /// [l10nDirs] in precedence order, LAST wins — same rule the worker's
  /// prefetch uses (a project's catalog overrides the artifact's).
  ErrorCatalog(this.l10nDirs);
  final List<String> l10nDirs;

  String? _lookup(String locale, String key) {
    String? hit;
    for (final dir in l10nDirs) {
      final f = File('$dir/app_$locale.arb');
      if (!f.existsSync()) continue;
      try {
        final v = parseArb(f.path)[key];
        if (v is String && v.isNotEmpty) hit = v;
      } catch (_) {
        // A malformed catalog must not turn a 404 into a crash. Skip it; the
        // English fallback below still produces a real sentence.
      }
    }
    return hit;
  }

  /// [fallback] is the authored English the caller would have shown anyway, so
  /// the worst case of a missing/broken catalog is today's behaviour exactly.
  String t(String locale, String key, String fallback,
      [Map<String, String> vars = const {}]) {
    var out = _lookup(locale, key) ?? _lookup('en', key) ?? fallback;
    vars.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }
}
