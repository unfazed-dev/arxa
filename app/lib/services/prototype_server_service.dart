import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:path/path.dart' as p;

/// Plan 09 — serves a frozen design's htmx prototype with no Node on PATH.
///
/// Two runtimes, selected by `prototypeRuntime` config (9.8):
///   embedded (default) — Dart [HttpServer] + flutter_js running the designer's
///     viewmodels UNCHANGED. JavaScriptCore on Apple platforms is a system
///     framework (zero added bytes); QuickJS elsewhere (~1 MB). Only the
///     routing layer is replaced (this service + harness.js); the viewmodels,
///     services, models and templates are bundled untouched (9.3) and fixture
///     reads are bridged to the host (9.4).
///   node — spawns the designer's `serve.mjs` for local byte-for-byte
///     comparison against the embedded engine.
///
/// Bound to 127.0.0.1 on an OS-assigned port (R3: port 0). The ready contract
/// matches serve.py / serve.mjs (host + real bound port) so a caller integrates
/// against one shape.
class PrototypeServerService {
  /// Starts the prototype server for [designDir] and returns its handle once
  /// listening. [vendorDir] is the designer runtime's `vendor/` (the htmx/
  /// preload/head-support client libs); it ships with the app or, in dev,
  /// resolves to the skill's runtime dir.
  Future<PrototypeServerHandle> start({
    required String designDir,
    required String vendorDir,
    String runtime = 'embedded',
    String host = '127.0.0.1',
    int port = 0,
  }) {
    if (runtime == 'node') {
      return _startNode(designDir: designDir, host: host, port: port);
    }
    return _startEmbedded(
      designDir: designDir,
      vendorDir: vendorDir,
      host: host,
      port: port,
    );
  }

  // --- embedded -------------------------------------------------------------
  Future<PrototypeServerHandle> _startEmbedded({
    required String designDir,
    required String vendorDir,
    required String host,
    required int port,
  }) async {
    final bundleFile = File(p.join(designDir, '_bundle', 'artifact.bundle.js'));
    if (!bundleFile.existsSync()) {
      throw FileSystemException(
        'design is not bundled — run `node tools/bundle_viewmodels.js <design>`',
        bundleFile.path,
      );
    }

    final js = getJavascriptRuntime(xhr: false);
    // Host bridges (9.4): synchronous reads back into Dart. The harness wraps
    // these as __readTemplate / __readFileSync. Returning a value flows through
    // flutter_js's sendMessage (whose typedef is void Function but whose
    // implementation uses the result).
    String readTemplate(dynamic args) {
      final name = args as String;
      final f = File(p.join(designDir, p.posix.normalize(name)));
      _confine(f, designDir);
      return f.readAsStringSync();
    }
    String readFileSync(dynamic args) {
      var raw = args as String;
      // The bundle emits file URLs rooted at a __ARTIFACT__ placeholder that the
      // runtime swaps for the real design dir.
      raw = raw.replaceAll('file://__ARTIFACT__', designDir);
      if (raw.startsWith('file://')) raw = raw.substring('file://'.length);
      final f = File(p.normalize(raw));
      _confine(f, designDir);
      return f.readAsStringSync();
    }
    js.setupBridge('readTemplate', readTemplate);
    js.setupBridge('readFileSync', readFileSync);

    final nunjucks = await rootBundle.loadString(
      'assets/prototype_runtime/nunjucks.min.js',
    );
    final harness = await rootBundle.loadString(
      'assets/prototype_runtime/harness.js',
    );
    final bundle = bundleFile.readAsStringSync();
    for (final code in [nunjucks, harness, bundle]) {
      final r = js.evaluate(code, sourceUrl: 'prototype-runtime');
      if (r.isError) {
        js.dispose();
        throw StateError('engine eval failed: ${r.stringResult}');
      }
    }

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    final actualHost = host.isEmpty ? '127.0.0.1' : host;
    final url = 'http://$actualHost:${server.port}/';

    final stopCompleter = Completer<void>();
    late PrototypeServerHandle handle;
    final subscription = server.listen((request) {
      _handle(request, js: js, designDir: designDir, vendorDir: vendorDir);
    });

    handle = PrototypeServerHandle(
      url: url,
      port: server.port,
      host: actualHost,
      stop: () async {
        await subscription.cancel();
        await server.close();
        js.dispose();
        if (!stopCompleter.isCompleted) stopCompleter.complete();
      },
    );
    return handle;
  }

