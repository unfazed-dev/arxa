#!/usr/bin/env python3
"""emit.py — apply a Blueprint package into a Target dir. Pure code, idempotent.

Adoption is the ONLY path code reaches a target (ADR-0002 #2). This stage reads
a blueprint package (`manifest.json` + `templates/`) and writes its templates
into a target Flutter project with write-on-diff semantics:

  - generated layer   — factory-owned. Overwritten on-diff (clean replay for
                        appbox-built). Never hand-edited.
  - extension points  — emitted ONCE as a stub, NEVER overwritten. Where the
                        operator/builder's business logic + widget bodies live.
                        Written only if ABSENT on target.

Gating (ADR-0002 #3 — byte-identical scoped to appbox-built):
  - appbox-built target (.appbox/manifest.json present) → generated layer replays
    freely; extension points preserved. Stamp refreshed.
  - new-app (no pubspec yet) → greenfield: write everything; stamp written.
  - arbitrary existing target → best-effort: DRY-RUN by default; pass --apply to
    write generated files (each reported); extension points only if absent.
    Stamp only with --adopt (do not silently claim an arbitrary project).

Idempotent: a second run with unchanged blueprint writes nothing.

Usage:
    emit.py <blueprint-dir> <target-dir> [--apply] [--adopt] [--mode MODE]
            [--supabase-url URL --supabase-publishable-key KEY]
            [--out report.json]
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def _read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


# file types the generated layer ships as BINARY (PNG brand glyphs). Text-mode
# _read would UnicodeDecodeError on the PNG header (0x89); these copy raw.
_BINARY_EXT = (".png",)


def _is_binary(rel):
    return rel.lower().endswith(_BINARY_EXT)


def _detect_appbox(target_dir):
    try:
        from detect_appbox_project import detect
        return detect(target_dir)
    except Exception:
        p = os.path.join(target_dir, ".appbox", "manifest.json")
        if not os.path.exists(p):
            return {"isAppbox": False}
        try:
            return {"isAppbox": True, "manifest": json.loads(_read(p))}
        except Exception:
            return {"isAppbox": False}


def _write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(content, bytes):
        with open(path, "wb") as f:
            f.write(content)
    else:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)


def _ensure_passkeys_web_sdk(target_dir, report):
    """Inject the Corbado Passkeys Web SDK into web/index.html when needed.

    supabase_flutter depends on `passkeys` → `passkeys_web`, whose web plugin
    auto-registers at startup: registerWith() checks `window['PasskeyAuthenticator']`,
    and if the SDK script isn't in index.html it calls window.close() (a no-op in a
    normal tab) then `PasskeyAuthenticator.init()` on `undefined` — which throws and
    aborts app bootstrap, so the Flutter view never mounts (blank web page). Native
    is unaffected. Fix per corbado docs: self-host bundle.js + add a <head> <script>.

    Scoped to web targets whose deps include passkeys/supabase; idempotent. The
    vendored bundle (assets/web/passkeys-bundle.js, v2.4.0) matches passkeys_web 2.9.0
    (the API the plugin's interop.dart binds). Bump both together if Supabase bumps
    passkeys_web. Runs in emit (not blueprint), so it never touches the snapshot golden.
    """
    index = os.path.join(target_dir, "web", "index.html")
    if not os.path.exists(index):
        return  # not a web target (or web/ not scaffolded yet)
    pubspec = os.path.join(target_dir, "pubspec.yaml")
    deps = _read(pubspec) if os.path.exists(pubspec) else ""
    if "supabase_flutter" not in deps and "passkeys" not in deps:
        return  # no plugin that needs the SDK
    html = _read(index)
    if 'src="bundle.js"' in html:
        return  # already present — idempotent
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sdk_src = os.path.join(root, "assets", "web", "passkeys-bundle.js")
    if not os.path.exists(sdk_src) or "</head>" not in html:
        return  # vendored SDK or head marker missing — skip rather than break emit
    _write(os.path.join(target_dir, "web", "bundle.js"), _read(sdk_src))
    tag = ('  <!-- Passkeys Web SDK (corbado): required by transitive passkeys_web (via\n'
           '       supabase_flutter); without it the web app boots but never mounts. -->\n'
           '  <script src="bundle.js" type="application/javascript"></script>\n')
    _write(index, html.replace("</head>", tag + "</head>", 1))
    report["written"].extend(["web/bundle.js", "web/index.html (+passkeys SDK)"])


# Drift web runtime. sqlite3.wasm ships from the sqlite3 package repo; the worker
# from the drift repo (named drift_worker.js). Keep wasm >= the sqlite3 package
# drift resolves, else web falls back to remote-only (handled gracefully).
_DRIFT_WEB_ASSETS = {
    "sqlite3.wasm":
        "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.3/sqlite3.wasm",
    "drift_worker.js":
        "https://github.com/simolus3/drift/releases/download/drift-2.34.0/drift_worker.js",
}


def _ensure_drift_web_assets(target_dir, report):
    """Place Drift's web runtime (sqlite3 WebAssembly + worker) into web/ so local
    persistence works on Flutter web too (browsers ship no sqlite3; the .wasm must
    be served as application/wasm — Flutter's dev server already does).

    Best-effort, idempotent, web-only: a fetch failure NEVER breaks emit — it drops
    a web/drift-web-setup.md breadcrumb and the cached repository degrades to
    remote-only until the assets are present. Mirrors _ensure_passkeys_web_sdk;
    runs in emit (not blueprint), so it never touches the snapshot golden.
    """
    web = os.path.join(target_dir, "web")
    if not os.path.isdir(web):
        return  # not a web target
    pubspec = os.path.join(target_dir, "pubspec.yaml")
    if "drift" not in (_read(pubspec) if os.path.exists(pubspec) else ""):
        return  # no local persistence in this app
    import urllib.request
    for name, url in _DRIFT_WEB_ASSETS.items():
        dst = os.path.join(web, name)
        if os.path.exists(dst):
            continue  # idempotent
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                data = resp.read()
            with open(dst, "wb") as f:
                f.write(data)
            report["written"].append(f"web/{name}")
        except Exception:
            note = os.path.join(web, "drift-web-setup.md")
            if not os.path.exists(note):
                _write(note,
                       "# Drift web assets (local persistence on web)\n\n"
                       "Place these two files (from the drift release matching `drift` "
                       "in pubspec.yaml) into `web/`:\n\n"
                       + "".join(f"- `{n}` — {u}\n" for n, u in _DRIFT_WEB_ASSETS.items())
                       + "\nServe `.wasm` as `application/wasm`. Until present, the app "
                       "runs remote-only on web (offline cache disabled).\n")
                report["written"].append("web/drift-web-setup.md")
            break  # network unavailable — one breadcrumb is enough
    return


def _ensure_svg_assets_declared(target_dir, report):
    """Declare assets/svg/ AND assets/png/ in pubspec.flutter when the app bundles them.

    The generators write design-extracted vectors to assets/svg/*.svg (SvgPicture)
    and the rasterized brand glyphs to assets/png/*.png (native UIKit decode +
    Android Bitmap) — but the pubspec template ships only `uses-material-design:
    true`. Without this the glyphs throw `Unable to load asset` at runtime (the
    iOS Google G blanked because the PNG wasn't declared, so the asset loaded as
    the SVG and SVGKit mis-rendered it). Mirrors _ensure_passkeys_web_sdk/
    _ensure_drift_web_assets: emit-time, file-aware, idempotent, never touches the
    blueprint golden.

    Directory form (`- assets/svg/`) bundles every asset without enumerating each;
    only emitted when the dir actually holds files, so a design with no vectors
    never declares a missing dir (which would fail `flutter build`). ponytail:
    string-inject the block; no YAML parser dep — add one if we ever need
    structured pubspec edits.
    """
    dirs = []
    for sub in ("svg", "png"):
        d = os.path.join(target_dir, "assets", sub)
        if os.path.isdir(d) and any(os.scandir(d)):
            dirs.append(sub)
    if not dirs:
        return  # no extracted vectors/rasters → nothing to declare
    pubspec = os.path.join(target_dir, "pubspec.yaml")
    if not os.path.exists(pubspec):
        return
    text = _read(pubspec)
    lines = "".join("    - assets/%s/\n" % s for s in dirs)
    changed = False
    if "\n  assets:\n" in text:  # an assets: block already exists under flutter:
        for sub in dirs:
            if "assets/%s/" % sub not in text:
                text = text.replace("\n  assets:\n", "\n  assets:\n    - assets/%s/\n" % sub, 1)
                changed = True
    elif "  uses-material-design: true\n" in text:
        text = text.replace("  uses-material-design: true\n",
                            "  uses-material-design: true\n  assets:\n" + lines, 1)
        changed = True
    elif "\nflutter:\n" in text:
        text = text.replace("\nflutter:\n", "\nflutter:\n  assets:\n" + lines, 1)
        changed = True
    # else: no flutter: block to extend — leave untouched rather than break emit
    if changed:
        _write(pubspec, text)
        report["written"].append("pubspec.yaml (+%s)" % "/+".join("assets/%s/" % s for s in dirs))


def _stamp_native_names(target_dir, display_name, report):
    """Reassert the design-derived app display name into the 3 platform manifests.

    `flutter create` (run by `stacked create app` or manually) seeds these from
    the project/dir name; the factory derives the name from the design <title>,
    so emit stamps the brand everywhere -> web <title>, android launcher label,
    iOS home-screen name all read the same string (e.g. 'Atlet', not
    bundle/target/Target).

    Targeted + idempotent: rewrites ONLY the label/title/CFBundle strings, never
    the whole file; skips if already correct or file absent. Gated by the caller
    (replay_ok or apply) so an arbitrary existing target in dry-run is untouched.
    ponytail: regex-replace the one field per platform; no plist/manifest parser
    dep. Add a real plist parser if we ever need structured Info.plist edits.
    On a appbox-replay a hand-edited label IS reasserted -- use --app-name to set a
    different name rather than hand-editing these manifests.
    """
    if not display_name:
        return  # old blueprint manifest without displayName -- nothing to stamp
    stamped = []

    index = os.path.join(target_dir, "web", "index.html")
    if os.path.exists(index):
        txt = _read(index)
        new = re.sub(r"<title[^>]*>.*?</title>",
                     lambda m: f"<title>{display_name}</title>",
                     txt, count=1, flags=re.I | re.S)
        if new != txt:
            _write(index, new); stamped.append("web/index.html (<title>)")

    am = os.path.join(target_dir, "android", "app", "src", "main", "AndroidManifest.xml")
    if os.path.exists(am):
        xml = _read(am)
        new = re.sub(r'(android:label=")[^"]*(")',
                     lambda m: f'{m.group(1)}{display_name}{m.group(2)}',
                     xml, count=1)
        reasons = ["android:label"] if new != xml else []
        # Android predictive-back: Flutter 3.44 already defaults Android page
        # transitions to PredictiveBackPageTransitionsBuilder, but the OS-level back
        # PEEK animation needs this <application> flag (API 33+). Additive +
        # idempotent; iOS Cupertino slide + edge-swipe-back is the framework default
        # and is deliberately left untouched (no pageTransitionsTheme override).
        if "enableOnBackInvokedCallback" not in new:
            bumped = re.sub(r"(<application\b)",
                            r'\1 android:enableOnBackInvokedCallback="true"', new, count=1)
            if bumped != new:
                new = bumped; reasons.append("predictive-back")
        if new != xml:
            _write(am, new)
            stamped.append(f"android/AndroidManifest.xml ({' + '.join(reasons)})")

    info = os.path.join(target_dir, "ios", "Runner", "Info.plist")
    if os.path.exists(info):
        plist = _read(info)
        new = plist
        for key in ("CFBundleDisplayName", "CFBundleName"):
            new = re.sub(rf'(<key>{key}</key>\s*<string>)[^<]*(</string>)',
                         lambda m: f'{m.group(1)}{display_name}{m.group(2)}',
                         new, count=1, flags=re.I)
        if new != plist:
            _write(info, new); stamped.append("ios/Runner/Info.plist (CFBundleDisplay/Name)")

    if stamped:
        report["written"].extend(stamped)


_EXPRESSIVE_KT = r'''package __PKG__

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
// the selected item renders (proven via probe-runner: one 142px item centered in
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
    // became valid — proven via probe-runner).
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
    // measures to content width → only the selected item renders (probe-runner:
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
'''

_MAINACTIVITY_KT = r'''package __PKG__

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
'''


def _ensure_android_expressive_compose(target_dir, platforms, report):
    """Wire true Android Material 3 Expressive (Jetpack Compose) primitives into
    the `flutter create`/`stacked create` Android scaffold: a Compose PlatformView
    the Dart `expressive` family renders via AndroidView.

    Runs in emit (NOT blueprint), so it never touches the snapshot golden — it
    patches generated platform scaffold idempotently, mirroring
    _ensure_passkeys_web_sdk / _ensure_drift_web_assets. Android-only; no-op when
    the design isn't scoped to android or the scaffold is absent.

    Three edits, each marker-guarded:
      1. Kotlin: ExpressivePlatformView.kt + rewrite MainActivity.kt
         (FlutterFragmentActivity + register the factory).
      2. settings.gradle.kts: declare the Compose compiler plugin (version pinned
         to the scaffold's Kotlin version — must match exactly).
      3. app/build.gradle.kts: apply the plugin + buildFeatures.compose + deps.
    """
    if platforms and "android" not in platforms:
        return  # design not scoped to android
    app = os.path.join(target_dir, "android", "app")
    if not os.path.isdir(app):
        return  # android not scaffolded
    # locate MainActivity.kt → its package + kotlin source dir
    main_kt = None
    for root, _dirs, files in os.walk(os.path.join(app, "src", "main")):
        if "MainActivity.kt" in files:
            main_kt = os.path.join(root, "MainActivity.kt")
            break
    if not main_kt:
        return  # non-Kotlin scaffold (Java) — skip rather than break emit
    pkg = "com.example.app"
    m = re.search(r"^package\s+([\w.]+)", _read(main_kt), flags=re.M)
    if m:
        pkg = m.group(1)
    kt_dir = os.path.dirname(main_kt)
    written = []

    # 1. Kotlin sources
    _write(os.path.join(kt_dir, "ExpressivePlatformView.kt"),
           _EXPRESSIVE_KT.replace("__PKG__", pkg))
    written.append("android ExpressivePlatformView.kt")
    new_main = _MAINACTIVITY_KT.replace("__PKG__", pkg)
    if _read(main_kt) != new_main:
        _write(main_kt, new_main)
        written.append("android MainActivity.kt (FlutterFragmentActivity + factory)")

    # 2. settings.gradle.kts — Compose compiler plugin + AGP floor for the alpha
    #    Compose track (material3 1.5.x → Compose 1.12.x needs AGP >= 9.1.0).
    settings = os.path.join(target_dir, "android", "settings.gradle.kts")
    if os.path.exists(settings):
        s0 = _read(settings)
        s = s0

        def _bump_agp(m):
            ver = m.group(2)
            parts = [int(x) for x in ver.split(".")]
            return m.group(1) + ("9.1.0" if parts < [9, 1, 0] else ver) + m.group(3)

        s = re.sub(r'(id\("com\.android\.application"\)\s+version\s+")([\d.]+)(")',
                   _bump_agp, s)
        if "kotlin.plugin.compose" not in s:
            km = re.search(r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([\d.]+)"', s)
            kver = km.group(1) if km else "2.1.0"
            anchor = re.search(r'id\("org\.jetbrains\.kotlin\.android"\)[^\n]*\n', s)
            if anchor:
                line = f'    id("org.jetbrains.kotlin.plugin.compose") version "{kver}" apply false\n'
                s = s[:anchor.end()] + line + s[anchor.end():]
        if s != s0:
            _write(settings, s)
            written.append("android settings.gradle.kts (+compose plugin, AGP>=9.1.0)")

    # 3. app/build.gradle.kts — apply plugin + buildFeatures.compose + deps
    gradle = os.path.join(app, "build.gradle.kts")
    if os.path.exists(gradle):
        g = _read(gradle)
        if "appbox:compose-embed" not in g:
            g = re.sub(r'(id\("dev\.flutter\.flutter-gradle-plugin"\)\s*\n)',
                       r'\1    id("org.jetbrains.kotlin.plugin.compose")\n', g, count=1)
            g += (
                "\n// appbox:compose-embed — true Android Material 3 Expressive via Jetpack\n"
                "// Compose, embedded as a Flutter PlatformView (see ExpressivePlatformView.kt).\n"
                "android {\n"
                "    // material3 1.5.0-alpha (Compose 1.12.x) requires compileSdk 37.\n"
                "    compileSdk = 37\n"
                "    buildFeatures {\n"
                "        compose = true\n"
                "    }\n"
                "}\n"
                "dependencies {\n"
                "    // 1.5.0-alpha track: MaterialExpressiveTheme + the expressive\n"
                "    // opt-in are internal in stable 1.4.0; public only on 1.5.0-alpha.\n"
                '    implementation("androidx.compose.material3:material3:1.5.0-alpha22")\n'
                '    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.0")\n'
                '    implementation("androidx.savedstate:savedstate-ktx:1.2.1")\n'
                "}\n"
            )
            _write(gradle, g)
            written.append("android app/build.gradle.kts (+compose)")

    # 4. gradle wrapper — AGP 9.1.x requires Gradle >= 9.3.1.
    wrap = os.path.join(target_dir, "android", "gradle", "wrapper",
                        "gradle-wrapper.properties")
    if os.path.exists(wrap):
        w0 = _read(wrap)

        def _bump_gradle(m):
            ver = m.group(2)
            parts = [int(x) for x in ver.split(".")]
            return m.group(1) + ("9.3.1" if parts < [9, 3, 1] else ver) + m.group(3)

        w = re.sub(r'(gradle-)([\d.]+)(-(?:all|bin)\.zip)', _bump_gradle, w0)
        if w != w0:
            _write(wrap, w)
            written.append("android gradle wrapper (>=9.3.1)")

    if written:
        report["written"].extend(written)


def emit(blueprint_dir, target_dir, apply=False, adopt=False,
         supabase_url=None, supabase_publishable_key=None):
    manifest_path = os.path.join(blueprint_dir, "manifest.json")
    templates_dir = os.path.join(blueprint_dir, "templates")
    manifest = json.loads(_read(manifest_path))
    gen_set = set(manifest.get("generatedLayer", []))
    ext_set = set(manifest.get("extensionPoints", []))

    appbox = _detect_appbox(target_dir)
    is_appbox = bool(appbox.get("isAppbox"))
    is_new = not os.path.exists(os.path.join(target_dir, "pubspec.yaml"))

    # gating: when may generated files overwrite without --apply?
    replay_ok = is_appbox or is_new
    stamp = is_new or is_appbox or adopt

    report = {
        "target": target_dir, "isAppbox": is_appbox, "isNewApp": is_new,
        "replay": replay_ok, "applied": apply,
        "written": [], "skipped_identical": [], "preserved_extension": [],
        "blocked_dryrun": [], "stamped": False,
    }

    all_rel = sorted(gen_set | ext_set)
    for rel in all_rel:
        src = os.path.join(templates_dir, rel)
        if not os.path.exists(src):
            continue
        # binary assets (PNG brand glyphs) read/write raw; text otherwise.
        if _is_binary(rel):
            content = _read_bytes(src)
        else:
            content = _read(src)
        dst = os.path.join(target_dir, rel)
        is_ext = rel in ext_set

        if os.path.exists(dst):
            try:
                existing = _read_bytes(dst) if _is_binary(rel) else _read(dst)
            except Exception:
                existing = None
            if existing == content:
                report["skipped_identical"].append(rel)
                continue
            if is_ext:
                # extension point already present → preserve (operator owns it)
                report["preserved_extension"].append(rel)
                continue
            # generated + differs
            if replay_ok or apply:
                _write(dst, content)
                report["written"].append(rel)
            else:
                report["blocked_dryrun"].append(rel)
        else:
            # absent — write regardless of gating (it's additive; no clobber)
            _write(dst, content)
            report["written"].append(rel)

    # Supabase wiring (optional; env-backed, never committed)
    if (supabase_url and supabase_publishable_key) and (replay_ok or apply):
        env_path = os.path.join(target_dir, ".env")
        _write(env_path, f"SUPABASE_URL={supabase_url}\n"
                         f"SUPABASE_PUBLISHABLE_KEY={supabase_publishable_key}\n")
        report["written"].append(".env")

    # web bootstrap: passkeys_web (via supabase_flutter) hard-requires its JS SDK in
    # index.html or the web app boots-but-never-mounts (blank). See fn docstring.
    if replay_ok or apply:
        _ensure_passkeys_web_sdk(target_dir, report)
        _ensure_drift_web_assets(target_dir, report)
        _ensure_svg_assets_declared(target_dir, report)
        _stamp_native_names(target_dir, manifest.get("displayName"), report)
        _ensure_android_expressive_compose(target_dir, manifest.get("platforms"), report)

    # appbox stamp
    if stamp and (replay_ok or apply or is_new):
        stamp_dir = os.path.join(target_dir, ".appbox")
        os.makedirs(stamp_dir, exist_ok=True)
        stamp_obj = {
            "factoryVersion": manifest.get("factoryVersion"),
            "source": manifest.get("source"),
            "stack": manifest.get("stack"),
            "lastMode": manifest.get("lastMode", "new-app"),
            "blueprintHash": manifest.get("blueprintHash"),
            "templatesVersion": manifest.get("templatesVersion"),
            "appName": manifest.get("appName"),
            "displayName": manifest.get("displayName"),
            "platforms": manifest.get("platforms"),
        }
        with open(os.path.join(stamp_dir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(stamp_obj, f, indent=2, sort_keys=True)
            f.write("\n")
        report["stamped"] = True

    return report


def main(argv):
    if len(argv) < 3:
        print("usage: emit.py <blueprint-dir> <target-dir> [--apply] [--adopt] "
              "[--supabase-url U --supabase-publishable-key K] [--out report.json]",
              file=sys.stderr)
        return 2
    blueprint_dir, target_dir = argv[1], argv[2]
    apply = "--apply" in argv
    adopt = "--adopt" in argv
    supabase_url = supabase_publishable_key = out = None
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--supabase-url" and i + 1 < len(argv):
            supabase_url = argv[i + 1]; i += 2
        elif a == "--supabase-publishable-key" and i + 1 < len(argv):
            supabase_publishable_key = argv[i + 1]; i += 2
        elif a == "--out" and i + 1 < len(argv):
            out = argv[i + 1]; i += 2
        else:
            i += 1

    r = emit(blueprint_dir, target_dir, apply, adopt, supabase_url, supabase_publishable_key)
    if out:
        _write(out, json.dumps(r, indent=2, sort_keys=True) + "\n")

    mode = "appbox-replay" if r["isAppbox"] else ("new-app" if r["isNewApp"] else "arbitrary")
    print(f"emit → {target_dir}  [mode={mode} applied={r['applied']}]")
    print(f"  written={len(r['written'])} identical={len(r['skipped_identical'])} "
          f"preserved(ext)={len(r['preserved_extension'])} "
          f"blocked(dry-run)={len(r['blocked_dryrun'])} stamped={r['stamped']}")
    if r["blocked_dryrun"]:
        print("  ⚠ arbitrary target — re-run with --apply to write generated files:")
        for f in r["blocked_dryrun"]:
            print(f"     {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
