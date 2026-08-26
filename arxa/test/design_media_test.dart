// Tests for the media proxy (slice 4, rework 2026-08-24): provider search
// normalization, the copy laws (CDN allowlist, name sanitation, size cap,
// credit recording), the assets list, and the author-only fence on the
// routes. The fetcher is faked — no sockets in tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_dial.dart';
import 'package:arxa/design_media.dart';
import 'package:test/test.dart';

const _unsplashBody = {
  'results': [
    {
      'id': 'abc123',
      'urls': {
        'thumb': 'https://images.unsplash.com/photo-1?w=200',
        'regular': 'https://images.unsplash.com/photo-1?w=1080',
      },
      'user': {'name': 'Musemind'},
    }
  ]
};
const _pexelsBody = {
  'photos': [
    {
      'id': 7256197,
      'src': {
        'tiny': 'https://images.pexels.com/photos/7256197/p.jpeg?w=280',
        'large2x': 'https://images.pexels.com/photos/7256197/p.jpeg?w=1880',
      },
      'photographer': 'Thirdman',
    }
  ]
};

void main() {
  group('DialMediaProxy.search', () {
    test('normalizes both photo providers into MediaHits', () async {
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, headers) async {
          final body = url.contains('unsplash') ? _unsplashBody : _pexelsBody;
          return (200, utf8.encode(jsonEncode(body)));
        },
      );
      final hits = await proxy.search('studio interior', 'photo');
      expect(hits.length, 2);
      expect(hits[0].provider, 'unsplash');
      expect(hits[0].thumb, contains('w=200'));
      expect(hits[0].credit, 'Musemind');
      expect(hits[1].provider, 'pexels');
      expect(hits[1].full, contains('w=1880'));
    });

    test('provider key absent skips that provider', () async {
      final proxy = DialMediaProxy(
        unsplashKey: '',
        pexelsKey: 'p',
        fetcher: (url, _) async =>
            (200, utf8.encode(jsonEncode(_pexelsBody))),
      );
      final hits = await proxy.search('x', 'photo');
      expect(hits.length, 1);
      expect(hits.first.provider, 'pexels');
    });

    test('video search picks the best mp4 at or under 1080p', () async {
      const body = {
        'videos': [
          {
            'id': 9620654,
            'image': 'https://images.pexels.com/vids/poster.jpeg',
            'user': {'name': 'Ravi'},
            'video_files': [
              {
                'file_type': 'video/mp4',
                'width': 720,
                'link': 'https://videos.pexels.com/720.mp4'
              },
              {
                'file_type': 'video/mp4',
                'width': 2160,
                'link': 'https://videos.pexels.com/2160.mp4'
              },
              {
                'file_type': 'video/mp4',
                'width': 1080,
                'link': 'https://videos.pexels.com/1080.mp4'
              },
            ]
          }
        ]
      };
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, _) async {
          if (url.contains('videos')) return (200, utf8.encode(jsonEncode(body)));
          return (200, utf8.encode(jsonEncode({'photos': []})));
        },
      );
      final hits = await proxy.search('ocean', 'video');
      expect(hits, hasLength(1));
      expect(hits.first.kind, 'video');
      expect(hits.first.full, 'https://videos.pexels.com/1080.mp4');
      expect(hits.first.poster, contains('poster'));
    });
  });

  group('DialMediaProxy.copyInto laws', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('media_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('copies from the CDN, sanitizes the name, records the credit',
        () async {
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, _) async => (200, [1, 2, 3, 4]),
      );
      final path = await proxy.copyInto(
        url: 'https://images.unsplash.com/photo-9?w=1080',
        nameHint: 'Studio Interior!! 2026.jpg',
        credit: 'Musemind',
        provider: 'unsplash',
        artifactDir: dir.path,
      );
      expect(path, 'assets/images/studio-interior-2026.jpg');
      expect(File('${dir.path}/assets/images/studio-interior-2026.jpg')
          .existsSync(), isTrue);
      final credits =
          jsonDecode(File('${dir.path}/assets/credits.json').readAsStringSync())
              as Map;
      final entry = (credits['media'] as List).single as Map;
      expect(entry['credit'], 'Musemind');
      expect(entry['file'], 'studio-interior-2026.jpg');
    });

    test('a non-CDN url is refused without any fetch (SSRF guard)', () async {
      var fetched = false;
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, _) async {
          fetched = true;
          return (200, [1]);
        },
      );
      await expectLater(
        proxy.copyInto(
            url: 'http://169.254.169.254/latest/meta-data',
            nameHint: 'x.jpg',
            credit: 'c',
            provider: 'unsplash',
            artifactDir: dir.path),
        throwsA(isA<MediaRefusal>()),
      );
      expect(fetched, isFalse, reason: 'the guard refuses BEFORE fetching');
    });

    test('a file over 25 MB is refused', () async {
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, _) async => (200, List.filled(26 * 1024 * 1024, 0)),
      );
      await expectLater(
        proxy.copyInto(
            url: 'https://images.pexels.com/big.jpg',
            nameHint: 'big.jpg',
            credit: 'c',
            provider: 'pexels',
            artifactDir: dir.path),
        throwsA(isA<MediaRefusal>()),
      );
    });

    test('extension outside the closed set is refused', () async {
      final proxy = DialMediaProxy(
        unsplashKey: 'u',
        pexelsKey: 'p',
        fetcher: (url, _) async => (200, [1]),
      );
      await expectLater(
        proxy.copyInto(
            url: 'https://images.pexels.com/x.svg',
            nameHint: 'x.svg',
            credit: 'c',
            provider: 'pexels',
            artifactDir: dir.path),
        throwsA(isA<MediaRefusal>()),
      );
    });
  });

  group('dial routes: /media/*', () {
    test('author searches; guest is 403; proxy-off is 503', () async {
      final api = DialApi(
        store: MemoryDialStore(),
        artifact: 'demo',
        media: DialMediaProxy(
          unsplashKey: 'u',
          pexelsKey: 'p',
          fetcher: (url, _) async =>
              (200, utf8.encode(jsonEncode(_unsplashBody))),
        ),
      );
      final ok = await api.handle(
          'POST', '/media/search', {}, {'q': 'studio', 'kind': 'photo'}, null);
      expect(ok.status, 200);
      final results = ((ok.json as Map)['results'] as List);
      expect(results, hasLength(1));
      expect((results.single as Map)['provider'], 'unsplash');

      final guest = await api.handle('POST', '/media/search', {},
          {'q': 'studio'}, _fakeGrant('demo'));
      expect(guest.status, 403);

      final off = DialApi(store: MemoryDialStore(), artifact: 'demo');
      final disabled = await off.handle(
          'POST', '/media/search', {}, {'q': 'studio'}, null);
      expect(disabled.status, 503);
    });

    test('copy route writes into the artifact and returns the path',
        () async {
      final dir = Directory.systemTemp.createTempSync('media_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final api = DialApi(
        store: MemoryDialStore(),
        artifact: 'demo',
        artifactDir: dir.path,
        media: DialMediaProxy(
          unsplashKey: 'u',
          pexelsKey: 'p',
          fetcher: (url, _) async => (200, [9, 9, 9]),
        ),
      );
      final res = await api.handle('POST', '/media/copy', {}, {
        'url': 'https://images.unsplash.com/photo-1?w=1080',
        'name': 'Hero Shot.jpg',
        'credit': 'Musemind',
        'provider': 'unsplash',
      }, null);
      expect(res.status, 201, reason: (res.json as Map)['error']?.toString() ?? '');
      expect((res.json as Map)['path'], 'assets/images/hero-shot.jpg');
      expect(File('${dir.path}/assets/images/hero-shot.jpg').existsSync(),
          isTrue);
    });

    test('assets route lists the copied media', () async {
      final dir = Directory.systemTemp.createTempSync('media_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/assets/images').createSync(recursive: true);
      File('${dir.path}/assets/images/a.jpg').writeAsStringSync('x');
      File('${dir.path}/assets/images/b.mp4').writeAsStringSync('x');
      File('${dir.path}/assets/images/notes.txt').writeAsStringSync('x');
      final api = DialApi(
        store: MemoryDialStore(),
        artifact: 'demo',
        artifactDir: dir.path,
        media: DialMediaProxy(
            unsplashKey: 'u', pexelsKey: 'p', fetcher: (u, h) async => (200, <int>[])),
      );
      final res = await api.handle('GET', '/media/assets', {}, null, null);
      expect(res.status, 200);
      final assets = (res.json as Map)['assets'] as List;
      expect(assets, contains('assets/images/a.jpg'));
      expect(assets, contains('assets/images/b.mp4'));
      expect(assets, isNot(contains('assets/images/notes.txt')));
    });
  });
}

ShareLinkGrant _fakeGrant(String artifact) =>
    ShareLinkGrant(artifact: artifact, expiresAt: '2099-01-01T00:00:00Z');
