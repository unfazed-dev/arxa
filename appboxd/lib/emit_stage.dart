// emit_stage — Dart port of tools/vendor/stages/emit.py (1100 lines).
//
// Applies (adopts) a Blueprint package into a target Flutter dir. Idempotent,
// write-on-diff. The generated layer replays freely; extension points are
// written once and never overwritten.
//
//   - generated layer   — factory-owned. Overwritten on-diff (clean replay for
//                         appbox-built). Never hand-edited.
//   - extension points  — emitted ONCE as a stub, NEVER overwritten. Written
//                         only if ABSENT on target.
//
// Gating (ADR-0002 #3):
//   - appbox-built target (.appbox/manifest.json present) → generated layer
//     replays freely; extension points preserved. Stamp refreshed.
//   - new-app (no pubspec yet) → greenfield: write everything; stamp written.
//   - arbitrary existing target → best-effort: DRY-RUN by default; pass
//     apply:true to write generated files (each reported); extension points
//     only if absent. Stamp only with adopt:true.
//
// Idempotent: a second run with an unchanged blueprint writes nothing.
//
// emitStage returns 0 on success, 1 on failure, and writes report.json into
// the blueprint dir (the stage's scratch area; keeps the Flutter target clean).
// The Python CLI took --out as a caller-chosen path; with the fixed signature
// below, the blueprint dir is the deterministic default.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// I/O helpers
// ---------------------------------------------------------------------------

String _read(String path) => File(path).readAsStringSync();

Uint8List _readBytes(String path) => File(path).readAsBytesSync();

// file types the generated layer ships as BINARY (PNG brand glyphs). Text-mode
// _read would choke on the PNG header (0x89); these copy raw.
const _binaryExt = ['.png'];

bool _isBinary(String rel) {
  final lower = rel.toLowerCase();
  return _binaryExt.any(lower.endsWith);
}

/// Write [content] (a [String] or byte [List]) to [path], creating parent dirs.
void _write(String path, Object content) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  if (content is List<int>) {
    f.writeAsBytesSync(content);
  } else {
    f.writeAsStringSync(content as String);
  }
}

