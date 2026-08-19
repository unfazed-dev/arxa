// The CDP worker bridge for the Dart design server.
//
// Design artifacts (app.routes.js, *_viewmodel.js, TSX views) are authored
// ES modules — porting them to Dart is out of scope. So the Dart server
// executes that JS in a headless-Chrome tab driven over CDP. Dart owns HTTP,
// routing, sessions, prefs, timers, hot reload; the worker tab owns viewmodel
// dispatch + TSX rendering + l10n.
//
// At boot (and on hot reload), Dart generates render.tsx from the artifact's
// .tsx view inventory, creates a browser-compatible icon.tsx (reads from
// globalThis.__icons instead of node:fs), and bundles everything via esbuild
// into a single self-contained ESM file. The bundle is injected into Chrome
// as a blob URL; __boot dynamically imports it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/crypto_aead.dart' as crypto;
import 'package:appboxd/design_server/l10n.dart' show parseArb;
import 'package:appboxd/design_tools.dart'
    show generateRenderTsx, scriptRepoRoot;
import 'package:path/path.dart' as p;

/// A localized SEED file: `<...>models/<x>_model/<x>_seed.<locale>.json`,
/// with the leading `design/` optional (the artifact roots models/ at the
/// top level, a project nests it under design/). Deliberately narrower than
/// `models/**.json` so SSOT config that shares the directory — theme.json,
/// fonts.json — can never be offered as a text-edit target.
final _seedRel = RegExp(r'(^|/)models/[^/]+/[^/]+_seed\.[A-Za-z0-9-]+\.json$');

/// A bounded tail of a child process's stderr, plus the note that carries it
/// into an error message.
///
/// Chrome's stderr is the only account of why a launch failed. `_readWsUrl`
/// used to match `ws://` and discard every other line, so a worker that never
/// printed a DevTools URL raised a bare `TimeoutException after 0:00:30` with
/// no cause attached — the intermittent `design_server_test` boot failure
/// (finding 16) was undiagnosable by construction, and re-running it could
/// never have said why. Bounded because a chatty Chrome must not turn one
/// failure into a megabyte of log.
///
/// This is instrumentation, not a fix: nothing here retries the boot, so a real
/// failure still fails — just legibly.
class StderrTail {
  StderrTail({this.max = 20});

  final int max;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    _lines.add(line);
    if (_lines.length > max) _lines.removeAt(0);
  }

  /// Empty is reported explicitly: "Chrome said nothing" and "we dropped what
  /// Chrome said" are different diagnoses, and silence must not read as the
  /// second one.
  String get note => _lines.isEmpty
      ? ' (Chrome wrote nothing to stderr)'
      : ' — last ${_lines.length} line(s) of Chrome stderr:\n  '
          '${_lines.join('\n  ')}';
}

/// `ps` elapsed time (`[[dd-]hh:]mm:ss`) to seconds. macOS `ps` has no
/// `etimes` keyword (that is procps-only), so this formatted field is all we
/// get and it has to be parsed by hand.
///
/// Returns null when unparseable, and every caller must read that as "too
/// young to touch" rather than "old". Failing open matters: this value is the
/// only thing separating a live `appbox-cdp-` Chrome from a leaked one, so a
/// parser that quietly returned a large number on bad input would start
/// killing live browsers, and one that quietly returned 0 would disable
/// reaping altogether. Neither failure announces itself, hence the test.
int? etimeSeconds(String s) {
  var rest = s.trim();
  var days = 0;
  final dash = rest.indexOf('-');
  if (dash >= 0) {
    final d = int.tryParse(rest.substring(0, dash));
    if (d == null) return null;
    days = d;
    rest = rest.substring(dash + 1);
  }
  final parts = rest.split(':').map(int.tryParse).toList();
  if (parts.isEmpty || parts.any((p) => p == null)) return null;
  final v = parts.cast<int>();
  final hms = switch (v.length) {
    3 => v[0] * 3600 + v[1] * 60 + v[2],
    2 => v[0] * 60 + v[1],
    _ => null,
  };
  return hms == null ? null : days * 86400 + hms;
}

/// One dispatched request's outcome, plus the per-request state the worker
/// hands back so Dart can persist sessions/timers/locale across reloads.
class WorkerResponse {
  final int status;
  final Map<String, String> headers;
  final String? body;
  final List<String> setCookies;
  final Map<String, dynamic>? session;
  final Map<String, dynamic> timers;
  final String locale;
  WorkerResponse({
    required this.status,
    required this.headers,
    required this.body,
    required this.setCookies,
    required this.session,
    required this.timers,
    required this.locale,
  });

  factory WorkerResponse.fromJson(Map<String, dynamic> m) => WorkerResponse(
        status: m['status'] as int? ?? 200,
        headers: (m['headers'] as Map?)?.cast<String, String>() ?? {},
        body: m['body'] as String?,
        setCookies: ((m['setCookies'] as List?) ?? []).cast<String>(),
        session: m['session'] as Map<String, dynamic>?,
        timers: (m['timers'] as Map?)?.cast<String, dynamic>() ?? {},
        locale: m['locale'] as String? ?? 'en',
      );
}

/// The in-memory prefetch the worker renders from. Built by scanning the
/// artifact dir; refreshed on hot reload. Sync lookups only on the render path.
class _Prefetch {
  final String renderBundle; // esbuild-bundled TSX render module (ESM JS)
  final Map<String, String> templates; // project-surface presence map, keyed by registry viewRef (ui/project/<name>.html)
  final Map<String, String> fixtures; // keyed by absolute served URL
  final Map<String, Map<String, dynamic>> arb;
  final Map<String, String> icons;
  _Prefetch(this.renderBundle, this.templates, this.fixtures, this.arb, this.icons);
}

