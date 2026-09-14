/// The Draft Overlay — Design Mode's auto-saved, server-side patch set
/// (locked amendment 2026-08-23, decision 5): the Author's uncommitted
/// edits, persisted per artifact, overlaid on served pages, and NEVER
/// touching artifact source — touching source is what the studio-socket
/// commit (decision 2) is for.
///
/// ⚠ SUPERSEDED 2026-09-11 (the grilled edit redesign — see
/// docs/plans/arxa-dial-palettes.md "Addendum — the edit redesign"):
/// decisions 5 and 11 are OVERTURNED. The live overlay is a Supabase row
/// (`arxa_dial_overlays`) applied CLIENT-SIDE by every dial; the file
/// store, serve-time injection, and the studio-commit socket are deleted
/// from the product. What survives in THIS file is the pure patch model
/// (DraftPatch/Json + patchAllRendered application) — the eject bake and
/// the rendered-patch tests still ride it. DraftFileStore is gone.
///
/// Storage: one JSON file per artifact under ~/.arxa/drafts/, keyed by
/// the artifact's absolute path (a moved checkout starts a fresh draft —
/// drafts are WIP by nature; commit makes them permanent). Deliberately
/// NOT inside the artifact dir: the file watcher hot-reloads on artifact
/// writes, and an auto-save that reloaded the page on every keystroke
/// would fight the Author it exists for.
///
/// Application rides patchAllRendered (design_patch.dart): the same
/// structured-patch law as source commits, but every loop-rendered
/// instance of a shared id is patched — "every row at once". A patch
/// whose id no longer renders is STALE, not lost: it stays in the draft
/// (the Orphaned Pin doctrine applied to edits) and is reported so the
/// island can say so.
library;

import 'design_patch.dart' show PatchEdits, patchAllRendered;

/// Validation caps. Loose enough never to bite real design work, tight
/// enough that a pasted stylesheet or a hostile blob cannot sit in the
/// overlay. Exceeded or malformed input is a FormatException — the API
/// layer turns that into a 400.
abstract class DraftCaps {
  static const patches = 128;
  static const tokens = 64;
  static const name = 80;
  static const value = 300;
  static const text = 4000;
  static const page = 200;
}

/// Attribute/property names: dashed css, data-*, aria-*, namespaced svg.
final _nameRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9:_-]{0,79}$');
final _tokenRe = RegExp(r'^--[a-zA-Z0-9-]{1,78}$');

/// The authored-semantic layer opens with this prefix: a patch key of
/// `el:<data-el>` binds to the data-el, everything else to data-arxa-id.
/// data-el values allow the inspect vocabulary's charset (letters, digits,
/// colon, dash, underscore — e.g. 'text:®' is NOT one; those are authored
/// inline, never selected).
const elKeyPrefix = 'el:';
final _dataElRe = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9:_-]{0,99}$');

/// The data-el half of an el:-prefixed patch key, or null for machine-id
/// keys. Exported for the commit socket's op shaping.
final _pageRe = RegExp(r'^[/A-Za-z0-9._~%-]*$');

/// Locale targeting: exactly one ISO-639-1 short code, captured by the dial
/// from `<html lang>` or the leading pathname segment.
final _localeRe = RegExp(r'^[a-z]{2}$');
String? elKeyOf(String patchKey) {
  if (!patchKey.startsWith(elKeyPrefix)) return null;
  final v = patchKey.substring(elKeyPrefix.length);
  return _dataElRe.hasMatch(v) ? v : null;
}

/// One element's overlay edits — the Draft Overlay's spelling of
/// [PatchEdits]. A null style/attr value REMOVES, matching the grammar.
class DraftPatch {
  final Map<String, String?> style;
  final Map<String, String?> attrs;
  final String? text;