/// Structural equality across a String/String or bytes/bytes pair. (Dart `List`
/// equality is identity, so byte buffers need an element-wise compare.)
bool _equal(Object? a, Object b) {
  if (a is String && b is String) return a == b;
  if (a is List<int> && b is List<int>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return false;
}

Map<String, dynamic> _detectAppbox(String targetDir) {
  // The Python import of a sibling detect_appbox_project module has no Dart
  // equivalent here; the fallback (read .appbox/manifest.json directly) is the
  // whole behaviour.
  final file = File(p.join(targetDir, '.appbox', 'manifest.json'));
  if (!file.existsSync()) return {'isAppbox': false};
  try {
    return {'isAppbox': true, 'manifest': jsonDecode(file.readAsStringSync())};
  } catch (_) {
    return {'isAppbox': false};
  }
}

/// Walk up from the cwd until the repo marker (config/appbox.config.json)
/// appears. Mirrors bin/appbox.dart's repo-root discovery; null if not found.
String? _repoRoot() {
  var dir = Directory.current.path;
  for (;;) {
    if (File(p.join(dir, 'config', 'appbox.config.json')).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

// ---------------------------------------------------------------------------
// web bootstrap: passkeys_web SDK (required by supabase_flutter → passkeys)
// ---------------------------------------------------------------------------

void _ensurePasskeysWebSdk(String targetDir, Map<String, dynamic> report) {
  final index = File(p.join(targetDir, 'web', 'index.html'));
  if (!index.existsSync()) return; // not a web target (or web/ not scaffolded)
  final pubspec = File(p.join(targetDir, 'pubspec.yaml'));
  final deps = pubspec.existsSync() ? pubspec.readAsStringSync() : '';
  if (!deps.contains('supabase_flutter') && !deps.contains('passkeys')) {
    return; // no plugin that needs the SDK
  }
  final html = index.readAsStringSync();
  if (html.contains('src="bundle.js"')) return; // already present — idempotent
  // Python resolves two dirs up from the emit.py script = the vendored crew
  // root (tools/vendor/). The Dart port resolves the same crew root via the
  // repo marker.
  final crewRoot = _repoRoot() == null ? null : p.join(_repoRoot()!, 'tools', 'vendor');
  final sdkSrc = crewRoot == null ? null : p.join(crewRoot, 'assets', 'web', 'passkeys-bundle.js');
  if (sdkSrc == null || !File(sdkSrc).existsSync() || !html.contains('</head>')) {
    return; // vendored SDK or head marker missing — skip rather than break emit
  }
  _write(p.join(targetDir, 'web', 'bundle.js'), _read(sdkSrc));
  const tag = '  <!-- Passkeys Web SDK (corbado): required by transitive passkeys_web (via\n'
      '       supabase_flutter); without it the web app boots but never mounts. -->\n'
      '  <script src="bundle.js" type="application/javascript"></script>\n';
  _write(index.path, html.replaceFirst('</head>', '$tag</head>'));
  report['written'].addAll(['web/bundle.js', 'web/index.html (+passkeys SDK)']);
}

// ---------------------------------------------------------------------------
// Drift web runtime (sqlite3 WebAssembly + worker)
// ---------------------------------------------------------------------------

const _driftWebAssets = {
  'sqlite3.wasm':
      'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.3/sqlite3.wasm',
  'drift_worker.js':
      'https://github.com/simolus3/drift/releases/download/drift-2.34.0/drift_worker.js',
};

void _ensureDriftWebAssets(String targetDir, Map<String, dynamic> report) {
  final web = Directory(p.join(targetDir, 'web'));
  if (!web.existsSync()) return; // not a web target
  final pubspec = File(p.join(targetDir, 'pubspec.yaml'));
  if (!pubspec.existsSync() || !pubspec.readAsStringSync().contains('drift')) {
    return; // no local persistence in this app
  }
  // kimitail: emitStage is synchronous (dart:io's HttpClient is async-only), so
  // a live blocking fetch isn't reachable from this entry point. When the binary
  // assets aren't already present we degrade to the documented offline breadcrumb
  // — the same path the Python takes on any network failure. Upgrade: make
  // emitStage async / call from an async host to perform the real fetch.
  for (final name in _driftWebAssets.keys) {
    final dst = File(p.join(web.path, name));
    if (dst.existsSync()) continue; // idempotent
    final note = File(p.join(web.path, 'drift-web-setup.md'));
    if (!note.existsSync()) {
      final lines = _driftWebAssets.entries
          .map((e) => '- `${e.key}` — ${e.value}\n')
          .join();
      _write(
        note.path,
        '# Drift web assets (local persistence on web)\n\n'
        'Place these two files (from the drift release matching `drift` '
        'in pubspec.yaml) into `web/`:\n\n'
        '$lines'
        '\nServe `.wasm` as `application/wasm`. Until present, the app '
        'runs remote-only on web (offline cache disabled).\n',
      );
      report['written'].add('web/drift-web-setup.md');
    }
    break; // network unavailable — one breadcrumb is enough
  }
}

// ---------------------------------------------------------------------------
// pubspec: declare assets/svg/ + assets/png/
// ---------------------------------------------------------------------------

void _ensureSvgAssetsDeclared(String targetDir, Map<String, dynamic> report) {
  final dirs = <String>[];
  for (final sub in const ['svg', 'png']) {
    final d = Directory(p.join(targetDir, 'assets', sub));
    if (d.existsSync() && d.listSync().isNotEmpty) dirs.add(sub);
  }
  if (dirs.isEmpty) return; // no extracted vectors/rasters → nothing to declare
  final pubspec = File(p.join(targetDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return;
  var text = pubspec.readAsStringSync();
  final lines = dirs.map((s) => '    - assets/$s/\n').join();
  var changed = false;
  if (text.contains('\n  assets:\n')) {
    for (final sub in dirs) {
      if (!text.contains('assets/$sub/')) {
        text = text.replaceFirst(
          '\n  assets:\n',
          '\n  assets:\n    - assets/$sub/\n',
        );
        changed = true;
      }
    }
  } else if (text.contains('  uses-material-design: true\n')) {
    text = text.replaceFirst(
      '  uses-material-design: true\n',
      '  uses-material-design: true\n  assets:\n$lines',
    );
    changed = true;
  } else if (text.contains('\nflutter:\n')) {
    text = text.replaceFirst('\nflutter:\n', '\nflutter:\n  assets:\n$lines');
    changed = true;
  }
  // else: no flutter: block to extend — leave untouched rather than break emit
  if (changed) {
    _write(pubspec.path, text);
    report['written']
        .add('pubspec.yaml (+${dirs.map((s) => 'assets/$s/').join('/+')})');
  }
}

// ---------------------------------------------------------------------------
// stamp the design-derived display name into the 3 platform manifests
// ---------------------------------------------------------------------------

void _stampNativeNames(String targetDir, String? displayName, Map<String, dynamic> report) {
  if (displayName == null || displayName.isEmpty) return;
  final stamped = <String>[];

  final index = File(p.join(targetDir, 'web', 'index.html'));
  if (index.existsSync()) {
    final txt = index.readAsStringSync();
    final newTxt = txt.replaceFirstMapped(
      RegExp('<title[^>]*>.*?</title>', caseSensitive: false, dotAll: true),
      (m) => '<title>$displayName</title>',
    );
    if (newTxt != txt) {
      _write(index.path, newTxt);
      stamped.add('web/index.html (<title>)');
    }
  }

  final am = File(p.join(targetDir, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'));
  if (am.existsSync()) {
    final xml = am.readAsStringSync();
    var newXml = xml.replaceFirstMapped(
      RegExp('(android:label=")[^"]*(")'),
      (m) => '${m.group(1)}$displayName${m.group(2)}',
    );
    final reasons = <String>[];
    if (newXml != xml) reasons.add('android:label');
    if (!newXml.contains('enableOnBackInvokedCallback')) {
      final bumped = newXml.replaceFirstMapped(
        RegExp('(<application\\b)'),
        (m) => '${m.group(1)} android:enableOnBackInvokedCallback="true"',
      );
      if (bumped != newXml) {
        newXml = bumped;
        reasons.add('predictive-back');
      }
    }
    if (newXml != xml) {
      _write(am.path, newXml);
      stamped.add('android/AndroidManifest.xml (${reasons.join(' + ')})');
    }
  }

  final info = File(p.join(targetDir, 'ios', 'Runner', 'Info.plist'));
  if (info.existsSync()) {
    final plist = info.readAsStringSync();
    var newPlist = plist;
    for (final key in const ['CFBundleDisplayName', 'CFBundleName']) {
      newPlist = newPlist.replaceFirstMapped(
        RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)', caseSensitive: false),
        (m) => '${m.group(1)}$displayName${m.group(2)}',
      );
    }
    if (newPlist != plist) {
      _write(info.path, newPlist);
      stamped.add('ios/Runner/Info.plist (CFBundleDisplay/Name)');
    }
  }

  if (stamped.isNotEmpty) report['written'].addAll(stamped);
}

// ---------------------------------------------------------------------------
// Android Material 3 Expressive via Jetpack Compose (embedded PlatformView)
// ---------------------------------------------------------------------------

const _expressiveKt = r'''package __PKG__

// AUTO-GENERATED by flutter_crew emit (NOT the snapshot golden). True Android
// Material 3 Expressive primitives rendered by Jetpack Compose, hosted in a
// Flutter PlatformView. Leaf primitives only (button/segmented/progress) — a
// platform view cannot host Flutter children, so composite primitives (cards,
// inputs) stay Flutter Material 3. Callbacks ride a per-view MethodChannel
// "appbox/expressive/$viewId" (matches lib/ui/primitives.dart).
import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
// Material 3 bottom nav: ShortNavigationBar (the M3 Expressive app-shell nav)
// WITH arrangement = ShortNavigationBarArrangement.EqualWeight — the fix for the
// 1-of-4-tabs bug. The default ShortNavigationBar arrangement (Centered/Spaced)
// collapses inactive items to icon-only and measures to content width, so only
// the selected item renders (proven via the appbox lens: one 142px item centered in
// a 1080px bar, the other 3 tabs absent). EqualWeight forces every item to an
// equal share of the full host width with a persistent icon+label — matching the
// design's .tabbar (left:0;right:0;display:flex, every tab equal-width). The
// catalog maps navigation.tabs → "NavigationBar/ShortNavigationBar"; ShortNavBar
// + EqualWeight is the M3 Expressive-native full-width bar. BadgedBox/Badge
// carry the cart count on the Shop tab.
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarArrangement
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ExpressiveViewFactory(
    private val activity: FlutterFragmentActivity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = (args as? Map<String, Any?>) ?: emptyMap()
        return ExpressiveView(context, activity, messenger, viewId, params)
    }
}

private class ExpressiveView(
    context: Context,
    activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String, Any?>,
) : PlatformView {
    private val composeView = ComposeView(context)
    private val channel = MethodChannel(messenger, "appbox/expressive/$viewId")

    // creationParams are immutable post-creation, so the live params live in a
    // SnapshotStateMap — mutations (via the `update` MethodChannel call from Dart's
    // _ExpressiveViewState.didUpdateWidget) trigger Compose recomposition. Without this,
    // a button frozen at its creation-time `enabled`/`tint` never reflects later Dart-side
    // state changes (the Send-code button stayed disabled-coloured even after the email
    // became valid — proven via the appbox lens).
    private val params = mutableStateMapOf<String, Any?>().apply { putAll(creationParams) }

    init {
        // ComposeView needs ViewTree owners or it crashes; FlutterFragmentActivity
        // (a FragmentActivity) supplies them. ViewModelStoreOwner is unneeded (no
        // viewModel() in these composables).
        composeView.setViewTreeLifecycleOwner(activity)
        composeView.setViewTreeSavedStateRegistryOwner(activity)
        // Handle the `update` push from Dart (volatile param deltas — enabled/tint/fg/busy).
        // Merging into the SnapshotStateMap recomposes any composable reading the changed key.
        channel.setMethodCallHandler { call, _ ->
            if (call.method == "update") {
                @Suppress("UNCHECKED_CAST")
                val delta = call.arguments as? Map<String, Any?>
                if (delta != null) {
                    for ((k, v) in delta) params[k] = v
                }
            }
        }
        composeView.setContent {
            val tint = (params["tint"] as? Number)?.toLong() ?: 0xFFD2522BL
            ExpressiveRoot(params.toMap(), Color(tint)) { m, a -> channel.invokeMethod(m, a) }
        }
    }

    override fun getView() = composeView
    override fun dispose() {}
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExpressiveRoot(params: Map<String, Any?>, accent: Color, invoke: (String, Any?) -> Unit) {
    val scheme = lightColorScheme(
        primary = accent,
        onPrimary = Color.White,
        secondaryContainer = accent.copy(alpha = 0.14f),
        onSecondaryContainer = accent,
    )
    MaterialExpressiveTheme(colorScheme = scheme) {
        when (params["kind"] as? String) {
            "button" -> ExButton(params, invoke)
            "segmented" -> ExSegmented(params, invoke)
            "iconButton" -> ExIconButton(params, invoke)
            "navBar" -> ExNavBar(params, invoke)
            "toggle" -> ExToggle(params, invoke)
            "slider" -> ExSlider(params, invoke)
            "chip" -> ExChip(params, invoke)
            "progress" -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            else -> {}
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExButton(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    val label = params["label"] as? String ?: ""
    // wrap == content-width. Flutter gives the platform view a TIGHT width, so a button
    // measured as the Compose root is forced to fill it (it would report the host box,
    // not its content). Nesting it in a fill Box that passes LOOSE constraints lets the
    // button wrap to content; onSizeChanged on the button then reports the real content
    // width (dp) back over the channel, and Dart tightens the AndroidView to it.
    val wrap = (params["wrap"] as? Boolean) ?: false
    val density = LocalDensity.current
    val onClick = { invoke("onPressed", null) }
    val btnMod = if (wrap) {
        Modifier.fillMaxHeight().onSizeChanged { sz ->
            invoke("onMeasured", listOf(with(density) { sz.width.toDp().value.toDouble() }))
        }
    } else {
        Modifier.fillMaxSize()
    }
    // Explicit design container + label colours (contrast-verified upstream by the
    // legibility gate), NOT theme roles. The theme path set primary = the button's own
    // tint with a hardcoded white onPrimary, so a light-tint button (Google `paper`)
    // rendered white-on-cream and vanished. shapes=… preserves the Expressive press morph.
    val fill = Color((params["tint"] as? Number)?.toLong() ?: 0xFF1A1A1AL)
    val fg = Color((params["fg"] as? Number)?.toLong() ?: 0xFFFFFFFFL)
    // The button's enabled state (design's submit-CTA validity gate — disabled until
    // the email regex passes). Read from Dart; Compose buttons default enabled=true, so
    // if this isn't wired the gate is silently ignored (button always enabled).
    val btnEnabled = (params["enabled"] as? Boolean) ?: true
    // A trailing affordance (the design's `Send code ›` — a forward chevron) renders
    // after the label via Canvas (no material-icons dep, same policy as NavGlyph). The
    // SF-symbol name comes from Dart; "chevron.right" → a ›. Null → label alone.
    val trailing = params["trailing"] as? String
    // A LEADING brand glyph (the social-CTA provider mark — Google's 4-color G /
    // Apple's logo / …) renders BEFORE the label, loaded as the same rasterized PNG
    // every platform renders (brand_{mark}.png). colorMode decides the tint.
    val leading = params["glyph"] as? String
    val glyphColorMode = (params["glyphColorMode"] as? String) ?: "brand"
    val content = @Composable {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (leading != null) {
                BrandGlyph(leading, glyphColorMode, 18.dp, fg)
                Spacer(Modifier.width(10.dp))
            }
            Text(label)
            if (trailing != null) {
                Spacer(Modifier.width(6.dp))
                // The trailing chevron (Send-code ›) at the design token size — 14dp
                // (bundle.html:4023 <Icon size={14}/>), matching HIG/Material's subtle-
                // accessory convention (slightly below the 17pt body text).
                val trailingDp = (params["trailingIconSize"] as? Number)?.toInt() ?: 14
                Canvas(Modifier.size(trailingDp.dp)) {
                    val w = size.width; val h = size.height; val sw = w * 0.16f
                    drawLine(fg, Offset(w*0.34f, h*0.20f), Offset(w*0.66f, h*0.50f), strokeWidth = sw, cap = StrokeCap.Round)
                    drawLine(fg, Offset(w*0.66f, h*0.50f), Offset(w*0.34f, h*0.80f), strokeWidth = sw, cap = StrokeCap.Round)
                }
            }
        }
    }
    val button = @Composable {
        when (params["variant"] as? String) {
            "secondary" -> FilledTonalButton(onClick = onClick, enabled = btnEnabled, modifier = btnMod, shapes = ButtonDefaults.shapes(),
                colors = ButtonDefaults.filledTonalButtonColors(containerColor = fill, contentColor = fg)) { content() }
            "outline" -> OutlinedButton(onClick = onClick, enabled = btnEnabled, modifier = btnMod, shapes = ButtonDefaults.shapes(),
                colors = ButtonDefaults.outlinedButtonColors(containerColor = fill, contentColor = fg),
                border = BorderStroke(1.dp, fg.copy(alpha = 0.20f))) { content() }
            "ghost" -> TextButton(onClick = onClick, enabled = btnEnabled, modifier = btnMod, shapes = ButtonDefaults.shapes(),
                colors = ButtonDefaults.textButtonColors(contentColor = fg)) { content() }
            // destructive: a high-emphasis red CTA (Sign out / Cancel subscription).
            // fill carries the error-red tint the Dart side derives (the legibility
            // gate verified contrast); same shapes morph as every other Expressive button.
            "destructive" -> Button(onClick = onClick, enabled = btnEnabled, modifier = btnMod, shapes = ButtonDefaults.shapes(),
                colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = fg)) { content() }
            else -> Button(onClick = onClick, enabled = btnEnabled, modifier = btnMod, shapes = ButtonDefaults.shapes(),
                colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = fg)) { content() }
        }
    }
    if (wrap) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) { button() }
    } else {
        button()
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExSegmented(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    @Suppress("UNCHECKED_CAST")
    val labels = (params["labels"] as? List<String>) ?: emptyList()
    // Local selection state: creationParams are immutable post-creation, so the
    // Compose view owns its highlight and reports changes back to Dart (which
    // drives the list filter). This view is the sole selection driver.
    val selected = remember { mutableStateOf((params["selectedIndex"] as? Number)?.toInt() ?: 0) }
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        labels.forEachIndexed { i, l ->
            SegmentedButton(
                selected = i == selected.value,
                onClick = { selected.value = i; invoke("onChanged", i) },
                shape = SegmentedButtonDefaults.itemShape(i, labels.size),
            ) { Text(l) }
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExNavBar(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    // M3 Expressive ShortNavigationBar WITH arrangement = EqualWeight — the
    // research-correct fix for the 1-of-4-tabs bug. The DEFAULT ShortNavigationBar
    // arrangement (Centered/Spaced) collapses inactive items to icon-only and
    // measures to content width → only the selected item renders (appbox lens:
    // one 142px item centered in a 1080px bar, the other 3 tabs absent).
    // ShortNavigationBarArrangement.EqualWeight forces every item to an equal share
    // of the full host width with a persistent icon+label — matching the design's
    // .tabbar (left:0;right:0;display:flex, every tab equal-width). This is the M3
    // Expressive-native full-width app-shell nav (not the baseline NavigationBar,
    // which works but masks the real fix). Selection is VM-owned on the Dart side;
    // this view reflects `selectedIndex` and reports taps back (same round-trip as
    // ExSegmented). BadgedBox carries the cart count.
    @Suppress("UNCHECKED_CAST")
    val labels = (params["labels"] as? List<String>) ?: emptyList()
    @Suppress("UNCHECKED_CAST")
    val icons = (params["icons"] as? List<String>) ?: List(labels.size) { "" }
    @Suppress("UNCHECKED_CAST")
    val badges = (params["badges"] as? List<Number>) ?: List(labels.size) { 0 }
    val selected = remember {
        mutableStateOf((params["selectedIndex"] as? Number)?.toInt() ?: 0)
    }
    ShortNavigationBar(arrangement = ShortNavigationBarArrangement.EqualWeight) {
        labels.forEachIndexed { i, label ->
            val count = badges.getOrNull(i)?.toInt() ?: 0
            ShortNavigationBarItem(
                selected = i == selected.value,
                onClick = { selected.value = i; invoke("onTabSelected", i) },
                icon = {
                    // BadgedBox carries the cart count on the Shop tab (native M3 badge).
                    if (count > 0) {
                        BadgedBox(badge = { Badge { Text(count.toString()) } }) {
                            NavGlyph(icons.getOrNull(i), label)
                        }
                    } else {
                        NavGlyph(icons.getOrNull(i), label)
                    }
                },
                label = { Text(label) },
            )
        }
    }
}

// A tab glyph drawn via Canvas (avoids the material-icons artifact — same policy as
// ExIconButton). Dispatched on the SF-symbol name the Dart side sends (native-vocab).
// Unknown → a filled disc (never blank). ponytail: swap to Icon() if icons-core lands.
@Composable
private fun NavGlyph(symbol: String?, _label: String) {
    // MaterialTheme.colorScheme reads the CURRENT scheme (set by ExpressiveRoot's
    // MaterialExpressiveTheme wrapper). NavGlyph runs inside that scope, so this is the
    // theme the bar inherits — NOT MaterialExpressiveTheme.colorScheme (that's a composable
    // invocation, not a property; the error it raised on the first Android build).
    val fg = MaterialTheme.colorScheme.onSurface
    Canvas(Modifier.size(22.dp)) {
        val w = size.width; val h = size.height
        val s = symbol ?: ""
        when {
            s.contains("bolt") -> { // Train
                drawLine(fg, Offset(w*0.56f, h*0.10f), Offset(w*0.40f, h*0.90f), strokeWidth = w*0.12f)
                drawLine(fg, Offset(w*0.44f, h*0.10f), Offset(w*0.60f, h*0.90f), strokeWidth = w*0.12f)
            }
            s.contains("bag") || s.contains("shop") -> { // Shop
                drawLine(fg, Offset(w*0.25f, h*0.40f), Offset(w*0.75f, h*0.40f), strokeWidth = w*0.10f)
                drawLine(fg, Offset(w*0.30f, h*0.40f), Offset(w*0.34f, h*0.85f), strokeWidth = w*0.10f)
                drawLine(fg, Offset(w*0.70f, h*0.40f), Offset(w*0.66f, h*0.85f), strokeWidth = w*0.10f)
                drawLine(fg, Offset(w*0.34f, h*0.85f), Offset(w*0.66f, h*0.85f), strokeWidth = w*0.10f)
            }
            s.contains("heart") -> { // Support
                val p = Path().apply {
                    moveTo(w*0.5f, h*0.82f)
                    cubicTo(w*0.05f, h*0.50f, w*0.22f, h*0.12f, w*0.5f, h*0.38f)
                    cubicTo(w*0.78f, h*0.12f, w*0.95f, h*0.50f, w*0.5f, h*0.82f)
                    close()
                }
                drawPath(p, fg)
            }
            s.contains("person") -> { // Account
                drawCircle(fg, radius = w*0.22f, center = Offset(w*0.5f, h*0.34f))
                drawArc(fg, startAngle = 0f, sweepAngle = 180f, useCenter = true,
                    topLeft = Offset(w*0.18f, h*0.55f), size = Size(w*0.64f, h*0.50f))
            }
            else -> drawCircle(fg, radius = w*0.20f, center = Offset(w*0.5f, h*0.5f))
        }
    }
}

// The official brand glyph for a social sign-in CTA — rendered from the SAME
// rasterized PNG every other platform renders (brand_{mark}.png, emitted by
// blueprint.py from the BRAND_REGISTRY via rsvg-convert). Loaded as a Compose
// Bitmap from the Flutter asset bundle (flutter_assets/assets/png/brand_{mark}.png).
// This replaced hand-drawn Canvas beziers that produced a misshapen Google G — now
// iOS (UIKit decode) and Android (this Compose Image) render byte-identical marks.
// colorMode drives the tint: "brand" keeps the mark's fixed colours (Google 4-color
// G, brand-mandated); "mono" tints to the button fg (Apple/GitHub/X). Drawn inside
// ExButton's content Row.
@Composable
private fun BrandGlyph(mark: String, colorMode: String, sizeDp: Dp, fg: Color) {
    val ctx = LocalContext.current
    // remember(mark): decode once per brand mark (the asset never changes). runCatching
    // → a missing/unfilled brand row renders nothing rather than crashing the view.
    val bmp = remember(mark) {
        runCatching {
            ctx.assets.open("flutter_assets/assets/png/brand_${mark}.png")
                .use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
    }
    if (bmp != null) {
        // mono marks (Apple/GitHub/X): the PNG bakes black (currentColor → rsvg black);
        // tint to the button fg so Apple reads white-on-black. brand marks keep colours.
        val colorFilter = if (colorMode == "mono")
            ColorFilter.tint(fg, BlendMode.SrcIn) else null
        Image(
            painter = BitmapPainter(bmp.asImageBitmap()),
            modifier = Modifier.size(sizeDp),
            contentScale = ContentScale.Fit,
            colorFilter = colorFilter,
            contentDescription = "${mark} sign-in",
        )
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExIconButton(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    val fill = Color((params["tint"] as? Number)?.toLong() ?: 0xFF1A1A1AL)
    val fg = Color((params["fg"] as? Number)?.toLong() ?: 0xFFEFE7DDL)
    // M3 Expressive FilledIconButton: the `shapes` overload morphs the disc on
    // press (resting = filledShape ≈ circle → pressed squish shape) driven by the
    // theme's expressive motion scheme — the signature Expressive press feedback.
    // The static `shape:` overload (what this used to be) does NOT morph.
    // ponytail: play glyph drawn via Canvas (avoids the material-icons artifact);
    // swap to Icon(Icons.Filled.PlayArrow) if icons-core is added. The triangle is
    // biased right of geometric centre so it reads optically centred.
    FilledIconButton(
        onClick = { invoke("onPressed", null) },
        modifier = Modifier.fillMaxSize(),
        shapes = IconButtonDefaults.shapes(),
        colors = IconButtonDefaults.filledIconButtonColors(
            containerColor = fill,
            contentColor = fg,
        ),
    ) {
        // Glyph drawn via Canvas (no material-icons dependency), dispatched on the
        // icon name passed from Dart (`params["icon"]` = the SF-symbol string, distinct
        // per glyph). Static at mount (AndroidView creationParams) — the reactive
        // play↔pause flip would need a MethodChannel update (see live-timer-vm-generation.md).
        val icon = (params["icon"] as? String) ?: "play.fill"
        Canvas(Modifier.size(18.dp)) {
            val w = size.width
            val h = size.height
            val sw = w * 0.12f
            when {
                icon.contains("pause") -> {
                    drawRect(fg, Offset(w * 0.30f, h * 0.24f), Size(w * 0.14f, h * 0.52f))
                    drawRect(fg, Offset(w * 0.56f, h * 0.24f), Size(w * 0.14f, h * 0.52f))
                }
                icon.contains("clockwise") || icon.contains("reset") || icon.contains("refresh") -> {
                    val pad = w * 0.20f
                    drawArc(fg, -40f, 290f, false, Offset(pad, pad), Size(w - 2 * pad, h - 2 * pad),
                        style = Stroke(width = sw, cap = StrokeCap.Round))
                    val ah = Path().apply {
                        moveTo(w * 0.78f, h * 0.08f); lineTo(w * 0.93f, h * 0.30f); lineTo(w * 0.62f, h * 0.30f); close()
                    }
                    drawPath(ah, color = fg)
                }
                icon.contains("chevron") || icon.contains("arrow.back") || icon.contains("backward") -> {
                    val cp = Path().apply {
                        moveTo(w * 0.60f, h * 0.22f); lineTo(w * 0.36f, h * 0.50f); lineTo(w * 0.60f, h * 0.78f)
                    }
                    drawPath(cp, color = fg, style = Stroke(width = sw, cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
                icon.contains("pencil") || icon.contains("edit") -> {
                    drawLine(fg, Offset(w * 0.28f, h * 0.72f), Offset(w * 0.70f, h * 0.30f), strokeWidth = sw, cap = StrokeCap.Round)
                    drawLine(fg, Offset(w * 0.23f, h * 0.77f), Offset(w * 0.33f, h * 0.67f), strokeWidth = sw, cap = StrokeCap.Round)
                }
                icon.contains("speaker") || icon.contains("volume") || icon.contains("sound") -> {
                    drawRect(fg, Offset(w * 0.18f, h * 0.40f), Size(w * 0.15f, h * 0.20f))
                    val cone = Path().apply {
                        moveTo(w * 0.33f, h * 0.40f); lineTo(w * 0.50f, h * 0.26f); lineTo(w * 0.50f, h * 0.74f); lineTo(w * 0.33f, h * 0.60f); close()
                    }
                    drawPath(cone, color = fg)
                    drawArc(fg, -50f, 100f, false, Offset(w * 0.44f, h * 0.30f), Size(w * 0.30f, h * 0.40f),
                        style = Stroke(width = sw * 0.8f, cap = StrokeCap.Round))
                }
                else -> {
                    val p = Path().apply {
                        moveTo(w * 0.34f, h * 0.24f); lineTo(w * 0.34f, h * 0.76f); lineTo(w * 0.80f, h * 0.50f); close()
                    }
                    drawPath(p, color = fg)
                }
            }
        }
    }
}

// ExToggle — a Material 3 Switch (the expressive thumb/track morphs on the theme's
// motion scheme). Local state owns the thumb; the toggle reports onChanged back to
// Dart (same round-trip as ExSegmented). `value` is the captured initial state.
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExToggle(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    val checked = remember { mutableStateOf((params["value"] as? Boolean) ?: false) }
    val tint = Color((params["tint"] as? Number)?.toLong() ?: 0xFFE0613AL)
    Switch(
        checked = checked.value,
        onCheckedChange = { v -> checked.value = v; invoke("onChanged", v) },
        modifier = Modifier.fillMaxSize(),
        colors = SwitchDefaults.colors(checkedTrackColor = tint, checkedThumbColor = Color.White),
    )
}

// ExSlider — a Material 3 Slider. Local state owns the thumb position; the slider
// reports onChanged (the double) back to Dart. min/max/divisions/value from the
// captured design props; a non-literal value defaults to min.
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExSlider(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    val min = (params["min"] as? Number)?.toFloat() ?: 0f
    val max = (params["max"] as? Number)?.toFloat() ?: 1f
    val divisions = (params["divisions"] as? Number)?.toInt()
    val initial = ((params["value"] as? Number)?.toFloat() ?: min).coerceIn(min, max)
    val value = remember { mutableStateOf(initial) }
    val tint = Color((params["tint"] as? Number)?.toLong() ?: 0xFFE0613AL)
    Slider(
        value = value.value,
        onValueChange = { v -> value.value = v },
        onValueChangeFinished = { invoke("onChanged", value.value.toDouble()) },
        valueRange = min..max,
        steps = if (divisions != null && divisions > 0) (divisions - 1).coerceAtLeast(0) else 0,
        modifier = Modifier.fillMaxSize(),
        colors = SliderDefaults.colors(thumbColor = tint, activeTrackColor = tint),
    )
}

// ExChip — a Material 3 FilterChip (selectable pill). The chip renders its own
// selected highlight from `selected`; a tap reports onTap back to Dart (a Void,
// not a value — the owning list/segment decides the selection effect).
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun ExChip(params: Map<String, Any?>, invoke: (String, Any?) -> Unit) {
    val label = params["label"] as? String ?: ""
    val selected = (params["selected"] as? Boolean) ?: false
    val tint = Color((params["tint"] as? Number)?.toLong() ?: 0xFFE0613AL)
    FilterChip(
        selected = selected,
        onClick = { invoke("onTap", null) },
        label = { Text(label) },
        shape = RoundedCornerShape(50),
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = tint,
            selectedLabelColor = Color.White,
        ),
    )
}
''';

const _mainActivityKt = r'''package __PKG__

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// flutter_crew: FlutterFragmentActivity (not FlutterActivity) so embedded Compose
// platform views get the ViewTree lifecycle/savedstate owners they require.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "appbox/expressive",
            ExpressiveViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
        )
    }
}
''';

const _composeEmbedBlock = '\n'
    '// appbox:compose-embed — true Android Material 3 Expressive via Jetpack\n'
    '// Compose, embedded as a Flutter PlatformView (see ExpressivePlatformView.kt).\n'
    'android {\n'
    '    // material3 1.5.0-alpha (Compose 1.12.x) requires compileSdk 37.\n'
    '    compileSdk = 37\n'
    '    buildFeatures {\n'
    '        compose = true\n'
    '    }\n'
    '}\n'
    'dependencies {\n'
    '    // 1.5.0-alpha track: MaterialExpressiveTheme + the expressive\n'
    '    // opt-in are internal in stable 1.4.0; public only on 1.5.0-alpha.\n'
    '    implementation("androidx.compose.material3:material3:1.5.0-alpha22")\n'
    '    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")\n'
    '    implementation("androidx.savedstate:savedstate-ktx:1.2.1")\n'
    '}\n';

/// Element-wise less-than mirroring Python list comparison (shorter prefix < longer).
bool _listLessThan(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return a.length < b.length;
}

String _bumpAgp(Match m) {
  final ver = m.group(2)!;
  final parts = ver.split('.').map(int.parse).toList();
  return '${m.group(1)}${_listLessThan(parts, [9, 1, 0]) ? '9.1.0' : ver}${m.group(3)}';
}

String _bumpGradle(Match m) {
  final ver = m.group(2)!;
  final parts = ver.split('.').map(int.parse).toList();
  return '${m.group(1)}${_listLessThan(parts, [9, 3, 1]) ? '9.3.1' : ver}${m.group(3)}';
}

void _ensureAndroidExpressiveCompose(
  String targetDir,
  List<dynamic>? platforms,
  Map<String, dynamic> report,
) {
  if (platforms != null && platforms.isNotEmpty && !platforms.contains('android')) {
    return; // design not scoped to android
  }
  final app = p.join(targetDir, 'android', 'app');
  if (!Directory(app).existsSync()) return; // android not scaffolded
  // locate MainActivity.kt → its package + kotlin source dir
  String? mainKt;
  final searchRoot = Directory(p.join(app, 'src', 'main'));
  if (searchRoot.existsSync()) {
    for (final ent in searchRoot.listSync(recursive: true)) {
      if (ent is File && p.basename(ent.path) == 'MainActivity.kt') {
        mainKt = ent.path;
        break;
      }
    }
  }
  if (mainKt == null) return; // non-Kotlin scaffold (Java) — skip rather than break emit
  var pkg = 'com.example.app';
  final pkgMatch = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(_read(mainKt));
  if (pkgMatch != null) pkg = pkgMatch.group(1)!;
  final ktDir = p.dirname(mainKt);
  final written = <String>[];

  // 1. Kotlin sources
  _write(p.join(ktDir, 'ExpressivePlatformView.kt'), _expressiveKt.replaceAll('__PKG__', pkg));
  written.add('android ExpressivePlatformView.kt');
  final newMain = _mainActivityKt.replaceAll('__PKG__', pkg);
  if (_read(mainKt) != newMain) {
    _write(mainKt, newMain);
    written.add('android MainActivity.kt (FlutterFragmentActivity + factory)');
  }

  // 2. settings.gradle.kts — Compose compiler plugin + AGP floor for the alpha
  //    Compose track (material3 1.5.x → Compose 1.12.x needs AGP >= 9.1.0).
  final settings = File(p.join(targetDir, 'android', 'settings.gradle.kts'));
  if (settings.existsSync()) {
    final s0 = settings.readAsStringSync();
    var s = s0.replaceAllMapped(
      RegExp(r'(id\("com\.android\.application"\)\s+version\s+")([\d.]+)(")'),
      _bumpAgp,
    );
    if (!s.contains('kotlin.plugin.compose')) {
      final km = RegExp(r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([\d.]+)"')
          .firstMatch(s);
      final kver = km?.group(1) ?? '2.1.0';
      final anchor =
          RegExp(r'id\("org\.jetbrains\.kotlin\.android"\)[^\n]*\n').firstMatch(s);
      if (anchor != null) {
        final line = '    id("org.jetbrains.kotlin.plugin.compose") version "$kver" apply false\n';
        s = s.substring(0, anchor.end) + line + s.substring(anchor.end);
      }
    }
    if (s != s0) {
      _write(settings.path, s);
      written.add('android settings.gradle.kts (+compose plugin, AGP>=9.1.0)');
    }
  }

  // 3. app/build.gradle.kts — apply plugin + buildFeatures.compose + deps
  final gradle = File(p.join(app, 'build.gradle.kts'));
  if (gradle.existsSync()) {
    var g = gradle.readAsStringSync();
    if (!g.contains('appbox:compose-embed')) {
      g = g.replaceFirstMapped(
        RegExp(r'(id\("dev\.flutter\.flutter-gradle-plugin"\)\s*\n)'),
        (m) => '${m.group(1)}    id("org.jetbrains.kotlin.plugin.compose")\n',
      );
      g += _composeEmbedBlock;
      _write(gradle.path, g);
      written.add('android app/build.gradle.kts (+compose)');
    }
  }

  // 4. gradle wrapper — AGP 9.1.x requires Gradle >= 9.3.1.
  final wrap = File(p.join(targetDir, 'android', 'gradle', 'wrapper',
      'gradle-wrapper.properties'));
  if (wrap.existsSync()) {
    final w0 = wrap.readAsStringSync();
    final w = w0.replaceAllMapped(
      RegExp(r'(gradle-)([\d.]+)(-(?:all|bin)\.zip)'),
      _bumpGradle,
    );
    if (w != w0) {
      _write(wrap.path, w);
      written.add('android gradle wrapper (>=9.3.1)');
    }
  }

  if (written.isNotEmpty) report['written'].addAll(written);
}

// ---------------------------------------------------------------------------
// core emit
// ---------------------------------------------------------------------------

/// Apply [blueprintDir] (manifest.json + templates/) into [targetDir].
///
/// Returns the report map (mirrors the Python `emit` return). Public callers
/// should use [emitStage]; this is exposed for testing the raw logic.
Map<String, dynamic> emit({
  required String blueprintDir,
  required String targetDir,
  bool apply = false,
  bool adopt = false,
  String? supabaseUrl,
  String? supabasePublishableKey,
}) {
  final manifestPath = p.join(blueprintDir, 'manifest.json');
  final templatesDir = p.join(blueprintDir, 'templates');
  final manifest = jsonDecode(_read(manifestPath)) as Map<String, dynamic>;
  final genSet = ((manifest['generatedLayer'] as List?) ?? []).cast<String>().toSet();
  final extSet = ((manifest['extensionPoints'] as List?) ?? []).cast<String>().toSet();

  final appbox = _detectAppbox(targetDir);
  final isAppbox = appbox['isAppbox'] == true;
  final isNewApp = !File(p.join(targetDir, 'pubspec.yaml')).existsSync();

  // gating: when may generated files overwrite without apply?
  final replayOk = isAppbox || isNewApp;
  final stamp = isNewApp || isAppbox || adopt;

  final report = <String, dynamic>{
    'target': targetDir,
    'isAppbox': appbox,
    'isNewApp': isNewApp,
    'replay': replayOk,
    'applied': apply,
    'written': <String>[],
    'skipped_identical': <String>[],
    'preserved_extension': <String>[],
    'blocked_dryrun': <String>[],
    'stamped': false,
  };

  final allRel = {...genSet, ...extSet}.toList()..sort();
  for (final rel in allRel) {
    final src = p.join(templatesDir, rel);
    if (!File(src).existsSync()) continue;
    final isBin = _isBinary(rel);
    final content = isBin ? _readBytes(src) as Object : _read(src) as Object;
    final dst = p.join(targetDir, rel);
    final isExt = extSet.contains(rel);

    if (File(dst).existsSync()) {
      Object? existing;
      try {
        existing = isBin ? _readBytes(dst) as Object : _read(dst) as Object;
      } catch (_) {
        existing = null;
      }
      if (_equal(existing, content)) {
        (report['skipped_identical'] as List).add(rel);
        continue;
      }
      if (isExt) {
        // extension point already present → preserve (operator owns it)
        (report['preserved_extension'] as List).add(rel);
        continue;
      }
      // generated + differs
      if (replayOk || apply) {
        _write(dst, content);
        (report['written'] as List).add(rel);
      } else {
        (report['blocked_dryrun'] as List).add(rel);
      }
    } else {
      // absent — write regardless of gating (additive; no clobber)
      _write(dst, content);
      (report['written'] as List).add(rel);
    }
  }

  // Supabase wiring (optional; env-backed, never committed)
  if (supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabasePublishableKey != null &&
      supabasePublishableKey.isNotEmpty &&
      (replayOk || apply)) {
    _write(
      p.join(targetDir, '.env'),
      'SUPABASE_URL=$supabaseUrl\n'
      'SUPABASE_PUBLISHABLE_KEY=$supabasePublishableKey\n',
    );
    (report['written'] as List).add('.env');
  }

  // web bootstrap + native stamping (only when writes are allowed)
  if (replayOk || apply) {
    _ensurePasskeysWebSdk(targetDir, report);
    _ensureDriftWebAssets(targetDir, report);
    _ensureSvgAssetsDeclared(targetDir, report);
    _stampNativeNames(targetDir, manifest['displayName'] as String?, report);
    _ensureAndroidExpressiveCompose(
        targetDir, (manifest['platforms'] as List?)?.cast<dynamic>(), report);
  }

  // appbox stamp
  if (stamp && (replayOk || apply || isNewApp)) {
    final stampObj = <String, dynamic>{
      'factoryVersion': manifest['factoryVersion'],
      'source': manifest['source'],
      'stack': manifest['stack'],
      'lastMode': manifest['lastMode'] ?? 'new-app',
      'blueprintHash': manifest['blueprintHash'],
      'templatesVersion': manifest['templatesVersion'],
      'appName': manifest['appName'],
      'displayName': manifest['displayName'],
      'platforms': manifest['platforms'],
    };
    _write(p.join(targetDir, '.appbox', 'manifest.json'), _encodeSorted(stampObj));
    report['stamped'] = true;
  }

  return report;
}

/// JSON-encode [obj] with 2-space indent and recursively sorted keys + trailing
/// newline, mirroring Python `json.dumps(obj, indent=2, sort_keys=True) + "\n"`.
String _encodeSorted(Object obj) {
  final sorted = _sortKeys(obj);
  return '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
}

Object _sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _sortKeys(v[k])};
  }
  if (v is List) return v.map(_sortKeys).toList();
  return v as Object;
}

/// Apply a Blueprint package into [targetDir]. Returns 0 on success, 1 on failure.
///
/// Writes report.json into the blueprint dir and prints a one-line summary.
int emitStage(String blueprintDir, String targetDir, {bool apply = false}) {
  try {
    final report = emit(
      blueprintDir: blueprintDir,
      targetDir: targetDir,
      apply: apply,
    );

    // report.json → blueprint dir (the stage's scratch area).
    _write(p.join(blueprintDir, 'report.json'), _encodeSorted(report));

    final isAppboxTruthy = report['isAppbox'] is Map &&
        (report['isAppbox'] as Map)['isAppbox'] == true;
    final mode = isAppboxTruthy
        ? 'appbox-replay'
        : (report['isNewApp'] == true ? 'new-app' : 'arbitrary');
    final written = (report['written'] as List).length;
    final identical = (report['skipped_identical'] as List).length;
    final preserved = (report['preserved_extension'] as List).length;
    final blocked = (report['blocked_dryrun'] as List).cast<String>();
    print('emit → $targetDir  [mode=$mode applied=${report['applied']}]');
    print('  written=$written identical=$identical '
        'preserved(ext)=$preserved blocked(dry-run)=${blocked.length} '
        'stamped=${report['stamped']}');
    if (blocked.isNotEmpty) {
      print('  ⚠ arbitrary target — re-run with --apply to write generated files:');
      for (final f in blocked) {
        print('     $f');
      }
    }
    return 0;
  } catch (e, st) {
    stderr.writeln('emit → FAIL: $e');
    stderr.writeln(st);
    return 1;
  }
}
