// readContext is the one piece of probe-context-sync's logic worth a test
// independent of a live server: it is a pure regex parser over rendered HTML,
// so this exercises it against fixture markup shaped like the real render.

import 'package:appboxd/probes/probe_context_sync.dart';
import 'package:test/test.dart';

const String _twoPinsHtml = '''
<span class="cm-tray-title">
  context · Home, Orders
</span>
<textarea id="composer-text" placeholder="Refine Home + Orders…"></textarea>
<span class="cs-ctx-chip ctx-blue" title="portalo.home">
  <span class="cs-ctx-name">Home</span>
  <a href="/design/chat/context/portalo.home?state=off">×</a>
</span>
<span class="cs-ctx-chip ctx-green" title="portalo.orders">
  <span class="cs-ctx-name">Orders</span>
  <a href="/design/chat/context/portalo.orders?state=off">×</a>
</span>
<div class="dv-tile in-ctx ctx-blue" data-title="Home tile, pinned"
     data-id="portalo.home">Home</div>
<div class="dv-tile in-ctx ctx-green" data-title="Orders tile, pinned"
     data-id="portalo.orders">Orders</div>
<div class="cs-thumb cs-thumb in-ctx"></div>
<div class="cs-thumb cs-thumb in-ctx"></div>
''';

const String _clearedHtml = '''
<textarea id="composer-text" placeholder="Ask about this screen…"></textarea>
''';

void main() {
  group('readContext', () {
    test('reads the composer label, chips, tones and counts off one render',
        () {
      final c = readContext(_twoPinsHtml);
      expect(c.composer, 'context · Home, Orders');
      expect(c.chips.map((x) => x.id), ['portalo.home', 'portalo.orders']);
      expect(c.chips.map((x) => x.tone), ['blue', 'green']);
      expect(c.chips.map((x) => x.remove), [
        '/design/chat/context/portalo.home?state=off',
        '/design/chat/context/portalo.orders?state=off',
      ]);
      expect(c.placeholder, contains('Home + Orders'));
      expect(c.stripPinned, 2);
      expect(c.tilesPinned, 2);
      expect(c.tileTone('portalo.home'), 'blue');
      expect(c.tileTone('portalo.orders'), 'green');
      expect(c.tileTone('portalo.cart'), isNull);
    });

    test('a dotted screen id is matched literally, not as a tileTone wildcard',
        () {
      final html = '<div class="dv-tile in-ctx ctx-red"'
          ' data-id="portalo.category">x</div>';
      // `.` in the id must not match an arbitrary character — a wildcard
      // match would still pass this specific fixture, so the assertion is on
      // an id that would falsely match "portaloXcategory" too.
      final c = readContext(html);
      expect(c.tileTone('portalo.category'), 'red');
      expect(c.tileTone('portaloXcategory'), isNull);
    });

    test('an absent composer label reads as null, not an empty string', () {
      final c = readContext(_clearedHtml);
      expect(c.composer, isNull);
      expect(c.chips, isEmpty);
      expect(c.stripPinned, 0);
      expect(c.tilesPinned, 0);
    });
  });
}
