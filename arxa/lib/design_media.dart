/// The Arxa Dial's media proxy (rework 2026-08-24, slice 4): the card's
/// Media section searches Unsplash + Pexels SERVER-SIDE and copies the pick
/// into the artifact's assets — the provider keys never reach the browser
/// (Pexels is kind:secret in credentials.catalog.json; Unsplash rides the
/// same confined channel by policy, one origin for both).
///
/// Contracts verified live 2026-08-24 (200s against both APIs):
///   Unsplash photos: `GET api.unsplash.com/search/photos?q=&per_page=`
///     `Authorization: Client-ID <key>`
///     results[].{id, urls.thumb (w=200), urls.regular (w=1080 download),
///                user.name, links.html}
///   Pexels photos:   `GET api.pexels.com/v1/search?q=&per_page=`
///     `Authorization: <key>`
///     photos[].{id, src.tiny (280x200), src.large2x, photographer}
///   Pexels videos:   `GET api.pexels.com/videos/search?q=&per_page=`
///     videos[].{id, image (poster), video_files[] {link, width, file_type}}
///
/// Laws with teeth:
///   - COPY only fetches the provider CDNs (images.unsplash.com,
///     images.pexels.com, videos.pexels.com) — an SSRF-shaped URL is a loud
///     400, never attempted.
///   - Names are sanitized to [a-z0-9-]; extensions to a closed set; bytes
///     capped at 25 MB; the written path is always inside
///     `<artifactDir>/assets/images/<artifact>/`.
///   - Every copy records a credit line in assets/credits.json (the
///     providers' attribution expectations are not optional).
///   - The fetcher is injectable: tests feed canned responses, production
///     gets the dart:io HttpClient adapter.
library;

import 'dart:convert';
import 'dart:io';

/// One normalized search result, provider-agnostic for the card grid.
class MediaHit {
  final String provider; // 'unsplash' | 'pexels'
  final String kind; // 'photo' | 'video'
  final String id;
  final String thumb; // grid thumbnail URL
  final String full; // download URL (photo full / best mp4 ≤1080p)
  final String credit; // who made it
  final String? poster; // video poster frame
  const MediaHit(this.provider, this.kind, this.id, this.thumb, this.full,
      this.credit, {this.poster});

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'kind': kind,
        'id': id,
        'thumb': thumb,
        'full': full,
        'credit': credit,
        if (poster != null) 'poster': poster,
      };
}

/// Injectable HTTP seam: (status, body-bytes?) for a GET. Production uses
/// [_ioFetch]; tests feed canned payloads without sockets.
typedef MediaFetch = Future<(int, List<int>?)> Function(
    String url, Map<String, String> headers);

/// The production fetcher over dart:io HttpClient.
Future<(int, List<int>?)> ioFetcher(
    String url, Map<String, String> headers) async {
  final c = HttpClient()..userAgent = 'arxa-dial';
  try {
    final req = await c.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final bytes = <int>[];
    await for (final b in res) {
      bytes.addAll(b);
    }
    return (res.statusCode, bytes);
  } finally {
    c.close();
  }
}

class DialMediaProxy {
  DialMediaProxy({
    required this.unsplashKey,
    required this.pexelsKey,
    MediaFetch? fetcher,
  }) : fetch = fetcher ?? ioFetcher;

  /// Empty-string keys disable the proxy (the routes answer 503 with the
  /// env var names — a loud refusal, not a silent empty grid).
  final String unsplashKey;
  final String pexelsKey;
  final MediaFetch fetch;

  bool get enabled => unsplashKey.isNotEmpty || pexelsKey.isNotEmpty;

  static const maxResults = 24;
  static const maxQuery = 80;
  static const maxBytes = 25 * 1024 * 1024;

  static const _cdnHosts = {
    'images.unsplash.com',
    'images.pexels.com',
    'videos.pexels.com',
  };
  static const _okExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4'};

  Future<List<MediaHit>> search(String q, String kind) async {
    final query = q.trim();
    if (query.isEmpty || query.length > maxQuery) return const [];
    final photos = kind == 'photo';
    final hits = <MediaHit>[];
    if (photos && unsplashKey.isNotEmpty) {
      hits.addAll(await _unsplash(query));
    }
    if (pexelsKey.isNotEmpty) {
      hits.addAll(photos
          ? await _pexelsPhotos(query)
          : await _pexelsVideos(query));
    }
    return hits.take(maxResults).toList();
  }

  Future<List<MediaHit>> _unsplash(String q) async {
    final (status, body) = await fetch(
        'https://api.unsplash.com/search/photos'
        '?query=${Uri.encodeQueryComponent(q)}&per_page=12',
        {'Authorization': 'Client-ID $unsplashKey'});
    if (status != 200 || body == null) return const [];
    final results =
        ((jsonDecode(utf8.decode(body)) as Map)['results'] ?? []) as List;
    return [
      for (final r in results)
        MediaHit(
          'unsplash',
          'photo',
          '${r['id']}',
          '${(r['urls'] as Map)['thumb']}',
          '${(r['urls'] as Map)['regular']}',
          '${(r['user'] as Map)['name']}',
        ),
    ];
  }

