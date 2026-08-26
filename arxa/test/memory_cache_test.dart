import 'dart:io';

import 'package:arxa/memory_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late ResponseCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('memory_cache_test_');
    cache = ResponseCache(repoRoot: tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('ResponseCache', () {
    test('put/get round-trips a response', () {
      expect(cache.get('design', 'kimi-k3', 'prompt A'), isNull);
      cache.put('design', 'kimi-k3', 'prompt A', 'response A');
      expect(cache.get('design', 'kimi-k3', 'prompt A'), 'response A');
    });

    test('expired entries miss and are removed', () {
      var now = DateTime(2026, 7, 30);
      final c = ResponseCache(repoRoot: tmp.path, clock: () => now);
      c.put('design', 'kimi-k3', 'prompt A', 'response A');
      now = now.add(const Duration(hours: 24));
      expect(c.get('design', 'kimi-k3', 'prompt A'), isNull);
    });

    test('per-entry ttl_seconds overrides the default TTL', () {
      var now = DateTime(2026, 7, 30);
      final c = ResponseCache(repoRoot: tmp.path, clock: () => now);
      c.put('design', 'kimi-k3', 'short', 'x', ttlSeconds: 10);
      c.put('design', 'kimi-k3', 'long', 'y', ttlSeconds: 100000);
      now = now.add(const Duration(hours: 1));
      expect(c.get('design', 'kimi-k3', 'short'), isNull);
      expect(c.get('design', 'kimi-k3', 'long'), 'y');
    });

    test('evicts oldest-ts entries once past the cap', () {
      var now = DateTime(2026, 7, 30);
      final c =
          ResponseCache(repoRoot: tmp.path, maxEntries: 3, clock: () => now);
      for (var i = 0; i < 5; i++) {
        c.put('design', 'm', 'prompt $i', 'response $i');
        now = now.add(const Duration(seconds: 1));
      }
      expect(c.get('design', 'm', 'prompt 0'), isNull);
      expect(c.get('design', 'm', 'prompt 1'), isNull);
      for (var i = 2; i < 5; i++) {
        expect(c.get('design', 'm', 'prompt $i'), 'response $i');
      }
      final files = Directory(
              '${tmp.path}/pipeline/state/memory/cache')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));
      expect(files, hasLength(3));
    });

    test('corrupt entries miss without throwing', () {
      cache.put('design', 'm', 'prompt', 'response');
      final key = ResponseCache.cacheKey('design', 'm', 'prompt');
      File('${tmp.path}/pipeline/state/memory/cache/$key.json')
          .writeAsStringSync('{not json');
      expect(cache.get('design', 'm', 'prompt'), isNull);
    });

    test('key is stable and stage-sensitive', () {
      expect(ResponseCache.cacheKey('design', 'm', 'p'),
          ResponseCache.cacheKey('design', 'm', 'p'));
      expect(ResponseCache.cacheKey('design', 'm', 'p'),
          isNot(ResponseCache.cacheKey('build', 'm', 'p')));
      expect(ResponseCache.cacheKey('design', 'm', 'p'),
          isNot(ResponseCache.cacheKey('design', 'other-model', 'p')));
    });
  });

  group('assemblePrompt', () {
    test('variable spec is always last, lessons inside the prefix region', () {
      final prompt = ResponseCache.assemblePrompt(
        staticPrefix: 'STATIC PREFIX',
        lessons: 'LESSON: gates hate empty files',
        variableSpec: 'VARIABLE SPEC',
      );
      expect(prompt.endsWith('VARIABLE SPEC'), isTrue);
      final marker = prompt.indexOf(ResponseCache.cacheBreakpointMarker);
      expect(marker, greaterThan(-1));
      // Static prefix and lessons sit above the breakpoint (cacheable);
      // the variable spec sits below it (never cached).
      expect(prompt.indexOf('STATIC PREFIX'), lessThan(marker));
      expect(prompt.indexOf('LESSON:'), lessThan(marker));
      expect(prompt.indexOf('VARIABLE SPEC'), greaterThan(marker));
    });

    test('omitting lessons keeps prefix-then-marker-then-spec order', () {
      final prompt = ResponseCache.assemblePrompt(
        staticPrefix: 'STATIC',
        variableSpec: 'SPEC',
      );
      expect(prompt.endsWith('SPEC'), isTrue);
      expect(prompt.indexOf('STATIC'),
          lessThan(prompt.indexOf(ResponseCache.cacheBreakpointMarker)));
    });
  });
}
