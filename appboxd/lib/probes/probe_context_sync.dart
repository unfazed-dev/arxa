// probe-context-sync — the composer must always say what the canvas has
// pinned.
//
// WHY THIS EXISTS: the screens filmstrip used to live in the composer tray,
// and composer.html gated the WHOLE tray — including the `cm-tray-title`
// summary of the pinned screens — on `{% if hasStrip or hasEls %}`. The strip
// was non-empty on every design surface, so that gate was always true and
// nobody noticed it was the wrong condition. When the strip moved out of the
// tray and into the viewer, `hasStrip` went false on the canvas surfaces and
// the composer stopped showing the pinned context entirely: you could pin two
// screens, watch the canvas tiles and the viewer strip both mark them, and
// the composer would say nothing. The state was fine the whole time (the
// placeholder tracked it) — only the render gate was wrong.
//
// So this probe asserts the INVARIANT, not the markup that happened to
// satisfy it: whatever is pinned in the session shows up in the composer and
// in the viewer strip at the same time. No browser needed — this is a
// server-render contract, and each check is one GET.
//
// Dart port of `tools/probe-context-sync.mjs` (30 checks, 1 section — the
// original prints exactly one `=== ... ===` header and runs every later
// block under it; this port does not add sections the original never had, so
// the parity diff reads the same shape). `needsBrowser: false`: this is the
// harness's one HTTP-only probe, the case `probe_base.dart`'s doc comment on
// [Probe.needsBrowser] names by name.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/probes/probe_base.dart';

/// One pinned-screen chip in the composer tray: `{tone, id, label, remove}`.
class ContextChip {
  final String tone;
  final String id;
  final String label;
  final String remove;

  const ContextChip({
    required this.tone,
    required this.id,
    required this.label,
    required this.remove,
  });
}

/// What the three surfaces (composer, viewer strip, canvas tiles) claim about
/// the pinned context, read out of one render.
class ContextSnapshot {
  final String _html;

  /// The composer's context label. Null is the regression this probe exists
  /// for.
  final String? composer;

  /// One chip per pinned screen.
  final List<ContextChip> chips;

  /// The composer textarea's placeholder ("Refine Home + Orders…") — the
  /// other place the composer names the context, and the one that never
  /// broke.
  final String placeholder;

  /// Pinned thumbs in the viewer's floating filmstrip (`.dv-vstrip`, views
  /// only).
  final int stripPinned;

  /// Pinned canvas tiles.
  final int tilesPinned;

  ContextSnapshot(
    this._html, {
    required this.composer,
    required this.chips,
    required this.placeholder,
    required this.stripPinned,
    required this.tilesPinned,
  });

  /// The tone the canvas tile paints for [id] — the value a chip's tone must
  /// match. Both come from `toneFor(id)` server-side, so a mismatch means
  /// someone started copying tones around instead of deriving them.
  String? tileTone(String id) {
    final re = RegExp(
      'dv-tile in-ctx ctx-([a-z]+)[\\s\\S]{0,80}?data-id="${RegExp.escape(id)}"',
    );
    return re.firstMatch(_html)?.group(1);
  }
}

final RegExp _composerRe = RegExp(
  r'<span class="cm-tray-title">([\s\S]*?)</span>',
);
final RegExp _chipRe = RegExp(
  r'<span class="cs-ctx-chip ctx-([a-z]+)"'
  r' title="([^"]*)">[\s\S]*?<span class="cs-ctx-name">([^<]*)</span>'
  r'[\s\S]*?href="([^"]*)"',
);
final RegExp _placeholderRe = RegExp(
  r'id="composer-text"[^>]*placeholder="([^"]*)"',
);
final RegExp _stripThumbRe = RegExp(r'cs-thumb [^"]*in-ctx');
final RegExp _tileRe = RegExp(r'dv-tile [^"]*in-ctx');
final RegExp _filmstripThumbRe = RegExp(r'class="dv-thumb cs-thumb');

/// Parse a `/design` render for what the composer, the viewer strip and the
/// canvas tiles each claim about the pinned context.
///
/// Pure — no I/O — so it can be unit-tested against fixture HTML without a
/// server; see `test/probe_context_sync_test.dart`.
ContextSnapshot readContext(String html) {
  final composer = _composerRe
      .firstMatch(html)
      ?.group(1)
      ?.replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final chips = _chipRe
      .allMatches(html)
      .map(
        (m) => ContextChip(
          tone: m.group(1)!,
          id: m.group(2)!,
          label: m.group(3)!,
          remove: m.group(4)!,
        ),
      )
      .toList();
  return ContextSnapshot(
    html,
    composer: composer,
    chips: chips,
    placeholder: _placeholderRe.firstMatch(html)?.group(1) ?? '',
    stripPinned: _stripThumbRe.allMatches(html).length,
    tilesPinned: _tileRe.allMatches(html).length,
  );
}

/// A cookie jar + GET, mirroring `_probe_context_sync.mjs`'s `jar`/`get`:
/// `dart:io`'s [HttpClient] does not persist cookies across requests on its
/// own, and the pin state this probe reads and writes lives in the session
/// cookie.
class _Session {
  final HttpClient _client = HttpClient();
  final Map<String, String> _jar = {};

  Future<String> get(String base, String path) async {
    final req = await _client.getUrl(Uri.parse('$base$path'));
    if (_jar.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, _jar.values.join('; '));
    }
    final res = await req.close();
    for (final c in res.cookies) {
      _jar[c.name] = '${c.name}=${c.value}';
    }
    return res.transform(utf8.decoder).join();
  }

  void close() => _client.close(force: true);
}