  /// Seed-route provenance (2026-08-24), captured by the dial on the FIRST
  /// text edit of a key: [was] is the edited instance's pre-edit rendered
  /// text — the value anchor resolved against the seed SSOT at commit; [nth]
  /// the 0-based index among the page's instances of this key, recorded only
  /// when those instances' texts diverge (data-backed rows; homogeneous
  /// repeats keep every-row semantics); [page] the editing page's pathname
  /// for slug/href correlation; [locale] the locale being edited
  /// (`<html lang>`, else the leading `/xx/` pathname segment) so the commit writes
  /// ONLY that locale's SSOT slice instead of stamping one language's text
  /// over every locale. Style edits never carry any of them.
  final String? was;
  final int? nth;
  final String? page;
  final String? locale;

  /// Instance-scoped ATTR edits (2026-08-26): attr name -> 0-based index
  /// among the page's instances of this key, recorded by the dial when
  /// those instances DIVERGE on that attr (every data-el="media-source"
  /// image has its own src — an every-row apply rewrote all of them on
  /// one pick). The overlay touches ONLY that occurrence — the attr twin
  /// of [nth]. Attrs absent from this map stay every-row.
  final Map<String, int>? attrsNth;

  const DraftPatch(
      {this.style = const {},
      this.attrs = const {},
      this.text,
      this.was,
      this.nth,
      this.page,
      this.locale,
      this.attrsNth});

  bool get isEmpty => style.isEmpty && attrs.isEmpty && text == null;

  PatchEdits toPatchEdits() =>
      PatchEdits(attrs: attrs, style: style, text: text);

  Map<String, dynamic> toJson() => {
        if (style.isNotEmpty) 'style': style,
        if (attrs.isNotEmpty) 'attrs': attrs,
        if (text != null) 'text': text,
        if (was != null) 'was': was,
        if (nth != null) 'nth': nth,
        if (page != null) 'page': page,
        if (locale != null) 'locale': locale,
        if (attrsNth != null && attrsNth!.isNotEmpty) 'attrsNth': attrsNth,
      };

  static Map<String, String?> _edits(Object? raw, String id, String what) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw FormatException('patch "$id"."$what" must be an object');
    }
    final out = <String, String?>{};
    for (final e in raw.entries) {
      final k = '${e.key}';
      if (!_nameRe.hasMatch(k)) {
        throw FormatException('patch "$id"."$what": bad name "$k"');
      }
      final v = e.value;
      if (v == null) {
        out[k] = null; // removal
        continue;
      }
      final s = '$v';
      if (s.length > DraftCaps.value) {
        throw FormatException(
            'patch "$id"."$what": value over ${DraftCaps.value} chars');
      }
      // A double quote would break out of the re-quoted attribute;
      // braces are declaration-block syntax, never a single value.
      if (s.contains('"') || s.contains('{') || s.contains('}')) {
        throw FormatException(
            'patch "$id"."$what": value must not contain " { }');
      }
      out[k] = s;
    }
    return out;
  }

  static DraftPatch fromJson(Object? raw, String id) {
    if (raw is! Map) {
      throw FormatException('patch "$id" must be an object');
    }
    final t = raw['text'];
    final text = t == null ? null : '$t';
    if (text != null && text.length > DraftCaps.text) {
      throw FormatException(
          'patch "$id".text over ${DraftCaps.text} chars');
    }
    var was = raw['was'] == null ? null : '${raw['was']}';
    if (was != null && was.length > DraftCaps.text) {
      throw FormatException(
          'patch "$id".was over ${DraftCaps.text} chars');
    }
    int? nth;
    if (raw['nth'] != null) {
      final n = raw['nth'];
      if (n is! int || n < 0 || n > 9999) {
        throw FormatException('patch "$id".nth must be a 0..9999 index');
      }
      nth = n;
    }
    var page = raw['page'] == null ? null : '${raw['page']}';
    if (page != null &&
        (page.length > DraftCaps.page || !_pageRe.hasMatch(page))) {
      throw FormatException('patch "$id".page is not a plain pathname');
    }
    var locale = raw['locale'] == null ? null : '${raw['locale']}';
    if (locale != null && !_localeRe.hasMatch(locale)) {
      throw FormatException(
          'patch "$id".locale must be a two-letter code');
    }
    Map<String, int>? attrsNth;
    if (raw['attrsNth'] != null) {
      final rawNth = raw['attrsNth'];
      if (rawNth is! Map) {
        throw FormatException('patch "$id".attrsNth must be an object');
      }
      final out = <String, int>{};
      for (final e in rawNth.entries) {
        final k = '${e.key}';
        if (!_nameRe.hasMatch(k)) {
          throw FormatException('patch "$id".attrsNth: bad name "$k"');
        }
        final n = e.value;
        if (n is! int || n < 0 || n > 9999) {
          throw FormatException(
              'patch "$id".attrsNth."$k" must be a 0..9999 index');
        }
        out[k] = n;
      }
      attrsNth = out.isEmpty ? null : out;
    }
    return DraftPatch(
      style: _edits(raw['style'], id, 'style'),
      attrs: _edits(raw['attrs'], id, 'attrs'),
      text: text,
      was: was,
      nth: nth,
      page: page,
      locale: locale,
      attrsNth: attrsNth,
    );
  }
}