Future<_Prefetch> _scanArtifact(String artifactDir, String origin,
    String? iconsDir, String? nodeModulesDir,
    {String? projectDir}) async {
  final templates = <String, String>{};
  final fixtures = <String, String>{};
  final arb = <String, Map<String, dynamic>>{};
  final iconNames = <String>{};
  final surfaceSrcIndex = <String>[];
  final arbSrcIndex = <String>[];
  final seedSrcIndex = <String>[];

  String posixRel(String f) =>
      p.relative(f, from: artifactDir).split(p.separator).join('/');

  void iconScan(String src) {
    // Facade/viewmodel data pattern: icon('foo') / icon: 'foo' — a viewmodel
    // names the icon a view will render.
    for (final m
        in RegExp(r"""icon['"]?\s*[:\(]\s*['"]([a-z0-9-]+)['"]""").allMatches(src)) {
      iconNames.add(m.group(1)!);
    }
    // TSX pattern: <Icon name="foo" /> only — a bare name= match sweeps in
    // form fields and every other named attribute.
    for (final m
        in RegExp(r'''<Icon(?:\s[^>]*?)?name=["']([a-z0-9-]+)["']''').allMatches(src)) {
      iconNames.add(m.group(1)!);
    }
  }

  for (final f in _walk(Directory(artifactDir))) {
    final rel = posixRel(f.path);
    if (rel.endsWith('.html') || rel.endsWith('.js') || rel.endsWith('.tsx')) {
      final src = f.readAsStringSync();
      if (rel.endsWith('.html')) templates[rel] = src;
      iconScan(src);
    }
    if (RegExp(r'^models/.*\.json$').hasMatch(rel)) {
      fixtures['$origin/$rel'] = f.readAsStringSync();
    }
  }
  void scanArbDir(Directory l10nDir) {
    if (!l10nDir.existsSync()) return;
    for (final f in l10nDir.listSync().whereType<File>()) {
      final m = RegExp(r'app_(.+)\.arb$').firstMatch(p.basename(f.path));
      if (m == null) continue;
      final entries = parseArb(f.path);
      // Project keys merge OVER the artifact's (a project can restyle copy).
      arb[m.group(1)!] = {
        ...?arb[m.group(1)!],
        ...Map.fromEntries(
            entries.entries.where((e) => !e.key.startsWith('@'))),
      };
    }
  }

  scanArbDir(Directory(p.join(artifactDir, 'l10n')));

  // ---- the live-read project overlay (~/.appbox/projects/<name>/) ---------
  // The studio serves the CURRENT PROJECT's data alongside its own chrome:
  //   design/surfaces/**.html -> fixtures at /project-src/ (widget manager
  //                              scans raw source via fs_shim)
  //   design/l10n/app_*.arb   -> merged over the artifact's arb (project wins)
  //   **.json anywhere        -> fixtures at /project/<rel>  (design seeds,
  //                              intake registry+flows, build evidence)
  if (projectDir != null) {
    for (final f in _walk(Directory(projectDir))) {
      final rel = p.relative(f.path, from: projectDir).split(p.separator).join('/');
      if (rel.endsWith('.html') || rel.endsWith('.js') || rel.endsWith('.tsx')) {
        iconScan(f.readAsStringSync());
      }
      if (rel.startsWith('design/surfaces/') &&
          (rel.endsWith('.html') || rel.endsWith('.tsx'))) {
        final src = f.readAsStringSync();
        // Presence key follows the render registry's viewRef convention
        // (generateRenderTsx): a surface renders as 'ui/project/<name>.html'
        // no matter which extension the source carries — .tsx is the
        // rendered source post-migration, .html the pre-TSX fallback. The
        // templates map is presence-only now (nothing renders from it);
        // hasPartial in project_repository.js keys off this name.
        templates[
            'ui/project/${p.basenameWithoutExtension(rel)}.html'] = src;
        // Raw SOURCE text too, for the widget manager: services scan the
        // authored surface partials (data-el containers, layout attrs) via
        // fs_shim, which can only see prefetched keys. /project-src/ is that
        // read-only window; writes still go through /__project_write and the
        // watcher re-prefetches (~200ms) like every other project edit.
        fixtures['$origin/project-src/$rel'] = src;
        surfaceSrcIndex.add(rel);
      }
      // Text editing routes a widget's copy by PROVENANCE, so the two write
      // targets need the same raw-source window the surfaces have. The parsed
      // /project/<rel> fixture above cannot serve: re-serialising a decoded map
      // would reorder keys and drop the @-metadata siblings an ARB carries.
      if (rel.startsWith('design/l10n/') && rel.endsWith('.arb')) {
        fixtures['$origin/project-src/$rel'] = f.readAsStringSync();
        arbSrcIndex.add(rel);
      }
      // Seeds ONLY — not every json under models/. theme.json and fonts.json
      // are SSOT config files that live in the same directory, and a router
      // that proposed them as text-edit targets would offer to rewrite the
      // accent palette when the user retitles a card. The `_seed.<locale>`
      // basename is the discriminator; the leading `design/` is optional
      // because the artifact lays models/ out at its root and a project nests
      // it under design/.
      if (_seedRel.hasMatch(rel)) {
        fixtures['$origin/project-src/$rel'] = f.readAsStringSync();
        seedSrcIndex.add(rel);
      }
      if (rel.endsWith('.json')) {
        fixtures['$origin/project/$rel'] = f.readAsStringSync();
      }
    }
    scanArbDir(Directory(p.join(projectDir, 'design', 'l10n')));
    // fs_shim has no readdir, so the surface list itself must be a fixture —
    // without it the widget manager could not discover included partials
    // (_tabbar.html) that no registry entry names.
    fixtures['$origin/project-src/index.json'] = jsonEncode(surfaceSrcIndex);
    // Separate indices, not extra members of index.json: that file is already
    // an ARRAY the widget manager reads, and which locales/seeds exist is a
    // question only the index can answer (no readdir). A project may ship any
    // locale set — app_qps-ploc.arb exists in the studio and not in portalo —
    // so the editor reports the locales it FOUND rather than guessing names.
    fixtures['$origin/project-src/l10n-index.json'] = jsonEncode(arbSrcIndex);
    fixtures['$origin/project-src/seed-index.json'] = jsonEncode(seedSrcIndex);
  }
  final icons = <String, String>{};
  if (iconsDir != null) {
    for (final name in iconNames) {
      final f = File(p.join(iconsDir, '$name.svg'));
      if (f.existsSync()) icons[name] = f.readAsStringSync();
    }
  }

  // Build the TSX render bundle (esbuild). This is the replacement for the
  // legacy template preload — viewmodels still call h.render(c, viewRef,
  // ctx), but the shim resolves viewRef via the bundled render module instead
  // of a template environment.
  final bundle = await _buildRenderBundle(artifactDir, nodeModulesDir, projectDir: projectDir);

  return _Prefetch(bundle, templates, fixtures, arb, icons);
}

List<File> _walk(Directory d) => d
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => !f.path.contains(RegExp(r'[/\\](node_modules|\.git)([/\\]|$)')))
    .toList();

