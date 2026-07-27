import 'package:app_box_companion/channel/channel_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadyLine.tryParse', () {
    test('parses a valid ready-line payload', () {
      final r = ReadyLine.tryParse(const {
        'tag': 'app-box-prototype-ready',
        'url': 'http://127.0.0.1:54321/',
        'port': 54321,
        'host': '127.0.0.1',
      });
      expect(r, isNotNull);
      expect(r!.url, 'http://127.0.0.1:54321/');
      expect(r.port, 54321);
      expect(r.host, '127.0.0.1');
    });

    // R5 — every check must have a negative case. A payload that is not the
    // prototype-ready signal must be rejected, or the companion would serve an
    // arbitrary channel message as a prototype.
    test('rejects a payload with the wrong tag (negative)', () {
      final r = ReadyLine.tryParse(const {
        'tag': 'something-else',
        'url': 'http://127.0.0.1:54321/',
        'port': 54321,
        'host': '127.0.0.1',
      });
      expect(r, isNull);
    });

    test('rejects a payload missing required fields (negative)', () {
      expect(
        ReadyLine.tryParse(const {'tag': 'app-box-prototype-ready'}),
        isNull,
      );
      // Wrong types: port as string, url missing.
      expect(
        ReadyLine.tryParse(const {
          'tag': 'app-box-prototype-ready',
          'url': 'http://x/',
          'port': 'not-a-port',
          'host': 'x',
        }),
        isNull,
      );
    });
  });

  group('ChannelState', () {
    test('has exactly the three §15 affordances', () {
      expect(ChannelState.values, [
        ChannelState.live,
        ChannelState.reconnecting,
        ChannelState.dead,
      ]);
    });
  });
}