  Future<List<MediaHit>> _pexelsPhotos(String q) async {
    final (status, body) = await fetch(
        'https://api.pexels.com/v1/search'
        '?query=${Uri.encodeQueryComponent(q)}&per_page=12',
        {'Authorization': pexelsKey});
    if (status != 200 || body == null) return const [];
    final photos =
        ((jsonDecode(utf8.decode(body)) as Map)['photos'] ?? []) as List;
    return [
      for (final r in photos)
        MediaHit(
          'pexels',
          'photo',
          '${r['id']}',
          '${((r['src'] as Map)['tiny'])}',
          '${((r['src'] as Map)['large2x'])}',
          '${r['photographer']}',
        ),
    ];
  }

  Future<List<MediaHit>> _pexelsVideos(String q) async {
    final (status, body) = await fetch(
        'https://api.pexels.com/videos/search'
        '?query=${Uri.encodeQueryComponent(q)}&per_page=12',
        {'Authorization': pexelsKey});
    if (status != 200 || body == null) return const [];
    final videos =
        ((jsonDecode(utf8.decode(body)) as Map)['videos'] ?? []) as List;
    final out = <MediaHit>[];
    for (final v in videos) {
      final files = ((v['video_files'] ?? []) as List)
          .where((f) => '${f['file_type']}' == 'video/mp4')
          .toList()
        ..sort((a, b) => (((a['width'] as num?) ?? 0).toInt())
            .compareTo(((b['width'] as num?) ?? 0).toInt()));
      final pick = files.isEmpty
          ? null
          : files.lastWhere(
              (f) => ((f['width'] as num?) ?? 0).toInt() <= 1080,
              orElse: () => files.first);
      if (pick == null) continue;
      out.add(MediaHit(
        'pexels',
        'video',
        '${v['id']}',
        '${v['image']}',
        '${pick['link']}',
        '${v['user'] != null ? (v['user'] as Map)['name'] : 'pexels'}',
        poster: '${v['image']}',
      ));
    }
    return out;
  }

  /// Copy a pick into the artifact. Returns the artifact-relative path the
  /// card commits as the element's src. [nameHint] is sanitized; the host
  /// must be a provider CDN; bytes are capped; a credit is recorded.
  Future<String> copyInto({
    required String url,
    required String nameHint,
    required String credit,
    required String provider,
    required String artifactDir,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_cdnHosts.contains(uri.host)) {
      throw const MediaRefusal('copy only fetches the Unsplash/Pexels CDNs');
    }
    final clean = nameHint
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9.-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (clean.isEmpty) throw const MediaRefusal('name sanitizes to nothing');
    // An extension the grammar does not know refuses LOUDLY — silently
    // re-wrapping x.svg as x.svg.jpg would ship a lie of a filename.
    final m = RegExp(r'\.([a-z0-9]+)$').firstMatch(clean);
    if (m != null && !_okExt.contains(m.group(1))) {
      throw const MediaRefusal('extension not allowed');
    }
    final base = m == null ? '$clean.jpg' : clean;
    final (status, bytes) = await fetch(url, const {});
    if (status != 200 || bytes == null) {
      throw const MediaRefusal('provider CDN said no');
    }
    if (bytes.length > maxBytes) {
      throw const MediaRefusal('file over 25 MB — pick a smaller variant');
    }
    final dir = Directory('$artifactDir/assets/images');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$base');
    file.writeAsBytesSync(bytes);
    _recordCredit(artifactDir, base, credit, provider, url);
    return 'assets/images/$base';
  }

  void _recordCredit(
      String artifactDir, String file, String credit, String provider, String src) {
    final f = File('$artifactDir/assets/credits.json');
    Map<String, dynamic> data = const {};
    if (f.existsSync()) {
      try {
        data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {
        data = const {};
      }
    }
    final entries = (data['media'] as List?)?.toList() ?? <Object>[];
    entries
        .removeWhere((e) => (e as Map)['file'] == file);
    entries.add({'file': file, 'credit': credit, 'provider': provider, 'src': src});
    f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'media': entries}));
  }

  /// The card's "From assets" tab: every image/video already local.
  List<String> listAssets(String artifactDir) {
    final d = Directory('$artifactDir/assets/images');
    if (!d.existsSync()) return const [];
    return d
        .listSync()
        .whereType<File>()
        .map((f) => 'assets/images/${f.path.split('/').last}')
        .where((p) => _okExt.contains(p.split('.').last))
        .toList()
      ..sort();
  }
}

/// A loud refusal — the card surfaces the message, nothing is written.
class MediaRefusal implements Exception {
  final String message;
  const MediaRefusal(this.message);
  @override
  String toString() => message;
}
