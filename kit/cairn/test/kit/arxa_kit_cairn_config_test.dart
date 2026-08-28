import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';

/// The cairn kit's configuration surface (phase 3): one immutable
/// [ArxaKitCairnConfig] plus the ONLY env contract apps ever see —
/// `ARXA_CAIRN_MODE` / `ARXA_CAIRN_URL` / `ARXA_CAIRN_PUSH` dart-defines.
///
/// Branches under test:
/// - Zero configuration means `localOnly`: free-user parity — the app boots a
///   local cairn database with no server, no URL, no defines.
/// - `fromDefines` (the testable core of `fromEnvironment`) parses the define
///   strings: `local|sync|supabase`, blank = default, push is the literal
///   string "true" only.
/// - `validate()` fails loudly — naming the exact missing define — when a
///   server mode has no sync URL (mirrors kit/data's credential checks).
/// - Unknown mode strings are rejected naming ARXA_CAIRN_MODE, never silently
///   coerced.
void main() {
  group('kit.cairn.config', () {
    test(
      'kit.cairn.config — zero configuration means localOnly and validates',
      () {
        // Given a config built with no arguments at all
        const config = ArxaKitCairnConfig();

        // Then the mode is localOnly with no URL and push opted out
        expect(config.mode, ArxaKitCairnMode.localOnly);
        expect(config.syncUrl, isNull);
        expect(config.push, isFalse);

        // And validation passes — localOnly needs nothing
        expect(config.validate, returnsNormally);
      },
    );

    test(
      'kit.cairn.config — blank defines parse to localOnly defaults',
      () {
        // When the raw define strings are all blank (unset)
        final config = ArxaKitCairnConfig.fromDefines();

        // Then the result is the localOnly default
        expect(config.mode, ArxaKitCairnMode.localOnly);
        expect(config.syncUrl, isNull);
        expect(config.push, isFalse);
      },
    );

    test(
      'kit.cairn.config — defines parse mode, url and the literal push true',
      () {
        // When the defines select a supabase bridge with a URL and push
        final config = ArxaKitCairnConfig.fromDefines(
          mode: 'supabase',
          syncUrl: 'wss://sync.example.com/sync',
          push: 'true',
        );

        // Then each lands on the typed field
        expect(config.mode, ArxaKitCairnMode.supabaseBridge);
        expect(config.syncUrl, 'wss://sync.example.com/sync');
        expect(config.push, isTrue);
      },
    );

    test(
      'kit.cairn.config — push is opt-in: any string but literal true is off',
      () {
        // Given push set to a non-literal value
        final config = ArxaKitCairnConfig.fromDefines(push: '1');

        // Then push stays off — only the literal string "true" opts in
        expect(config.push, isFalse);
      },
    );

    test(
      'kit.cairn.config — an unknown mode is rejected naming ARXA_CAIRN_MODE',
      () {
        // When the mode define holds garbage, parsing throws a StateError
        // that names the offending define — never a silent fallback
        expect(
          () => ArxaKitCairnConfig.fromDefines(mode: 'produciton'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('ARXA_CAIRN_MODE'),
            ),
          ),
        );
      },
    );

    test(
      'kit.cairn.config — sync mode without a URL fails naming ARXA_CAIRN_URL',
      () {
        // Given a sync-mode config with no syncUrl
        const config = ArxaKitCairnConfig(mode: ArxaKitCairnMode.sync);

        // Then validate throws naming the exact missing define
        expect(
          config.validate,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('ARXA_CAIRN_URL'),
            ),
          ),
        );
      },
    );

    test(
      'kit.cairn.config — supabaseBridge without a URL fails naming ARXA_CAIRN_URL',
      () {
        // Given a supabaseBridge-mode config with no syncUrl
        const config = ArxaKitCairnConfig(mode: ArxaKitCairnMode.supabaseBridge);

        // Then validate throws naming the exact missing define
        expect(
          config.validate,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('ARXA_CAIRN_URL'),
            ),
          ),
        );
      },
    );

    test(
      'kit.cairn.config — server modes validate once a syncUrl is present',
      () {
        // Given both server modes with a URL
        const sync = ArxaKitCairnConfig(
          mode: ArxaKitCairnMode.sync,
          syncUrl: 'wss://sync.example.com/sync',
        );
        const bridge = ArxaKitCairnConfig(
          mode: ArxaKitCairnMode.supabaseBridge,
          syncUrl: 'wss://sync.example.com/sync',
        );

        // Then both validate
        expect(sync.validate, returnsNormally);
        expect(bridge.validate, returnsNormally);
      },
    );

    test(
      'kit.cairn.config — CRDT tiers are carried for the schema emitter',
      () {
        // Given a config declaring counter and or-set tables
        const config = ArxaKitCairnConfig(
          orSetTables: {'tags'},
          counterTables: {'likes'},
        );

        // Then both tiers round-trip untouched (the backend hands them to
        // cairn and the emitter stamps their columns)
        expect(config.orSetTables, {'tags'});
        expect(config.counterTables, {'likes'});
      },
    );

    test(
      'kit.cairn.config — a table in BOTH tier sets is rejected at validate',
      () {
        // Given a config tagging the same table as counter AND or-set — the
        // engine's rule is "a table MUST NOT be in both" (or-set wins the
        // first branch checked, silently dropping the counter tag), so the
        // kit fails loudly instead
        const config = ArxaKitCairnConfig(
          orSetTables: {'posts'},
          counterTables: {'posts'},
        );

        // Then validate names the table and both fields
        expect(
          config.validate,
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('posts'))
              .having((e) => e.message, 'message', contains('counterTables'))),
        );
      },
    );
  });
}