const Probe contextSyncProbe = Probe(
  name: 'context-sync',
  summary:
      'the composer, the viewer strip, and the canvas tiles agree on'
      ' what is pinned',
  // Pins and unpins context in the served project's session, same as the
  // .mjs original — which guards itself with requireDisposableProject.
  mutates: true,
  needsBrowser: false,
  body: _run,
);

Future<void> _run(ProbeContext ctx) async {
  final s = _Session();
  try {
    ctx.report.section(
      'the composer names every pinned screen the canvas marks',
    );

    // Start clean: ?screen=none clears the context.
    await s.get(ctx.base, '/design/chat?screen=none');

    // The composer names every pin as its own chip — one per pinned screen,
    // in the screen's own tone, with an unpin control. Not a "first +N"
    // summary.
    const pins = [(1, 'portalo.home', 'Home'), (2, 'portalo.orders', 'Orders')];
    for (final (n, id, label) in pins) {
      await s.get(ctx.base, '/design/chat/context/$id?state=on');
      final c = readContext(await s.get(ctx.base, '/design'));
      ctx.report.check(
        '$n pinned: the composer shows a context label',
        c.composer != null,
        c.composer == null
            ? 'cm-tray-title ABSENT — the composer says nothing about the pin'
            : jsonEncode(c.composer),
      );
      ctx.report.check(
        '$n pinned: one chip per pin',
        c.chips.length == n,
        jsonEncode(c.chips.map((x) => x.id).toList()),
      );
      ctx.report.check(
        '$n pinned: the new chip names the screen',
        c.chips.any((x) => x.id == id && x.label == label),
        jsonEncode(c.chips.map((x) => '${x.id}=${x.label}').toList()),
      );
      ctx.report.check(
        "$n pinned: every chip wears its screen's canvas tone",
        c.chips.every((x) => x.tone.isNotEmpty && x.tone == c.tileTone(x.id)),
        c.chips
            .map((x) => '${x.id} chip=${x.tone} tile=${c.tileTone(x.id)}')
            .join(', '),
      );
      ctx.report.check(
        '$n pinned: every chip carries an unpin href',
        c.chips.every((x) => x.remove.contains('/context/${x.id}?state=off')),
        jsonEncode(c.chips.map((x) => x.remove).toList()),
      );
      ctx.report.check(
        '$n pinned: the placeholder agrees',
        c.placeholder.contains(label),
        jsonEncode(c.placeholder),
      );
      ctx.report.check(
        '$n pinned: the viewer strip marks $n',
        c.stripPinned == n,
        '${c.stripPinned}',
      );
      ctx.report.check(
        '$n pinned: the canvas tiles mark $n',
        c.tilesPinned == n,
        '${c.tilesPinned}',
      );
    }

    // The × is the whole point of the chips: one GET, and the composer, the
    // strip and the tiles all drop that screen together.
    {
      final before = readContext(await s.get(ctx.base, '/design'));
      final target = before.chips.first;
      final after = readContext(await s.get(ctx.base, target.remove));
      ctx.report.check(
        'unpin via a chip × removes that chip',
        !after.chips.any((x) => x.id == target.id),
        jsonEncode(after.chips.map((x) => x.id).toList()),
      );
      ctx.report.check(
        'unpin via a chip × leaves the others',
        after.chips.length == before.chips.length - 1,
        '${before.chips.length} → ${after.chips.length}',
      );
      ctx.report.check(
        'unpin via a chip × unmarks the viewer strip in the same swap',
        after.stripPinned == before.stripPinned - 1,
        '${before.stripPinned} → ${after.stripPinned}',
      );
      ctx.report.check(
        'unpin via a chip × unmarks the canvas tile in the same swap',
        after.tilesPinned == before.tilesPinned - 1,
        '${before.tilesPinned} → ${after.tilesPinned}',
      );
    }

    // The strip is VIEWS-ONLY. It floats over the views canvas; in flows it
    // would cover the flow rows, and in proto it would sit beside a device
    // frame that has nothing to do with it. The gate lives in the facade
    // (filmstrip: null), so this is what proves the template isn't quietly
    // rendering it anyway.
    {
      await s.get(ctx.base, '/design/chat/context/portalo.home?state=on');
      const modes = [('views', true), ('flows', false), ('proto', false)];
      for (final (mode, want) in modes) {
        await s.get(ctx.base, '/design/viewer?mode=$mode');
        final html = await s.get(ctx.base, '/design');
        final thumbs = _filmstripThumbRe.allMatches(html).length;
        ctx.report.check(
          '$mode: the filmstrip ${want ? 'renders' : 'is absent'}',
          want ? thumbs > 0 : thumbs == 0,
          '$thumbs thumb(s)',
        );
        // The pin itself must survive the lens switch either way — hiding
        // the strip is a render decision, not a state change.
        ctx.report.check(
          '$mode: the pin survives the lens switch',
          readContext(html).chips.any((x) => x.id == 'portalo.home'),
          '',
        );
      }
      await s.get(ctx.base, '/design/viewer?mode=views');
    }

    // Unpinning must take the summary away again — a stale "context ·" line
    // is the same desync in the other direction.
    await s.get(ctx.base, '/design/chat?screen=none');
    final cleared = readContext(await s.get(ctx.base, '/design'));
    ctx.report.check(
      'cleared: no pinned thumbs',
      cleared.stripPinned == 0,
      '${cleared.stripPinned}',
    );
    ctx.report.check(
      'cleared: no pinned tiles',
      cleared.tilesPinned == 0,
      '${cleared.tilesPinned}',
    );
    ctx.report.check(
      'cleared: the composer drops every chip',
      cleared.chips.isEmpty,
      jsonEncode(cleared.chips.map((x) => x.id).toList()),
    );
    ctx.report.check(
      'cleared: the composer drops the context label',
      cleared.composer == null,
      jsonEncode(cleared.composer),
    );
  } finally {
    s.close();
  }
}