/// Find `skills/appbox-designer/runtime/node_modules` — where hono/jsx
/// lives; esbuild needs it to bundle the TSX render module.
///
/// Anchor 1 is the executing checkout ([scriptRepoRoot]) — cwd-independent
/// (see [appboxdPackageDir] for why the CWD walk is not enough). Anchor 2 is
/// the original walk up from [from], kept for in-repo shells.
String? _findNodeModulesDir([String? from]) {
  final repo = scriptRepoRoot();
  if (repo != null) {
    final c = p.join(
        repo, 'skills', 'appbox-designer', 'runtime', 'node_modules');
    if (Directory(c).existsSync()) return c;
  }
  var dir = Directory(from ?? Directory.current.path);
  for (var i = 0; i < 12; i++) {
    final candidate =
        p.join(dir.path, 'skills', 'appbox-designer', 'runtime', 'node_modules');
    if (Directory(candidate).existsSync()) return candidate;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}

/// esbuild could not bundle the render module — almost always a TSX syntax
/// error in the artifact. Distinct from a missing toolchain (node_modules
/// absent still fails the boot): a bundle error must not kill the server, it
/// surfaces on every route instead (M9 — see [JsWorker.bundleError]).
class RenderBundleException implements Exception {
  final String message;
  RenderBundleException(this.message);
  @override
  String toString() => message;
}

/// Stand-in render module injected when the real bundle fails to build, so
/// the worker still boots (the route table loads, the server stays up) and
/// [JsWorker.bundleError] can be surfaced per-route. render() is never
/// reached: the server short-circuits every dispatch while the error stands.
const _kBrokenRenderBundle =
    'export function render(){ throw new Error("render bundle unavailable — see bundleError"); }\n';

/// Browser-compatible icon.tsx — reads Lucide SVGs from `globalThis.__icons`
/// (populated by the Dart prefetch) instead of `node:fs`. Same SVG modification
/// logic as the ejected icon.tsx (stroke-width, aria attrs, class, size).
///
/// Every icon carries `data-el="icon:<glyph>"` on its `<svg>` root so it is a
/// first-class inspectable widget — hovering a path/group collapses to the svg
/// (via ownerSVGElement), never to the parent container.
const _browserIconTsx = r"""
import { raw } from 'hono/utils/html';
import type { FC } from 'hono/jsx';

interface IconProps {
  name: string;
  size?: number;
  cls?: string;
  label?: string;
  strokeWidth?: number;
  fn?: string;
}

const NAME_RE = /^[a-z0-9-]+$/;
const esc = (s: string) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function placeholder(size: number, cls: string | undefined, elName: string): string {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" focusable="false" data-el="${esc(elName)}" data-inspect-role="icon" data-inspect-style="icon"${cls ? ` class="${esc(cls)}"` : ''}><rect x="3" y="3" width="18" height="18" rx="3" stroke-dasharray="4 3"/></svg>`;
}

const Icon: FC<IconProps> = ({ name, size = 24, cls, label, strokeWidth, fn }) => {
  const elName = `icon:${name}`;
  if (typeof name !== 'string' || !NAME_RE.test(name)) {
    return raw(placeholder(size, cls, 'icon:unknown'));
  }
  const rawSvg = ((globalThis as any).__icons || {})[name];
  if (!rawSvg) return raw(placeholder(size, cls, elName));

  const openTag = rawSvg.match(/<svg[^>]*>/)![0];
  let open = openTag
    .replace(/\s+class="[^"]*"/, '')
    .replace(/\s+width="[^"]*"/, '')
    .replace(/\s+height="[^"]*"/, '');
  if (strokeWidth != null) {
    open = open.replace(/stroke-width="[^"]*"/, `stroke-width="${Number(strokeWidth)}"`);
  }
  open = open.replace(
    /<svg/,
    `<svg width="${size}" height="${size}"` +
      ` data-el="${esc(elName)}" data-inspect-role="icon" data-inspect-style="icon"` +
      (fn ? ` data-inspect-fn="${esc(fn)}"` : '') +
      (cls ? ` class="${esc(cls)}"` : '') +
      (label ? ` role="img" aria-label="${esc(label)}"` : ' aria-hidden="true" focusable="false"'),
  );
  const head = rawSvg.slice(0, rawSvg.indexOf(openTag));
  let out = head + open + rawSvg.slice(rawSvg.indexOf(openTag) + openTag.length);
  if (label) out = out.replace(/(<svg[^>]*>)/, `$1<title>${esc(label)}</title>`);
  return raw(out);
};

export default Icon;
""";

/// Generates render.tsx from the artifact's .tsx views, creates a browser-
/// compatible icon.tsx, and bundles everything via esbuild into a single
/// self-contained ESM file. The bundle includes the hono/jsx runtime — Chrome
/// needs no npm imports at runtime.
///
/// Structure:
///   tempDir/
///     node_modules/  → symlink to [nodeModulesDir]
///     runtime/
///       render.tsx   (generated by generateRenderTsx)
///       icon.tsx     (browser-compatible — reads globalThis.__icons)
///     ui/...         (copied .tsx files from the artifact)
///
/// esbuild resolves `hono/jsx` / `hono/utils/html` from the symlinked
/// node_modules. All source files are COPIED (not symlinked) so esbuild's
/// upward node_modules walk from each file lands in tempDir/node_modules.
///
/// The bundle depends ONLY on the .tsx tree (sources + the generated
/// registry), so it is cached on a content hash: a hot reload that touched
/// just JSON/ARB/fixtures reuses the bundle and skips the esbuild round-trip.
/// kimitail: single-slot cache — reloads are sequential, one slot covers the
/// edit/save cycle; a Map would only accumulate dead bundles.
String? _bundleCacheKey;
String? _bundleCacheValue;

/// esbuild runs across the process. The bundle-cache contract is a count,
/// same reasoning as [JsWorker.reloadRunsForTest]: a fixture-only reload must
/// not bump this, a .tsx edit must. Test-only.
int bundleBuildCount = 0;

Future<String> _buildRenderBundle(
    String artifactDir, String? nodeModulesDir, {String? projectDir}) async {
  if (nodeModulesDir == null || !Directory(nodeModulesDir).existsSync()) {
    throw StateError(
        'node_modules not found (needed to bundle TSX). Expected at '
        'skills/appbox-designer/runtime/node_modules. Run `npm install` there.');
  }

  // Collect the .tsx inputs once — they are both the cache key and what the
  // build copies. Key = sha256 over sorted rel paths + contents + the
  // generated render.tsx (which the inventory alone determines).
  final inputs = <String, String>{};
  for (final f in _walk(Directory(artifactDir))) {
    if (!f.path.endsWith('.tsx')) continue;
    inputs[p.relative(f.path, from: artifactDir)] = f.readAsStringSync();
  }
  // Project surface .tsx partials join the bundle under ui/project/.
  if (projectDir != null) {
    final surfacesDir = Directory(p.join(projectDir, 'design', 'surfaces'));
    if (surfacesDir.existsSync()) {
      for (final f in _walk(surfacesDir)) {
        if (!f.path.endsWith('.tsx')) continue;
        inputs[p.join('ui', 'project', p.basename(f.path))] =
            f.readAsStringSync();
      }
    }
  }
  final renderTsx = generateRenderTsx(artifactDir, projectDir: projectDir);
  final keyBytes = <int>[];
  for (final rel in inputs.keys.toList()..sort()) {
    keyBytes.addAll(utf8.encode(rel));
    keyBytes.addAll(utf8.encode(inputs[rel]!));
  }
  keyBytes.addAll(utf8.encode(renderTsx));
  final key = crypto.sha256(Uint8List.fromList(keyBytes))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (key == _bundleCacheKey && _bundleCacheValue != null) {
    return _bundleCacheValue!;
  }

  final buildDir =
      await Directory.systemTemp.createTemp('appbox-render-build');
  try {
    // Symlink node_modules so esbuild can resolve hono/jsx.
    await Link(p.join(buildDir.path, 'node_modules'))
        .create(nodeModulesDir);

    // Copy the .tsx files in. esbuild resolves relative imports from the
    // file's real path, so symlinked files would walk up to the artifact dir
    // (which has no node_modules).
    for (final rel in inputs.keys) {
      final dest = File(p.join(buildDir.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsString(inputs[rel]!);
    }

    // Create runtime/ with generated render.tsx + browser-compatible icon.tsx.
    // Written AFTER the copy so they overwrite any artifact's own runtime/
    // versions (e.g. an ejected copy has a node-dependent icon.tsx).
    final runtimeDir = Directory(p.join(buildDir.path, 'runtime'))
      ..createSync(recursive: true);
    File(p.join(runtimeDir.path, 'render.tsx')).writeAsStringSync(renderTsx);
    File(p.join(runtimeDir.path, 'icon.tsx'))
        .writeAsStringSync(_browserIconTsx);

    // Bundle render.tsx → render_bundle.js (self-contained ESM). The skill's
    // own pinned esbuild binary, not an npx lookup.
    final entryPath = p.join(runtimeDir.path, 'render.tsx');
    final outPath = p.join(buildDir.path, 'render_bundle.js');
    bundleBuildCount++;
    final result =
        await Process.run(p.join(nodeModulesDir, '.bin', 'esbuild'), [
      entryPath,
      '--bundle',
      '--format=esm',
      '--jsx=automatic',
      '--jsx-import-source=hono/jsx',
      '--outfile=$outPath',
      // node:* externals are inert (browser icon.tsx doesn't import them), but
      // kept as a safety net so a stray import doesn't fail the build.
      '--external:node:fs',
      '--external:node:path',
      '--external:node:url',
    ]);
    if (result.exitCode != 0) {
      throw RenderBundleException(
          'esbuild failed to bundle render.tsx:\n${result.stderr}');
    }

    final bundle = File(outPath).readAsStringSync();
    _bundleCacheKey = key;
    _bundleCacheValue = bundle;
    return bundle;
  } finally {
    try {
      await buildDir.delete(recursive: true);
    } catch (_) {
      // Temp dir cleanup is best-effort.
    }
  }
}

/// A live headless-Chrome worker tab. Boot it once per server; reload on
/// artifact change; dispose on shutdown.
class JsWorker {
  JsWorker._(this._tab, this._workerPageUrl, this._origin, this._artifactDir,
      this._iconsDir, this._nodeModulesDir, this._projectDir,
      this._launchAttempts, this._chromePath, this._profilePrefix);
  // Not final: recovering from a dead browser means a NEW Chrome and a new
  // session. [reload] alone cannot do it — it re-navigates this tab, and a tab
  // whose browser has exited is not navigable, so the studio stayed wedged
  // behind 500s until a human restarted it (task #64).
  CdpSession _tab;
  final String _workerPageUrl;
  final String _origin;
  final String _artifactDir;
  final String? _iconsDir;
  final String? _nodeModulesDir;
  final String? _projectDir;
  // Kept from the boot call because replacing a dead browser has to launch the
  // same Chrome the same way. [_chromePath] is also the poison point a test
  // uses to make the replacement fail on cue.
  final int _launchAttempts;
  String? _chromePath;

  /// Carried so a relaunch lands under the same prefix the boot used —
  /// otherwise a worker booted under a caller-owned prefix would silently
  /// start creating dirs under the default one, which is exactly the kind of
  /// drift the prefix exists to remove.
  final String? _profilePrefix;
  _ChromeHandle? _chrome;

  /// Boot a worker against the artifact served at [origin] (the Dart server's
  /// own origin). [workerPageUrl] is the server's internal worker page.
  ///
  /// Launches Chrome directly (rather than via CdpClient.launch) so we own the
  /// Chrome [Process] and can report a real [workerPid] (behavior 4: the worker
  /// is a distinct process from the Dart server pid). cdp.dart is not modified.
  static Future<JsWorker> boot({
    required String workerPageUrl,
    required String origin,
    required String artifactDir,
    String? iconsDir,
    String? nodeModulesDir,
    String? projectDir,
    // Both exist so the boot-failure path (task #31) is reachable from a test
    // without needing a real Chrome to fail on cue; [chromePath] also lets a
    // caller pin a specific Chrome build.
    int launchAttempts = 2,
    String? chromePath,
    // Lets a test own the profile-dir prefix so it can count only its own —
    // see [_ChromeHandle.launch].
    String? profilePrefix,
  }) async {
    final handle = await _ChromeHandle.launch(
        attempts: launchAttempts,
        chromePath: chromePath,
        profilePrefix: profilePrefix);
    try {
      final tab = await handle.client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(workerPageUrl, settleMs: 600);
      final nmDir = nodeModulesDir ?? _findNodeModulesDir();
      final w = JsWorker._(tab, workerPageUrl, origin, artifactDir, iconsDir,
          nmDir, projectDir, launchAttempts, chromePath, profilePrefix)
        .._chrome = handle;
      await w._inject(await w._scan());
      final ok = await tab.evaluateFunction(
          '(b) => globalThis.__boot(b).then(() => true).catch(e => "FAIL:"+(e&&e.message||e))',
          origin);
      if (ok != true) {
        await handle.close();
        throw StateError('worker boot failed: $ok');
      }
      return w;
    } catch (e) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> _inject(_Prefetch pf) async {
    // Inject the TSX render bundle as a blob URL — ESM modules can't be
    // eval'd directly, and blob URLs work with dynamic import() in Chrome.
    // A fresh URL on every inject (including reload) ensures the worker
    // always picks up the latest bundle.
    await _tab.evaluate(
        'const _b=new Blob([${jsonEncode(pf.renderBundle)}],{type:"text/javascript"});'
        'globalThis.__renderBundleUrl=URL.createObjectURL(_b);');
    await _tab.evaluate('globalThis.__templates=${jsonEncode(pf.templates)};');
    await _tab.evaluate('globalThis.__fixtures=${jsonEncode(pf.fixtures)};');
    await _tab.evaluate('globalThis.__arb=${jsonEncode(pf.arb)};');
    await _tab.evaluate('globalThis.__icons=${jsonEncode(pf.icons)};');
  }

  /// The esbuild diagnosis from the last failed render-bundle build, null
  /// when the bundle is healthy. The design server surfaces this on every
  /// route (500 + toast) while it stands — a TSX syntax error must reach the
  /// designer's browser, not just the serve log (M9).
  String? bundleError;

  /// [_scanArtifact] plus the bundle-error contract: a TSX/esbuild failure is
  /// recorded in [bundleError] and swapped for a stub bundle so the worker
  /// still boots and the server can answer with the diagnosis; a clean build
  /// clears it. Anything else (toolchain, IO) still throws.
  Future<_Prefetch> _scan() async {
    try {
      final pf = await _scanArtifact(_artifactDir, _origin, _iconsDir,
          _nodeModulesDir, projectDir: _projectDir);
      bundleError = null;
      return pf;
    } on RenderBundleException catch (e) {
      bundleError = e.message;
      return _Prefetch(_kBrokenRenderBundle, const <String, String>{},
          const <String, String>{}, const <String, Map<String, dynamic>>{},
          const <String, String>{});
    }
  }

  /// The Chrome process pid (the "worker" pid — distinct from the Dart pid).
  int get workerPid => _chrome?.pid ?? -1;

  /// The route table: `[[method, path], ...]`.
  Future<List<List<String>>> routes() async {
    final raw =
        await _tab.evaluate('JSON.stringify(globalThis.__routes())') as String;
    return [
      for (final r in jsonDecode(raw) as List)
        [(r[0] as String).toUpperCase(), r[1] as String]
    ];
  }

  /// Dispatch one request through the artifact's viewmodel layer. [state]
  /// carries sessions/timers/locale so the JS side stays stateless across
  /// reloads.
  /// A tab that has lost `globalThis.__dispatch` (or whose execution context
  /// died mid-call) is not serving anything ever again on its own: nothing in
  /// this class re-boots except [reload], and [reload] only ever runs when a
  /// file changes. So one bad moment used to end the studio permanently — the
  /// server stayed up, answered every request with a 500, and only a manual
  /// restart brought it back (task #51).
  ///
  /// Recovery is one reboot and one retry. Not a loop: if the tab is broken for
  /// a reason a reboot cannot fix, retrying forever converts a dead worker into
  /// a hang, which is strictly worse to diagnose than a fast 500.
  Future<WorkerResponse> dispatch(
    String method,
    String fullPath, {
    Map<String, String> headers = const {},
    String? body,
    Map<String, dynamic> state = const {},
  }) async {
    try {
      return await _dispatchOnce(method, fullPath,
          headers: headers, body: body, state: state);
    } catch (e, st) {
      if (!_isLostRealm(e) && !_isTransportGone(e)) rethrow;
      stderr.writeln('[worker] the worker stopped answering ($e) — '
          'rebooting once');
      try {
        await reload();
      } catch (rebootFailure) {
        // A reboot can itself fail — Chrome is gone and refuses to come back.
        // Letting that escape replaces the caller's diagnosis with a second,
        // unrelated one, and on the watcher path it is an unhandled async
        // error, which kills the whole server. The caller asked about the
        // dispatch, so the dispatch failure is what it gets (task #64).
        stderr.writeln('[worker] the reboot failed too ($rebootFailure)');
        Error.throwWithStackTrace(e, st);
      }
      return await _dispatchOnce(method, fullPath,
          headers: headers, body: body, state: state);
    }
  }

  /// True when the failure is "the page is not the worker page any more",
  /// rather than "the artifact's own JS threw".
  ///
  /// Deliberately narrow. Matching bare `__dispatch` would also swallow a
  /// genuine bug thrown *inside* the dispatch handler, and rebooting the tab on
  /// every artifact-level exception would hide real errors behind an 850ms
  /// reload — so the missing-global case must match the callee-is-gone shape,
  /// not merely mention the name.
  static bool _isLostRealm(Object e) {
    final s = e.toString();
    return (s.contains('__dispatch') && s.contains('is not a function')) ||
        s.contains('Execution context was destroyed') ||
        s.contains('Cannot find context with specified id');
  }

  /// True when the CDP *transport* failed — the browser process is gone, not
  /// merely the tab's globals.
  ///
  /// [_isLostRealm] cannot see this case: a dead Chrome never answers, so what
  /// comes back is cdp.dart's own 30s timeout (or, once the socket has dropped,
  /// a closed-client error) with nothing about contexts or `__dispatch` in it.
  /// That is why killing the worker's Chrome used to leave the studio answering
  /// 500 to every request forever — the one place that reboots decided this was
  /// somebody else's error and rethrew (task #64).
  ///
  /// Matched by TYPE, which keeps the same narrowness [_isLostRealm] is written
  /// for by construction rather than by care: a bug thrown inside the artifact's
  /// own JS arrives as a [CdpException] carrying that JS error, and no artifact
  /// exception can ever be a socket or a CDP-command timeout. The timeout is
  /// further pinned to cdp.dart's own message so that some future unrelated
  /// `.timeout()` elsewhere in the call does not start triggering reboots.
  static bool _isTransportGone(Object e) {
    if (e is SocketException || e is WebSocketException) return true;
    if (e is TimeoutException) {
      return e.message?.startsWith('CDP command ') ?? false;
    }
    if (e is StateError) {
      final m = e.message;
      return m.contains('CdpClient is closed') ||
          m.contains('after closing') ||
          m.contains('StreamSink is closed');
    }
    return false;
  }

  Future<WorkerResponse> _dispatchOnce(
    String method,
    String fullPath, {
    required Map<String, String> headers,
    required String? body,
    required Map<String, dynamic> state,
  }) async {
    final raw = await _tab.evaluateFunction(
      '(req) => globalThis.__dispatch(req.method, req.path, req.headers, req.body, req.state)',
      {
        'method': method.toUpperCase(),
        'path': fullPath,
        'headers': headers,
        'body': body,
        'state': state,
      },
    );
    return WorkerResponse.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>);
  }

  /// Hot reload: re-navigate the worker page, then re-scan disk and re-boot.
  ///
  /// The renavigation is what makes nested modules pick up edits. A dynamic
  /// `import()` is evaluated once per realm: every module the graph pulls in
  /// (services/facades, viewmodels, repositories) is keyed in the realm's
  /// module map by resolved URL and never fetched again. A cache-busting query
  /// on the entry specifier cannot fix that — relative specifiers resolve
  /// against the base URL's path, so `./services/x.js` drops the query.
  /// Only a fresh realm empties the map, so we reboot the page the same way
  /// [boot] does, in the same order: navigate, then inject (the globals
  /// _inject writes do not survive a navigation), then __boot.
  ///
  /// Cost is per reload (watcher-triggered), not per request — one navigation
  /// plus a re-parse of the worker page's scripts, ~850ms measured, most of it
  /// the navigateAndSettle wait. Dispatch is untouched.
  ///
  /// SINGLE-FLIGHT, because concurrent reloads corrupt the tab (task #51).
  /// The watchers call this unawaited from a 200ms-debounced Timer, but the
  /// debounce only spaces out the *scheduling* — the reload itself takes ~850ms,
  /// so any save-storm longer than the debounce (a `POST /__project_write`
  /// writes answers.json AND flows.json: two events) starts a second reload
  /// while the first is between its navigate and its `__boot`. Two navigations
  /// on one tab interleave: A's [_inject] writes globals into a realm B then
  /// navigates away from, and A's `__boot` runs against B's half-loaded page.
  /// The tab can be left with no `__dispatch` at all, and since nothing reboots
  /// except this method, it stays that way until a human restarts the server.
  ///
  /// A queued flag rather than a plain join: a file that changed *during* a
  /// reload may have been missed by the in-flight [_scanArtifact], so simply
  /// returning the in-flight future would silently drop that edit. One trailing
  /// re-run, however many requests arrived, coalesces the storm without losing
  /// the last write.
  Future<void>? _reloading;
  bool _reloadQueued = false;

  Future<void> reload() async {
    final inFlight = _reloading;
    if (inFlight != null) {
      _reloadQueued = true;
      return inFlight;
    }
    // This assignment runs synchronously on call (an async body executes up to
    // its first await eagerly), so no second caller can observe a null.
    final done = Completer<void>();
    _reloading = done.future;
    try {
      do {
        _reloadQueued = false;
        await _reloadOnce();
      } while (_reloadQueued);
    } finally {
      _reloading = null;
      _reloadQueued = false;
      // Joiners only need "the reload finished". The error, if any, propagates
      // to the caller that owned this run — completing them with it too would
      // raise an unhandled async error in the watcher's Timer.
      done.complete();
    }
  }

  /// How many times the navigate→inject→boot sequence has actually run.
  /// The single-flight contract is a *count*, and counting is the only way to
  /// assert it that is not vacuous: three concurrent reloads on an idle machine
  /// interleave harmlessly often enough that "the tab still serves afterwards"
  /// passes with the guard removed. Measured, not assumed.
  int reloadRunsForTest = 0;

  /// How many times a dead browser has been replaced with a live one. Same
  /// reasoning as [reloadRunsForTest]: "the server answered again" also passes
  /// whenever Chrome happened to survive, so the count is the contract.
  int relaunchRunsForTest = 0;

  Future<void> _reloadOnce() async {
    reloadRunsForTest++;
    // Navigating a tab whose browser has exited cannot work, and it is not even
    // cheap to find out: cdp.dart never errors its pending commands when the
    // socket drops, so each doomed call burns the full 30s timeout first. When
    // the Chrome process is already reaped we know that before spending it.
    if (_chrome?.exited ?? false) await _relaunchChrome();
    try {
      await _navigateInjectBoot();
    } catch (e) {
      // The other order: Chrome died while this reload was mid-flight, or died
      // so recently that its exit has not been reaped yet. Either way a reload
      // that gives up here leaves the studio permanently on 500s, which is the
      // whole of task #64.
      if (!_isTransportGone(e)) rethrow;
      stderr.writeln('[worker] chrome is gone ($e) — launching a new one');
      await _relaunchChrome();
      await _navigateInjectBoot();
    }
  }

  /// Replace the browser process, not just the page. Deliberately does NOT
  /// re-run [boot]'s validation of `__boot`: [_navigateInjectBoot] does that,
  /// and it is the caller here.
  Future<void> _relaunchChrome() async {
    relaunchRunsForTest++;
    final dead = _chrome;
    _chrome = null;
    try {
      await dead?.close();
    } catch (_) {
      // By hypothesis this browser is already gone; failing to close it
      // politely must not stop its replacement from starting.
    }
    final handle = await _ChromeHandle.launch(
        attempts: _launchAttempts,
        chromePath: _chromePath,
        profilePrefix: _profilePrefix);
    try {
      final tab = await handle.client.newTab();
      await tab.enable();
      _tab = tab;
      _chrome = handle;
    } catch (e) {
      // Same discipline as [boot]: a handle we cannot finish wiring up is a
      // leaked Chrome and a leaked profile dir, not a spare.
      await handle.close();
      rethrow;
    }
  }

  Future<void> _navigateInjectBoot() async {
    await _tab.navigateAndSettle(_workerPageUrl, settleMs: 600);
    await _inject(await _scan());
    final ok = await _tab.evaluateFunction(
        '(b) => globalThis.__boot(b).then(()=>true).catch(e=>"FAIL:"+(e&&e.message||e))',
        _origin);
    // A failed reboot used to be discarded here — which is how a reload that
    // re-imported nothing stayed invisible. Keep serving, but say so.
    if (ok != true) stderr.writeln('worker reload failed: $ok');
  }

  /// Boot attempts made by the most recent launch. The retry contract is a
  /// COUNT: a test that asserted only "a dead Chrome eventually throws" passes
  /// just as well with the retry loop deleted, and would have let #31's whole
  /// fix rot silently.
  static int get lastLaunchAttempts => _ChromeHandle.lastLaunchAttempts;

  /// Drop `globalThis.__dispatch`, reproducing the lost-realm state a racing
  /// navigation leaves behind. Test-only seam: the real trigger is a timing
  /// race, and a test that reproduces it by racing would be exactly the kind of
  /// load-dependent flake this work is trying to remove.
  /// Kill the worker's Chrome, by pid and only by pid. Test-only: production
  /// triggers this state by being OOM-killed or crashing, neither of which a
  /// test can wait for. Never widen this to a pattern kill — the pattern also
  /// matches every other design server's Chrome on the machine.
  bool killChromeForTest() {
    final handle = _chrome;
    if (handle == null) return false;
    return Process.killPid(handle.pid, ProcessSignal.sigkill);
  }

  /// Point every subsequent relaunch at a binary that exits immediately, so the
  /// "the reboot failed too" branch is reachable without waiting for a real
  /// Chrome to refuse to start. Same stand-in as the boot-retry tests use.
  void breakRelaunchForTest() => _chromePath = '/bin/echo';

  /// Completes when the in-flight reload settles; null when none is running.
  ///
  /// The single authoritative "is the route table being rebuilt" signal, for
  /// EVERY path that rebuilds it: the watcher's [reload] and [dispatch]'s own
  /// self-heal reboot alike. `design_server` waits on this before dispatching,
  /// because a reload re-navigates this tab and `worker_shim.js` re-runs
  /// `let routesTable = []` — leaving `__dispatch` defined, answering, and
  /// 404ing everything until `__boot` repopulates it (task #19).
  ///
  /// Two properties the waiter depends on, both already true of [_reloading]:
  /// it is assigned before the first `await` in [reload], so it is set
  /// synchronously on call and no request can slip past a null; and its
  /// completer completes NORMALLY on failure, so a failed reload releases
  /// waiters instead of erroring every request queued behind it.
  Future<void>? get reloadInFlight => _reloading;

  Future<void> breakDispatchForTest() =>
      _tab.evaluate('delete globalThis.__dispatch');

  Future<void> dispose() async {
    await _chrome?.close();
  }
}

/// Owns the spawned headless-Chrome process + its CDP client. Mirrors
/// cdp.dart's CdpClient.launch args (keep in sync); launched here so the worker
/// bridge can report a real Chrome pid without modifying cdp.dart.
class _ChromeHandle {
  _ChromeHandle(this.client, this.process, this.tmpDir) {
    // The browser's own death is the only advance warning available. cdp.dart
    // never errors its pending commands when the socket drops (and is not ours
    // to change), so every call to a browser that is already gone costs the
    // full 30s timeout before failing. Watching for the exit lets the reload
    // path skip a navigation it knows cannot succeed (task #64).
    unawaited(process.exitCode
        .then((_) => _exited = true, onError: (_) => _exited = true));
  }
  final CdpClient client;
  final Process process;
  final Directory tmpDir;
  int get pid => process.pid;

  bool _exited = false;

  /// True once the Chrome process has terminated. Never guesses: an unfinished
  /// [Process.exitCode] means the browser may still be answering, so a false
  /// here only says "no proof it is dead", not "it is alive".
  bool get exited => _exited;

  /// Markers identifying a Chrome appbox launched: our own `--user-data-dir`
  /// prefixes under systemTemp. Narrow on purpose — they must never match a
  /// Chrome the user is running themselves.
  ///
  /// BOTH prefixes, not just this class's. `CdpClient` (`cdp.dart`) opens its
  /// own Chrome under `appbox-cdp-` and leaks it by exactly the same routes.
  /// Sweeping only the worker prefix left those orphans resident for days
  /// while the sweep reported success — the fix was correct for what it
  /// claimed and narrower than the leak.
  static const _uddWorker = 'appbox-design-worker-';
  static const _uddCdp = 'appbox-cdp-';
  static const _uddNames = [_uddWorker, _uddCdp];

  static List<String> get _udds => [
        for (final n in _uddNames)
          '--user-data-dir=${Directory.systemTemp.path}/$n',
      ];

  /// A CDP session lasts seconds to minutes. An hour is far outside that and
  /// still reaps day-old strays. See [sweepOrphans] for why age is needed at
  /// all for this prefix and not for the worker one.
  static const _cdpMinAgeSeconds = 3600;

  /// Reap Chrome trees a previous run leaked, and the temp dirs they held.
  ///
  /// SIGKILL and a hard crash can never run [close], so signal handlers alone
  /// cannot close this hole — the only cure is to sweep at the next boot.
  ///
  /// The orphan test is PER PREFIX, because "reparented to init" means
  /// different things for the two launchers:
  ///
  ///  * `appbox-design-worker-` — a live worker is always a child of its own
  ///    Dart server, so ppid==1 is a sound orphan signal on its own.
  ///  * `appbox-cdp-` — `CdpClient` launches with `--no-startup-window`, and
  ///    such a Chrome legitimately reparents to init while perfectly alive.
  ///    ppid==1 here proves nothing. Treating it as proof killed live Chromes
  ///    out from under concurrently running CDP work (four test files went red
  ///    the moment this prefix was added without the age guard). Age is the
  ///    discriminator that actually separates the two.
  ///
  /// Anything not judged an orphan has its profile dir marked live, so the
  /// directory sweep below cannot delete it either.
  ///
  /// Reaps are announced — a sweep that killed things silently would be the
  /// same invisible-failure trap this server already had once.
  static void sweepOrphans() {
    final ProcessResult ps;
    try {
      ps = Process.runSync('ps', ['-eo', 'pid=,ppid=,etime=,command=']);
    } catch (_) {
      return; // no ps (unlikely) — a leak is better than a crash on boot.
    }
    if (ps.exitCode != 0) return;
    final live = <String>{}; // user-data-dirs still owned by a running Chrome
    final orphans = <int>[];
    final udds = _udds;
    for (final line in (ps.stdout as String).split('\n')) {
      var at = -1;
      for (final u in udds) {
        at = line.indexOf(u);
        if (at >= 0) break;
      }
      if (at < 0) continue;
      final dir = line.substring(at + '--user-data-dir='.length).split(' ').first;
      final f = line.trimLeft().split(RegExp(r'\s+'));
      if (f.length < 3) continue;
      final pid = int.tryParse(f[0]);
      final ppid = int.tryParse(f[1]);
      final age = etimeSeconds(f[2]);
      if (pid == null) continue;
      final isWorker = dir.contains('/$_uddWorker');
      // Unparseable age counts as young: never kill on a field we failed to read.
      final oldEnough = age != null && age > _cdpMinAgeSeconds;
      if (ppid == 1 && (isWorker || oldEnough)) {
        orphans.add(pid);
      } else {
        live.add(dir); // still owned, or too young to call — hands off
      }
    }
    for (final pid in orphans) {
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
        stderr.writeln('design serve: reaped orphaned appbox chrome $pid');
      } catch (_) {}
    }
    // Their profile dirs are ours and are never reused. Skip any still claimed
    // by a running Chrome — deleting a live profile would break that server.
    for (final d in Directory.systemTemp.listSync().whereType<Directory>()) {
      if (!_uddNames.any((n) => d.path.contains('/$n'))) continue;
      if (live.contains(d.path)) continue;
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Counts boot attempts made by the most recent [launch] call. See
  /// [JsWorker.lastLaunchAttempts].
  static int lastLaunchAttempts = 0;

  /// Boot Chrome, retrying a bounded number of times (task #31).
  ///
  /// HONESTY NOTE: this is HANDLING, not a root-cause fix. The failure it
  /// addresses — `design_server_test`'s worker boot dying under parallel load —
  /// has never been reproduced on demand, and nothing here explains WHY Chrome
  /// occasionally never prints its DevTools URL. What is certain is the second
  /// half: [_readWsUrl]'s own comment records that "the boot is not retried, so
  /// a real failure still fails", so a single unlucky launch took the whole
  /// server (or test file) down with it. A transient failure that is never
  /// retried is a guaranteed failure.
  ///
  /// Two attempts, not more: each failed attempt can cost the full 30s
  /// no-DevTools-URL timeout, and turning a 30s failure into a 90s one makes a
  /// genuinely-dead Chrome much worse to diagnose for a shrinking benefit.
  ///
  /// Every attempt cleans up after itself. A retry loop that leaked the
  /// half-started Chrome would manufacture exactly the orphans [sweepOrphans]
  /// exists to reap — one failure becoming N strays.
  ///
  /// [chromePath] is injectable so the failure path is testable at all: point it
  /// at a binary that exits immediately and the retry runs in milliseconds
  /// instead of needing a real Chrome to misbehave on cue.
  ///
  /// [profilePrefix] names the `systemTemp` prefix each attempt's profile dir
  /// is created under, defaulting to the one [sweepOrphans] knows. It exists
  /// so a test can assert on *its own* dirs: the default prefix is shared by
  /// every worker on the machine, so counting it means counting whatever else
  /// happens to be booting, and the assertion passes or fails on other tests'
  /// timing rather than on the behaviour under test. A prefix the caller owns
  /// makes that count exact by construction. Note the trade: dirs under a
  /// custom prefix are invisible to [sweepOrphans], so a caller passing one
  /// owns their cleanup — which is precisely what such a test asserts.
  static Future<_ChromeHandle> launch({
    int attempts = 2,
    String? chromePath,
    String? profilePrefix,
  }) async {
    final exe = chromePath ?? CdpClient.defaultChromePath();
    if (!await File(exe).exists()) {
      throw StateError('Chrome not found at: $exe');
    }
    sweepOrphans();
    lastLaunchAttempts = 0;
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      lastLaunchAttempts = attempt;
      Process? proc;
      Directory? tmpDir;
      try {
        tmpDir = await Directory.systemTemp
            .createTemp(profilePrefix ?? _uddWorker);
        proc = await Process.start(exe, [
          '--headless=new',
          '--remote-debugging-port=0',
          '--user-data-dir=${tmpDir.path}',
          '--no-first-run',
          '--no-default-browser-check',
          '--use-gl=angle',
          '--use-angle=swiftshader',
          '--enable-unsafe-swiftshader',
          '--ignore-gpu-blocklist',
          '--hide-scrollbars',
          'about:blank',
        ]);
        final wsUrl = await _readWsUrl(proc);
        final client = await CdpClient.connect(wsUrl);
        return _ChromeHandle(client, proc, tmpDir);
      } catch (e) {
        lastError = e;
        try {
          proc?.kill(ProcessSignal.sigkill);
        } catch (_) {}
        if (tmpDir != null) {
          // SIGKILL is a request, not a completion. A Chrome that got far
          // enough to open its profile still holds those files for a moment
          // after the signal, and on macOS the recursive delete throws while
          // it does — into a bare `catch (_)`, so the directory leaks silently
          // and this retry loop manufactures exactly the orphans sweepOrphans
          // exists to reap. Wait for the profile to be genuinely unowned
          // first, the same guarantee CdpClient.close gives its own dir.
          //
          // Inert when the launched binary never opened the profile (a boot
          // that died instantly, or the `/bin/echo` stand-in the retry tests
          // use): nothing owns the dir, so the wait returns at once. This
          // hardens the real-Chrome path; it is not what makes any test pass.
          await CdpClient.awaitProfileReleased(tmpDir.path);
          try {
            tmpDir.deleteSync(recursive: true);
          } catch (_) {}
        }
        if (attempt < attempts) {
          // Announced, because a silent retry would hide a Chrome that is
          // failing every other boot behind an apparently healthy server.
          stderr.writeln('design serve: Chrome boot attempt $attempt of '
              '$attempts failed ($e) — retrying');
          await Future.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }
    // The tail is already inside lastError (see [_readWsUrl]); keep it.
    throw StateError(
        'Chrome failed to boot after $attempts attempts — $lastError');
  }

  static Future<String> _readWsUrl(Process proc) async {
    final completer = Completer<String>();
    // Every stderr line that was not the DevTools URL used to be dropped on the
    // floor, so a launch that stalled surfaced as a bare
    // `TimeoutException after 0:00:30` with no cause attached — which is why
    // the intermittent `design_server_test` worker boot (finding 16) has never
    // been diagnosable. Keep a bounded tail and attach it to every failure
    // path. This is instrumentation, not a fix: the boot is not retried, so a
    // real failure still fails, just legibly.
    final tail = StderrTail();
    late StreamSubscription sub;
    sub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        tail.add(line);
        final m = RegExp(r'ws://\S+').firstMatch(line);
        if (m != null && !completer.isCompleted) completer.complete(m.group(0)!);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError(
              'Chrome exited before printing its DevTools URL${tail.note}'));
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    try {
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw StateError(
            'Chrome printed no DevTools URL within 30s${tail.note}'),
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> close() async {
    // Graceful shutdown via CDP: Browser.close makes Chrome tear down ALL its
    // child processes (renderer/gpu/zygote). A bare kill(sigkill) on the parent
    // orphans the children — they pile up across test runs.
    try {
      await client.send('Browser.close').timeout(
          const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {
      // already gone / command rejected — fall through to the hard kill.
    }
    await client.close();
    if (!process.kill(ProcessSignal.sigkill)) {
      // already exited — nothing more to do.
    }
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// The appboxd package root (…/app-box/appboxd), resolved through the
/// RUNNING isolate's package config — the cwd-independent anchor.
///
/// Skills invoke `appbox` from wherever the engagement lives: a client
/// checkout, ~/.appbox, anywhere. The cwd walks in this file only find the
/// repo when cwd is inside it; from `clients/<name>` the walk goes
/// client → clients → … → / and never touches app-box, so `design serve`
/// closed its socket with a StateError before serving anything. The package
/// config of the script the wrapper execs (`dart run …/appboxd/bin/appbox.dart`)
/// points at the real checkout from ANY cwd.
///
/// Null when the package config cannot resolve (an AOT snapshot with no
/// package info, say) — callers must fall back to their cwd walk.
String? appboxdPackageDir() {
  Uri? uri;
  try {
    uri = Isolate.resolvePackageUriSync(Uri.parse(
        'package:appboxd/design_server/worker_assets/worker_page.html'));
  } catch (_) {
    return null;
  }
  if (uri == null) return null;
  // …/appboxd/lib/design_server/worker_assets/worker_page.html → …/appboxd
  var dir = File.fromUri(uri).parent; // worker_assets
  for (var i = 0; i < 3; i++) {
    dir = dir.parent; // design_server → lib → appboxd
  }
  return dir.existsSync() ? dir.path : null;
}

/// Locate the vendored worker assets (worker_page.html + shim),
/// bundled inside the appboxd package.
///
/// Anchor 1 is the package itself ([appboxdPackageDir]) — cwd-independent.
/// Anchor 2 is the original walk up from [from] looking for
/// `appboxd/pubspec.yaml`, kept for shells where no package config exists
/// but cwd sits inside the repo.
String? findWorkerAssetsDir([String? from]) {
  final pkg = appboxdPackageDir();
  if (pkg != null) {
    final assets = p.join(pkg, 'lib', 'design_server', 'worker_assets');
    if (File(p.join(assets, 'worker_page.html')).existsSync()) return assets;
  }
  var dir = Directory(from ?? Directory.current.path);
  for (var i = 0; i < 12; i++) {
    final candidate = File(p.join(dir.path, 'appboxd', 'pubspec.yaml'));
    if (candidate.existsSync()) {
      final assets = p.join(dir.path, 'appboxd', 'lib', 'design_server',
          'worker_assets', 'worker_page.html');
      if (File(assets).existsSync()) {
        return p.dirname(assets);
      }
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}