  void _handle(
    HttpRequest request, {
    required JavascriptRuntime js,
    required String designDir,
    required String vendorDir,
  }) async {
    try {
      // Static assets first (9.5): vendor libs, design assets, consumed DS.
      if (await _maybeServeStatic(
        request,
        designDir: designDir,
        vendorDir: vendorDir,
      )) {
        return;
      }

      // Routing is delegated to the engine against the design's route table
      // (9.2) — no ad-hoc route map here. Read the body for POST before the
      // (synchronous) dispatch critical section.
      Map<String, dynamic>? body;
      if (request.method == 'POST') {
        body = await _readFormBody(request);
      }
      final cookies = <String, String>{};
      for (final c in request.cookies) {
        cookies[c.name] = c.value;
      }
      final req = <String, dynamic>{
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': body,
        'cookies': cookies,
      };

      // CRITICAL SECTION (synchronous, no awaits): dispatch -> drain -> read.
      // Dart is single-isolate, so nothing interleaves inside this block — the
      // engine's per-request globals cannot be corrupted by a concurrent request.
      final mode = js.evaluate('__dispatch(${jsonEncode(req)})').stringResult;
      if (mode == '__async__' ||
          js.evaluate('globalThis.__lastDispatchResponse == null').stringResult ==
              'true') {
        for (var i = 0; i < 8; i++) {
          js.executePendingJob();
        }
      }
      final respJson = js
          .evaluate('JSON.stringify(globalThis.__lastDispatchResponse)')
          .stringResult;
      final resp = jsonDecode(respJson) as Map<String, dynamic>;

      final status = (resp['status'] as num?)?.toInt() ?? 200;
      final headers = (resp['headers'] as Map?)?.cast<String, dynamic>() ?? {};
      request.response.statusCode = status;
      headers.forEach((k, v) {
        final value = '$v';
        // Hono's c.html()/c.text() send '; charset=utf-8'; match it so the
        // shipped runtime agrees with the designer's headers, not just its body.
        final amended = (k.toLowerCase() == 'content-type' &&
                (value == 'text/html' || value == 'text/plain'))
            ? '$value; charset=utf-8'
            : value;
        request.response.headers.add(k, amended);
      });
      for (final sc in (resp['setCookies'] as List?) ?? <dynamic>[]) {
        request.response.headers.add('Set-Cookie', '$sc');
      }
      request.response.headers.add('Cache-Control', 'no-store');
      // IOSink.write defaults to latin1; the body is UTF-8, so emit raw bytes.
      request.response.add(utf8.encode(resp['body'] as String? ?? ''));
      await request.response.close();
    } catch (err) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.text;
        request.response.add(utf8.encode('500 — $err'));
        await request.response.close();
      } catch (_) {
        // The response may be past committing; nothing more to do but drop.
      }
    }
  }

  // --- static serving (9.5) -------------------------------------------------
  Future<bool> _maybeServeStatic(
    HttpRequest request, {
    required String designDir,
    required String vendorDir,
  }) async {
    if (request.method != 'GET' && request.method != 'HEAD') return false;
    final path = request.uri.path;
    File? file;
    if (path.startsWith('/assets/vendor/')) {
      file = _safeFile(vendorDir, path.substring('/assets/vendor/'.length));
    } else if (path.startsWith('/assets/')) {
      file = _safeFile(designDir, 'assets/${path.substring('/assets/'.length)}');
    } else if (path.startsWith('/_ds/')) {
      file = _safeFile(designDir, '_ds/${path.substring('/_ds/'.length)}');
    }
    if (file == null || !file.existsSync()) return false;
    final ctype = _mimeType(file.path);
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ctype;
    request.response.headers.add('Cache-Control', 'no-store');
    if (request.method == 'HEAD') {
      request.response.headers.contentLength = file.lengthSync();
      await request.response.close();
      return true;
    }
    await file.openRead().pipe(request.response);
    return true;
  }

  File? _safeFile(String root, String rel) {
    // Drop '..' segments and confine to root (a prototype is unreleased client
    // work — traversal out of the root is rejected, never merely unexpected).
    final clean = rel
        .split('/')
        .where((s) => s.isNotEmpty && s != '..')
        .join('/');
    if (clean.isEmpty) return null;
    final f = File(p.normalize(p.join(root, clean)));
    try {
      if (!p.isWithin(root, f.absolute.path)) return null;
    } on Exception {
      // ignore
    }
    return f;
  }

  void _confine(File f, String root) {
    // Defense in depth for host-driven reads (templates/fixtures).
    final abs = f.absolute.path;
    if (!p.isWithin(File(root).absolute.path, abs) && abs != File(root).absolute.path) {
      throw FileSystemException('path escapes design root', f.path);
    }
  }

  ContentType _mimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.css' => ContentType.parse('text/css'),
      '.js' => ContentType.parse('text/javascript'),
      '.json' => ContentType.parse('application/json'),
      '.svg' => ContentType.parse('image/svg+xml'),
      '.png' => ContentType.parse('image/png'),
      '.webp' => ContentType.parse('image/webp'),
      '.woff2' => ContentType.parse('font/woff2'),
      '.woff' => ContentType.parse('font/woff'),
      '.html' => ContentType.parse('text/html'),
      '.txt' => ContentType.parse('text/plain'),
      _ => ContentType.parse('application/octet-stream'),
    };
  }

  Future<Map<String, String>> _readFormBody(HttpRequest request) async {
    // The handlers' contract (helpers.form -> c.req.parseBody) returns a plain
    // object of the urlencoded fields; keys are singular.
    final data = <int>[];
    await for (final chunk in request) {
      data.addAll(chunk);
    }
    final body = utf8.decode(data);
    final result = <String, String>{};
    for (final pair in body.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final k = Uri.decodeQueryComponent(eq < 0 ? pair : pair.substring(0, eq));
      final v = eq < 0 ? '' : Uri.decodeQueryComponent(pair.substring(eq + 1));
      result[k] = v;
    }
    return result;
  }

  // --- node fallback (9.8) --------------------------------------------------
  Future<PrototypeServerHandle> _startNode({
    required String designDir,
    required String host,
    required int port,
  }) async {
    // Dev-only: run the designer's Hono server natively. Requires Node on PATH
    // and the runtime's node_modules. The ready line is one JSON object.
    final exe = Platform.environment['APP_BOX_NODE'] ?? 'node';
    final here = Directory.current.path;
    final serveMjs = _resolveServeMjs(here);
    final args = [
      serveMjs,
      designDir,
      '--host',
      host,
      '--port',
      '$port',
      '--json',
    ];
    final proc = await Process.start(exe, args);
    final completer = Completer<Map<String, dynamic>>();
    final sub = proc.stdout.transform(utf8.decoder).listen((out) {
      final nl = out.indexOf('\n');
      final line = nl < 0 ? out : out.substring(0, nl);
      if (line.trimLeft().startsWith('{')) {
        try {
          completer.complete(jsonDecode(line.trim()) as Map<String, dynamic>);
          // ignore: empty_catches
        } catch (e) {}
      }
    });
    final info = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('node server did not signal ready'),
    );
    return PrototypeServerHandle(
      url: info['url'] as String,
      port: (info['port'] as num).toInt(),
      host: info['host'] as String,
      stop: () async {
        await sub.cancel();
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(const Duration(seconds: 5),
            onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        });
      },
    );
  }

  String _resolveServeMjs(String cwd) {
    // repo layout: skills/app-box-designer/runtime/serve.mjs
    final candidates = [
      p.join(cwd, 'skills', 'app-box-designer', 'runtime', 'serve.mjs'),
      p.join(cwd, '..', 'skills', 'app-box-designer', 'runtime', 'serve.mjs'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    throw FileSystemException('serve.mjs not found for node fallback');
  }
}

class PrototypeServerHandle {
  final String url;
  final int port;
  final String host;
  final Future<void> Function() stop;
  PrototypeServerHandle({
    required this.url,
    required this.port,
    required this.host,
    required this.stop,
  });
}
