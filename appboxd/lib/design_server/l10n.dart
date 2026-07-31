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