/// The outcome of overlaying one draft onto one served page.
class DraftApplyResult {
  /// The page with the overlay applied (identical to the input when the
  /// draft is empty or nothing matched).
  final String html;

  /// How many element instances were patched (loop-shared ids count each).
  final int applied;

  /// Patch ids no element in the page carries — kept in the draft, never
  /// silently dropped (the Orphaned Pin doctrine, applied to edits).
  final List<String> stale;

  /// Edits the grammar refused (e.g. text on nested markup), human-read.
  final List<String> refused;

  const DraftApplyResult(this.html,
      {this.applied = 0, this.stale = const [], this.refused = const []});
}

/// One artifact's Draft Overlay: global token overrides plus per-element
/// patches keyed by `data-arxa-id`.
class DraftOverlay {
  DraftOverlay({
    required this.artifact,
    String? updatedAt,
    Map<String, String>? tokens,
    Map<String, DraftPatch>? patches,
  })  : updatedAt = updatedAt ?? DateTime.now().toUtc().toIso8601String(),
        tokens = tokens ?? {},
        patches = patches ?? {};

  static const version = 1;

  final String artifact;
  String updatedAt;
  final Map<String, String> tokens;
  final Map<String, DraftPatch> patches;

  bool get isEmpty => tokens.isEmpty && patches.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': version,
        'artifact': artifact,
        'updatedAt': updatedAt,
        if (tokens.isNotEmpty) 'tokens': tokens,
        if (patches.isNotEmpty)
          'patches': {for (final e in patches.entries) e.key: e.value.toJson()},
      };

  static DraftOverlay fromJson(Object? raw, {required String artifact}) {
    if (raw is! Map) {
      throw const FormatException('draft must be an object');
    }
    final tokens = <String, String>{};
    final rawTokens = raw['tokens'];
    if (rawTokens != null) {
      if (rawTokens is! Map) {
        throw const FormatException('draft.tokens must be an object');
      }
      if (rawTokens.length > DraftCaps.tokens) {
        throw FormatException('draft holds over ${DraftCaps.tokens} tokens');
      }
      for (final e in rawTokens.entries) {
        final k = '${e.key}';
        if (!_tokenRe.hasMatch(k)) {
          throw FormatException('bad token name "$k"');
        }
        final v = '${e.value}';
        if (v.length > DraftCaps.value || v.contains('<')) {
          throw FormatException('bad value for token "$k"');
        }
        tokens[k] = v;
      }
    }
    final patches = <String, DraftPatch>{};
    final rawPatches = raw['patches'];
    if (rawPatches != null) {
      if (rawPatches is! Map) {
        throw const FormatException('draft.patches must be an object');
      }
      if (rawPatches.length > DraftCaps.patches) {
        throw FormatException(
            'draft holds over ${DraftCaps.patches} patches');
      }
      for (final e in rawPatches.entries) {
        final k = '${e.key}';
        if (k.startsWith(elKeyPrefix) && elKeyOf(k) == null) {
          throw FormatException('bad el: patch key "$k"');
        }
        patches[k] = DraftPatch.fromJson(e.value, k);
      }
    }
    return DraftOverlay(
      artifact: artifact,
      updatedAt: raw['updatedAt'] as String?,
      tokens: tokens,
      patches: patches,
    );
  }

  /// The token tier's served form: a :root override block placed after the
  /// artifact's own styles, so equal specificity lets source order win.
  String tokenStyleBlock() {
    if (tokens.isEmpty) return '';
    final decls =
        tokens.entries.map((e) => '${e.key}: ${e.value}').join('; ');
    return '<style id="arxa-draft-tokens">:root{$decls}</style>';
  }

  /// Overlay the draft onto one served page. Pure. Patch keys ride machine
  /// identity by default; an `el:<data-el>` key targets the authored
  /// identity instead — the binding the dial records when one machine id
  /// fans out over heterogeneous authored meanings (amended 2026-08-24).
  DraftApplyResult apply(String html) {
    var out = html;
    var applied = 0;
    final stale = <String>[];
    final refused = <String>[];
    for (final e in patches.entries) {
      if (e.value.isEmpty) continue;
      final elKey = elKeyOf(e.key);
      final attr = elKey != null ? 'data-el' : 'data-arxa-id';
      final target = elKey ?? e.key;
      // Instance-scoped text (2026-08-24): an nth-carrying text edit touches
      // ONLY that occurrence — exactly what its seed commit will do. The
      // style facets of the same key stay every-row; attrs scoped by
      // attrsNth (below) are per-occurrence too.
      if (e.value.text != null && e.value.nth != null) {
        final rText = patchAllRendered(
            out, target, PatchEdits(text: e.value.text),
            attr: attr, onlyNth: e.value.nth);
        out = rText.code;
        applied += rText.applied;
        final rest = PatchEdits(attrs: e.value.attrs, style: e.value.style);
        if (!rest.isEmpty) {
          final rRest = patchAllRendered(out, target, rest, attr: attr);
          out = rRest.code;
          applied += rRest.applied;
          if (rRest.error != null) {
            refused.add('${e.key}: ${rRest.error}');
          } else if (!rRest.found) {
            stale.add(e.key);
          }
        }
        if (rText.error != null) {
          refused.add('${e.key}: ${rText.error}');
        } else if (!rText.found) {
          stale.add(e.key);
        }
        continue;
      }
      // Instance-scoped attrs (2026-08-26): each attrsNth attr touches
      // ONLY its occurrence — one attr per call, because onlyNth is
      // per-call. The rest of the patch (style, every-row attrs) rides
      // one every-row pass after them.
      final scoped = e.value.attrsNth ?? const <String, int>{};
      if (scoped.isNotEmpty) {
        final everyRow = Map<String, String?>.from(e.value.attrs)
          ..removeWhere((k, _) => scoped.containsKey(k));
        for (final ent in scoped.entries) {
          final oneAttr = <String, String?>{ent.key: e.value.attrs[ent.key]};
          final rN = patchAllRendered(
              out, target, PatchEdits(attrs: oneAttr),
              attr: attr, onlyNth: ent.value);
          out = rN.code;
          applied += rN.applied;
          if (rN.error != null) {
            refused.add('${e.key}: ${rN.error}');
          } else if (!rN.found) {
            stale.add(e.key);
          }
        }
        if (everyRow.isNotEmpty || e.value.style.isNotEmpty) {
          final rRest = patchAllRendered(
              out, target,
              PatchEdits(attrs: everyRow, style: e.value.style),
              attr: attr);
          out = rRest.code;
          applied += rRest.applied;
          if (rRest.error != null) {
            refused.add('${e.key}: ${rRest.error}');
          } else if (!rRest.found) {
            stale.add(e.key);
          }
        }
        continue;
      }
      final r = patchAllRendered(out, target, e.value.toPatchEdits(),
          attr: attr);
      out = r.code;
      applied += r.applied;
      if (r.error != null) {
        refused.add('${e.key}: ${r.error}');
      } else if (!r.found) {
        stale.add(e.key);
      }
    }
    final block = tokenStyleBlock();
    if (block.isNotEmpty && out.contains('</body>')) {
      out = out.replaceFirst('</body>', '$block</body>');
    }
    return DraftApplyResult(out,
        applied: applied, stale: stale, refused: refused);
  }
}
