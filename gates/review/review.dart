// ignore_for_file: avoid_print
// enforce_design.dart — the stacked-kit-designer's enforcement gate.
//
// A pure-Dart static analyzer the skill runs on its own emitted view files BEFORE
// declaring "done". The skill-owned check the model runs on its own output. The
// shape — pure functions, named
// checks, exit(1) on fail, --self-test calibrated on a real fixture where every
// negative fails for the right reason — is the standard discipline for a
// freeze-validity gate, reimplemented here for Dart, owned by THIS skill.
//
// It does NOT replace `flutter analyze` (compile/type checking) or `flutter run`
// (perceptual/Checkpoint 4 verification). It catches the kit-specific slop and
// contract violations that the Dart compiler accepts but the skill forbids:
//
//   1. no_stock_icons       — Icons.<x> outside allowlisted debug contexts → AppBoxKitGlyphs.*
//   2. no_hardcoded_colors  — Color(0x…) / Color.fromARGB() / Color.fromRGBO() /
//                             CupertinoColors.* / Colors.* literals in view files → AppBoxKitColors.*
//   3. no_raw_dart_io       — `import 'dart:io'` (incl. `show`/`as` combiners) + raw
//                             Platform.is* → AppBoxKitPlatform
//   4. kit_theme_used      — unconfigured MaterialApp( or MaterialApp.router( without
//                             appBoxKitLightTheme/appBoxKitDarkTheme
//   4b. no_stock_cta_buttons — ElevatedButton/FilledButton/TextButton as CTAs in view
//                             code → AppBoxKitNativeButton
//   4c. no_stock_loading_indicator — CircularProgressIndicator in view code →
//                             AppBoxKitNativeLoadingIndicator
//   4d. no_invented_native_widgets — AppBoxKitNative<X> not in the matrix allowlist
//                             (e.g. AppBoxKitNativeDialog) → never invent a wrapper the kit lacks (#0c)
//   4e. valid_dart_syntax   — brace/paren/bracket balance (catches truncated files the
//                             regex gate would silently call "clean")
//   5. form_factor_files    — for each <surface>_view.dart, the 4 sibling files exist
//   6. design_system_doc    — design-system.md exists in the surface dir (mandatory)
//   7. iteration_drift      — for a vN (N≥2) surface, no DROPPED AppBoxKitGlyphs/AppBoxKitColors vs prior
//   8. no_cross_shell_imports — view trees stay shell-private: a file under
//                             /ui/views/<shellA>/ never imports /ui/views/<shellB>/
//                             (overlay subdirs bottom_sheets|dialogs|snackbars exempt)
//   9. no_hardcoded_strings — Text('…')/label: '…' literals with 3+ ASCII letters
//                             in view files → copy comes from the ARB catalogs
//                             via AppLocalizations (the i18n discipline)
//
// Closed blind spots (each has a stress scenario under scripts/tests/):
//   G1 MaterialApp.router( (navigator2 form)  — caught by kit_theme_used
//   G2 Color.fromARGB()/fromRGBO()            — caught by no_hardcoded_colors
//   G3 `import 'dart:io' show Platform;`      — caught by no_raw_dart_io
//   G4 Icons.* / Color.* inside string lits   — stripped before matching (no false positive)
//   G6 _v3+ surfaces iterating a _v2          — caught by iteration_drift (any vN≥2)
//   G7 lone non-view .dart file               — per-file checks only (no form-factor noise)
//
// Usage:
//   dart scripts/enforce_design.dart <surface-dir-or-view-file> [--json] [--self-test]
//
// A "surface dir" is lib/ui/views/<shell>/<surface>/ containing the 5-file set.
// A "view file" is the <surface>_view.dart shell. Either is accepted.

import 'dart:convert';
import 'dart:io';

// ---------- patterns ----------

// Icons.<name> usage. Allowlist: comments, debug-only chips, the kit's own
// appbox_kit_glyphs.dart (where the Material IconData is the source of truth).
final _iconsUsage = RegExp(r'\bIcons\.([a-zA-Z0-9_]+)');

// Color(0x...) literal — the hardcoded-color smell.
final _colorLiteral = RegExp(r'\bColor\(\s*0x([0-9A-Fa-f]+)\s*\)');

// Color.fromARGB(...) / Color.fromRGBO(...) — the SAME hardcoded-color smell via
// the named-arg constructors. Closes the G2 evasion (a sloppy author reached for
// the constructor the 0x-literal regex doesn't match).
final _colorFromArgb = RegExp(r'\bColor\.fromARGB\s*\(');
final _colorFromRgba = RegExp(r'\bColor\.fromRGBO\s*\(');

// CupertinoColors.* / Colors.* literals (not colorScheme / AppBoxKitColors).
final _cupertinoColorsLiteral = RegExp(r'\bCupertinoColors\.([a-zA-Z0-9_]+)');
final _colorsLiteralUsage =
    RegExp(r'\bColors\.([a-zA-Z0-9_]+)');

// import 'dart:io' ... — unconditional import breaks web compile. The optional
// `.*` absorbs a trailing combiner (`show Platform`, `as io`, deferred `deferred
// as`), closing the G3 evasion: `import 'dart:io' show Platform;` is the same
// web-break and must trip the check.
// (Plain string + escapes: avoids raw-string/nested-quote parser pitfalls.)
final _dartIoImport =
    RegExp("^\\s*import\\s+['\\\"]dart:io['\\\"].*;", multiLine: true);

// raw Platform.is* — use AppBoxKitPlatform instead (web-safe).
final _rawPlatform = RegExp(r'\bPlatform\.(isIOS|isAndroid|isMacOS|isWindows|isLinux)\b');

// Stock CTA buttons as primary/secondary actions → AppBoxKitNativeButton. The anti-slop
// blacklist names these explicitly. Allowlist: the kit's own widget wrappers
// (kit_native_*.dart) use FilledButton.tonal internally — that's correct, they're
// the wrapper layer, not app view code.
final _stockCtaButton =
    RegExp(r'\b(ElevatedButton|FilledButton|TextButton|OutlinedButton|CupertinoButton)\b');

// Stock CircularProgressIndicator everywhere → AppBoxKitNativeLoadingIndicator. Same
// allowlist rationale (the kit's own progress wrappers use it internally).
final _stockLoadingIndicator =
    RegExp(r'\b(CircularProgressIndicator|LinearProgressIndicator)\b');

// Invented AppBoxKitNative* widget references. The native-component matrix
// (NATIVE_COMPONENTS.md) is the SSOT for which AppBoxKitNative* widgets actually
// exist; inventing a name the matrix doesn't list (AppBoxKitNativeDialog,
// AppBoxKitNativeDatePicker, AppBoxKitNativeCarousel…) is the #0c gate's "never invent a
// AppBoxKitNative* class the matrix doesn't list" rule. This constant is the
// authoritative allowlist, sourced from NATIVE_COMPONENTS.md.
const knownKitNativeWidgets = <String>{
  'AppBoxKitNativeAppBar',
  'AppBoxKitNativeButton',
  'AppBoxKitNativeChromeGate',
  'AppBoxKitNativeFab',
  'AppBoxKitNativeFabMenu',
  'AppBoxKitNativeIconButton',
  'AppBoxKitNativeInputBar',
  'AppBoxKitNativeLoadingIndicator',
  'AppBoxKitNativeNavigationRail',
  'AppBoxKitNativePopupMenu',
  'AppBoxKitNativeProgress',
  'AppBoxKitNativeRangeSlider',
  'AppBoxKitNativeSearchBar',
  'AppBoxKitNativeSegmentedControl',
  'AppBoxKitNativeSlider',
  'AppBoxKitNativeSplitButton',
  'AppBoxKitNativeSwitch',
  'AppBoxKitNativeTabBar',
  'AppBoxKitNativeTextField',
  'AppBoxKitNativeToolbar',
};
// Matches any `AppBoxKitNative<Identifier>` reference so the invented-name check can
// flag names NOT in the allowlist above.
final _anyKitNativeRef = RegExp(r'\bAppBoxKitNative([A-Z][a-zA-Z0-9]*)');

// Card/tile/banner/panel CONTENT surfaces must compose on AppBoxKitGlassCard (the ✅
// "glass card" matrix row: Liquid Glass iOS 26 / M3E Material Card Android), never
// a hand-rolled colored `Material(color:` / decorated `Container(…BoxDecoration)`.
// The check fires ONLY when a file declares such a widget class (narrow by design;
// blast-radius-measured). `// flutter-only:` opts a surface out (read on raw src).
final _cardSurfaceClass =
    RegExp(r'\bclass\s+[A-Za-z0-9_]*(?:Tile|Card|Banner|Panel)\b');
final _rawColoredSurface =
    RegExp(r'\bMaterial\(\s*color:|\bdecoration:\s*(?:const\s+)?BoxDecoration');
final _flutterOnlyOptOut = RegExp(r'//\s*flutter-only:');

/// One row of the native-surface ban matrix (check 4g). [stock] is the raw
/// Flutter widget/call an app author might reach for; [kit] is the AppBoxKitNative*
/// surface that must be used instead; [surface] labels the matrix row.
class _NativeSurfaceBan {
  final RegExp stock;
  final String kit;
  final String surface;
  const _NativeSurfaceBan(this.stock, this.kit, this.surface);
}

/// The native-surface ban matrix — every ✅ NATIVE_COMPONENTS.md row that has a
/// stock Flutter equivalent an app author could reach for instead of the kit
/// widget. This list IS the matrix: adding a native surface = adding one row, so
/// the pipeline can't silently miss a surface. It is the whole-matrix sibling of
/// 4b/4c (buttons/loaders) and 4f (card surfaces). Chrome bars (app bar / tab bar
/// / icon button) are owned by the review gate's 1c–1w and deliberately not
/// duplicated here. Each pattern matches the constructor call (an optional named
/// constructor like `.adaptive`/`.extended` included) or, for the two overlay
/// APIs, the call site.
final _nativeSurfaceBans = <_NativeSurfaceBan>[
  _NativeSurfaceBan(
      RegExp(r'\b(?:TextField|TextFormField|CupertinoTextField)(?:\.\w+)?\s*\('),
      'AppBoxKitNativeTextField',
      'text field'),
  _NativeSurfaceBan(RegExp(r'\b(?:Switch|CupertinoSwitch)(?:\.\w+)?\s*\('),
      'AppBoxKitNativeSwitch', 'switch'),
  _NativeSurfaceBan(RegExp(r'\b(?:Slider|CupertinoSlider)(?:\.\w+)?\s*\('),
      'AppBoxKitNativeSlider', 'slider'),
  _NativeSurfaceBan(
      RegExp(r'\bRangeSlider(?:\.\w+)?\s*\('), 'AppBoxKitNativeRangeSlider', 'range slider'),
  _NativeSurfaceBan(RegExp(r'\bFloatingActionButton(?:\.\w+)?\s*\('),
      'AppBoxKitNativeFab / AppBoxKitNativeFabMenu', 'FAB'),
  _NativeSurfaceBan(
      RegExp(r'\b(?:SegmentedButton|CupertinoSegmentedControl|CupertinoSlidingSegmentedControl)(?:\.\w+)?\s*\('),
      'AppBoxKitNativeSegmentedControl',
      'segmented control'),
  _NativeSurfaceBan(
      RegExp(r'\b(?:SearchBar|SearchAnchor|CupertinoSearchTextField)(?:\.\w+)?\s*\('),
      'AppBoxKitNativeSearchBar',
      'search bar'),
  _NativeSurfaceBan(RegExp(r'\b(?:PopupMenuButton|MenuAnchor)(?:\.\w+)?\s*\('),
      'AppBoxKitNativePopupMenu / AppBoxKitNativeSplitButton', 'popup / menu'),
  _NativeSurfaceBan(RegExp(r'\bNavigationRail(?:\.\w+)?\s*\('),
      'AppBoxKitNativeNavigationRail', 'navigation rail'),
  _NativeSurfaceBan(RegExp(r'\.showSnackBar\s*\(|\bSnackBar(?:\.\w+)?\s*\('),
      'appBoxKitShowNativeToast()', 'toast / snackbar'),
  _NativeSurfaceBan(RegExp(r'\bshowModalBottomSheet\s*\('), 'appBoxKitShowNativeSheet()',
      'bottom sheet'),
];

// True iff `path` is a kit-internal widget/palette/glyph file (the source of
// truth that legitimately uses Material primitives) or a test. Used by the
// anti-slop checks to avoid false-positiving on the kit's own wrappers.
bool _isKitInternalOrTest(String path) {
  if (path.endsWith('appbox_kit_glyphs.dart') ||
      path.endsWith('appbox_kit_colors.dart') ||
      path.contains('/widgets/appbox_kit_') || // the kit's own wrapper files
      path.contains('/test/') ||
      path.endsWith('_test.dart')) {
    return true;
  }
  return false;
}

// MaterialApp( / MaterialApp.router( — either constructor form needs the kit
// theme. Stacked navigator2 apps use MaterialApp.router (the showcase app does,
// at lib/main.dart), so the plain `(` form alone missed every real app. G1.
final _materialApp = RegExp(r'\bMaterialApp(?:\.router)?\s*\(');

// AppBoxKitGlyphs.<name> / AppBoxKitColors.<name> references (for iteration drift + allowlist logic).
final _kitGlyphsRef = RegExp(r'\bAppBoxKitGlyphs\.([a-zA-Z0-9_]+)');
final _kitColorsRef = RegExp(r'\bAppBoxKitColors\.([a-zA-Z0-9_]+)');
final _kitDarkColorsRef = RegExp(r'\bAppBoxKitDarkColors\.([a-zA-Z0-9_]+)');

// Text('…') / Text("…") and label: '…' / label: "…" — a string literal sitting
// in a user-visible copy slot. Groups 1/2 hold the literal's contents. The i18n
// discipline: copy comes from the ARB catalogs via AppLocalizations, never a
// hardcoded literal in a view.
final _textOrLabelLiteral = RegExp(
    r"(?:\bText\(\s*|\blabel\s*:\s*)'((?:\\.|[^'\\])*)'"
    r'|(?:\bText\(\s*|\blabel\s*:\s*)"((?:\\.|[^"\\])*)"');

// The scaffolder's stub header. Stub files carry placeholder KEYS
// (Text('projects.home')) that the builder replaces with AppLocalizations
// lookups, so a STRUCTURE ONLY file is exempt from no_hardcoded_strings.
final _scaffolderStubHeader =
    RegExp(r'//\s*appbox-scaffolder:[^\n]*STRUCTURE ONLY');

// Any file under the view tree — no_hardcoded_strings scopes to view files.
final _viewsTree = RegExp(r'/ui/views/');

// ---------- check results ----------

class CheckResult {
  final String name;
  final bool ok;
  final String message;
  CheckResult(this.name, this.ok, this.message);
}

// ---------- individual checks (pure functions) ----------

/// Check 1: no stock Icons.* glyphs. Allow: inside comments, in appbox_kit_glyphs.dart
/// (the registry's source of truth), or in test files.
CheckResult checkNoStockIcons(String src, String path) {
  if (path.endsWith('appbox_kit_glyphs.dart')) {
    return CheckResult('no_stock_icons', true,
        'skipped (appbox_kit_glyphs.dart is the registry source of truth)');
  }
  if (path.contains('/test/') || path.endsWith('_test.dart')) {
    return CheckResult('no_stock_icons', true, 'skipped (test file)');
  }
  // Strip comments AND string literals so an Icons.* mentioned only in a comment
  // (e.g. "// don't use Icons.home") or a string ("..." the bad path is
  // Icons.home ...") doesn't trip the check. G4: the comment-stripper alone left
  // string-embedded tokens firing false positives.
  final stripped = _stripNoise(src);
  final matches = _iconsUsage.allMatches(stripped).toList();
  if (matches.isEmpty) {
    return CheckResult('no_stock_icons', true, 'no stock Icons.* usage');
  }
  final glyphs = matches.map((m) => 'Icons.${m.group(1)}').toSet();
  return CheckResult('no_stock_icons', false,
      'stock Material Icons.* found: $glyphs. Use AppBoxKitGlyphs.* (add an entry to '
      'appbox_kit_glyphs.dart if missing). Icons.* reads as "untuned Flutter".');
}

/// Check 2: no hardcoded Color(0x…) / CupertinoColors.* / Colors.* in view files.
/// Allow: the kit's own appbox_kit_colors.dart (source of truth), test files, comments.
CheckResult checkNoHardcodedColors(String src, String path) {
  if (path.endsWith('appbox_kit_colors.dart')) {
    return CheckResult('no_hardcoded_colors', true,
        'skipped (appbox_kit_colors.dart is the palette source of truth)');
  }
  if (path.contains('/test/') || path.endsWith('_test.dart')) {
    return CheckResult('no_hardcoded_colors', true, 'skipped (test file)');
  }
  final stripped = _stripNoise(src);
  final colorLits = _colorLiteral.allMatches(stripped).map((m) => 'Color(0x${m.group(1)})').toSet();
  // Named-arg constructors are the same ad-hoc-color smell (G2).
  final argbLits = _colorFromArgb.hasMatch(stripped) ? {'Color.fromARGB()'} : <String>{};
  final rgbaLits = _colorFromRgba.hasMatch(stripped) ? {'Color.fromRGBO()'} : <String>{};
  final cupLits = _cupertinoColorsLiteral.allMatches(stripped).map((m) => 'CupertinoColors.${m.group(1)}').toSet();
  // Colors.white / Colors.black / Colors.transparent are occasionally legit
  // (the kit documents these as deliberate platform-token matches); allow those three.
  final colorsLits = _colorsLiteralUsage
      .allMatches(stripped)
      .map((m) => 'Colors.${m.group(1)}')
      .where((s) => !s.contains('.white') && !s.contains('.black') && !s.contains('.transparent'))
      .toSet();
  final all = {...colorLits, ...argbLits, ...rgbaLits, ...cupLits, ...colorsLits};
  if (all.isEmpty) {
    return CheckResult('no_hardcoded_colors', true, 'no hardcoded color literals');
  }
  return CheckResult('no_hardcoded_colors', false,
      'hardcoded color literal(s) in view code: $all. Use AppBoxKitColors.* / AppBoxKitDarkColors.* '
      'or Theme.of(context).colorScheme.*. Every ad-hoc color dilutes the palette.');
}

/// Check 3: no unconditional `import 'dart:io'` and no raw Platform.is*.
CheckResult checkNoRawDartIo(String src, String path) {
  if (path.contains('/test/') || path.endsWith('_test.dart')) {
    return CheckResult('no_raw_dart_io', true, 'skipped (test file)');
  }
  // Comments only (NOT _stripNoise): the `import 'dart:io';` directive contains
  // a string literal we must read to detect it — string-stripping would blank
  // `'dart:io'` and the import regex would never match. Comments are still
  // stripped so a `// import 'dart:io';` note doesn't fire.
  final stripped = _stripComments(src);
  final ioImport = _dartIoImport.firstMatch(stripped);
  final rawPlat = _rawPlatform.allMatches(stripped).map((m) => 'Platform.${m.group(1)}').toSet();
  final problems = <String>[];
  if (ioImport != null) {
    problems.add("unconditional `import 'dart:io'` (fails to compile on web — and the "
        'mobile file renders on phone-width browsers)');
  }
  if (rawPlat.isNotEmpty) {
    problems.add('raw $rawPlat (use AppBoxKitPlatform — web-safe, kIsWeb-guarded). Or better, '
        'let a AppBoxKitNative* widget do the platform branch for you.');
  }
  if (problems.isEmpty) {
    return CheckResult('no_raw_dart_io', true, 'no dart:io / raw Platform usage');
  }
  return CheckResult('no_raw_dart_io', false, problems.join(' · '));
}

/// Check 4: if MaterialApp( appears, appBoxKitLightTheme/appBoxKitDarkTheme must too.
CheckResult checkKitThemeUsed(String src, String path) {
  if (path.contains('/test/') || path.endsWith('_test.dart')) {
    return CheckResult('kit_theme_used', true, 'skipped (test file)');
  }
  final stripped = _stripNoise(src);
  if (!_materialApp.hasMatch(stripped)) {
    return CheckResult('kit_theme_used', true, 'no MaterialApp( in this file');
  }
  final hasKitTheme = stripped.contains('appBoxKitLightTheme') || stripped.contains('appBoxKitDarkTheme');
  if (hasKitTheme) {
    return CheckResult('kit_theme_used', true, 'MaterialApp uses kit theme');
  }
  return CheckResult('kit_theme_used', false,
      'MaterialApp( found without appBoxKitLightTheme()/appBoxKitDarkTheme(). The default M3 '
      'color scheme is purple-ish and screams "fresh flutter create".');
}

/// Check 4b: no stock CTA buttons (ElevatedButton/FilledButton/TextButton) as
/// primary/secondary actions in app view code → AppBoxKitNativeButton. The anti-slop
/// blacklist names these as the loudest surface ("a stock M3 button reads as
/// 'untuned Flutter' instantly"). Allowlist: the kit's own wrapper files use
/// `FilledButton.tonal` internally (they're the wrapper layer, not view code).
CheckResult checkNoStockCtaButtons(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('no_stock_cta_buttons', true,
        'skipped (kit-internal or test file)');
  }
  final stripped = _stripNoise(src);
  final matches = _stockCtaButton.allMatches(stripped).toList();
  if (matches.isEmpty) {
    return CheckResult('no_stock_cta_buttons', true, 'no stock CTA buttons');
  }
  final buttons = matches.map((m) => m.group(1)).toSet();
  return CheckResult('no_stock_cta_buttons', false,
      'stock CTA button(s) in view code: $buttons. Use AppBoxKitNativeButton for every '
      'primary/secondary action — CTAs are the loudest surface and a stock button '
      '(Material or Cupertino) reads as "untuned Flutter" instantly.');
}

/// Check 4c: no stock progress indicator as the loading affordance in app view
/// code. A spinner → AppBoxKitNativeLoadingIndicator (iOS Cupertino / Android M3E); a
/// determinate/linear bar → AppBoxKitNativeProgress. Bans both CircularProgressIndicator
/// and LinearProgressIndicator. Allowlist: the kit's own progress wrappers use them
/// internally (they're the wrapper layer).
CheckResult checkNoStockLoadingIndicator(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('no_stock_loading_indicator', true,
        'skipped (kit-internal or test file)');
  }
  final stripped = _stripNoise(src);
  final hits =
      _stockLoadingIndicator.allMatches(stripped).map((m) => m.group(1)).toSet();
  if (hits.isEmpty) {
    return CheckResult('no_stock_loading_indicator', true,
        'no stock progress indicator');
  }
  return CheckResult('no_stock_loading_indicator', false,
      'stock progress indicator(s) in view code: $hits. Use '
      'AppBoxKitNativeLoadingIndicator (circular/spinner) or AppBoxKitNativeProgress '
      '(determinate/linear) — each picks iOS Cupertino / Android M3E. A bare '
      'Material indicator reads as "untuned Flutter".');
}

/// Check 4d: no invented AppBoxKitNative* widget names. The native-component matrix is
/// the SSOT for which AppBoxKitNative* widgets exist (see the `knownKitNativeWidgets`
/// allowlist). A reference to `AppBoxKitNative<AnythingElse>` (AppBoxKitNativeDialog,
/// AppBoxKitNativeDatePicker, …) is the #0c gate's "never invent a AppBoxKitNative* class the
/// matrix doesn't list" rule — it means the model hallucinated a wrapper that
/// doesn't exist, which compiles (as an undefined class) but breaks at design
/// intent long before the user can build it.
CheckResult checkNoInventedNativeWidgets(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('no_invented_native_widgets', true,
        'skipped (kit-internal or test file)');
  }
  final stripped = _stripNoise(src);
  final refs = _anyKitNativeRef
      .allMatches(stripped)
      .map((m) => 'AppBoxKitNative${m.group(1)}')
      .toSet();
  final invented = refs.where((r) => !knownKitNativeWidgets.contains(r)).toSet();
  if (invented.isEmpty) {
    return CheckResult('no_invented_native_widgets', true,
        'no invented AppBoxKitNative* widget names');
  }
  return CheckResult('no_invented_native_widgets', false,
      'invented AppBoxKitNative* widget name(s): $invented. The native-component '
      'matrix (NATIVE_COMPONENTS.md) is the SSOT for which AppBoxKitNative* widgets '
      'exist. If a design needs a native primitive the kit lacks, that is a kit '
      'contribution (a separate task) — never a stubbed AppBoxKitNative* in the view. '
      '(#0c / gate contract.)');
}

/// Check 4f: native-first content surface. A card/tile/banner/panel CONTENT widget
/// must compose on AppBoxKitGlassCard (the matrix ✅ "glass card" row: real Liquid Glass
/// on iOS 26 / M3E Material Card on Android), never a hand-rolled colored
/// `Material(color:` / decorated `Container(…BoxDecoration)`. This is the
/// content-surface sibling of 4b (CTA buttons) / 4c (loaders); chrome bars are the
/// review gate's 1c–1w. It closes the exact gap that shipped the shop's product
/// tiles + upsell banner as plain Flutter over kit primitives instead of on
/// AppBoxKitGlassCard. Narrow: fires only when the file DECLARES a *Tile/*Card/*Banner/
/// *Panel class. Deliberate plain Flutter opts out with a `// flutter-only:` comment
/// (→ AppBoxKitGlassCard(wantNative:false) / stock).
CheckResult checkNativeFirstSurface(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult(
        'no_raw_card_surface', true, 'skipped (kit-internal or test file)');
  }
  // The // flutter-only: opt-out is read on RAW src — _stripNoise removes comments.
  if (_flutterOnlyOptOut.hasMatch(src)) {
    return CheckResult(
        'no_raw_card_surface', true, 'opted out via // flutter-only:');
  }
  final stripped = _stripNoise(src);
  if (!_cardSurfaceClass.hasMatch(stripped)) {
    return CheckResult('no_raw_card_surface', true,
        'no card/tile/banner/panel widget class');
  }
  if (stripped.contains('AppBoxKitGlassCard') || !_rawColoredSurface.hasMatch(stripped)) {
    return CheckResult('no_raw_card_surface', true,
        'card surface composes on AppBoxKitGlassCard (or declares no raw surface)');
  }
  return CheckResult('no_raw_card_surface', false,
      'a card/tile/banner/panel widget hand-rolls a raw colored Material / '
      'decorated Container surface. Compose it on AppBoxKitGlassCard — the matrix ✅ '
      '"glass card" row (real Liquid Glass on iOS 26 / M3E Material Card on '
      'Android). Dense scrolling grid → AppBoxKitGlassCard(wantNative: false); a '
      'singular floating surface (hero/banner) → wantNative: true. Deliberate '
      'plain Flutter → mark it `// flutter-only: <reason>`. (#0c / native-first.)');
}

/// Check 4g: whole-matrix native-first. Every ✅ NATIVE_COMPONENTS.md surface with
/// a stock Flutter equivalent (text field, switch, slider, range slider, FAB,
/// segmented control, search bar, popup/menu, navigation rail, toast, sheet) must
/// route through its AppBoxKitNative* widget in app view code — never the raw Flutter
/// widget. This closes the "pipeline missed a native surface" gap that let a plain
/// input ship: the shop sign-in used AppBoxKitNativeTextField correctly, but nothing
/// guarded the OTHER matrix rows. The ban list (`_nativeSurfaceBans`) IS the
/// matrix. Deliberate plain Flutter opts the file out with `// flutter-only:`
/// (same contract as 4f). Kit-internal wrappers + tests are skipped.
CheckResult checkNoStockNativeSurface(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('no_stock_native_surface', true,
        'skipped (kit-internal or test file)');
  }
  // The // flutter-only: opt-out is read on RAW src — _stripNoise removes comments.
  if (_flutterOnlyOptOut.hasMatch(src)) {
    return CheckResult(
        'no_stock_native_surface', true, 'opted out via // flutter-only:');
  }
  final stripped = _stripNoise(src);
  final hits = <String>[];
  for (final ban in _nativeSurfaceBans) {
    if (ban.stock.hasMatch(stripped)) hits.add('${ban.surface} → ${ban.kit}');
  }
  if (hits.isEmpty) {
    return CheckResult('no_stock_native_surface', true,
        'no stock native-matrix surfaces in view code');
  }
  return CheckResult('no_stock_native_surface', false,
      'stock Flutter widget(s) used where a kit native surface exists: '
      '${hits.join('; ')}. Map every design to the kit native UI first — real '
      'Liquid Glass on iOS 26 / M3E on Android — before any plain Flutter widget. '
      'Deliberate plain Flutter → mark the file `// flutter-only: <reason>`. '
      '(#0c / native-first, whole-matrix.)');
}

/// Check 4e: brace/paren/bracket balance. A regex gate can't parse Dart, but it
/// CAN catch the common "file got cut off / unbalanced delimiters" case that
/// would silently slip through as "clean" (no regex matches → all checks pass).
/// This closes the R5 gap: a syntax-broken file now FAILS rather than reporting
/// a false "clean". Strips strings + comments first (the gate's `_stripNoise`)
/// so delimiters inside strings/comments don't count.
CheckResult checkValidDartSyntax(String src, String path) {
  if (path.contains('/test/') || path.endsWith('_test.dart')) {
    return CheckResult('valid_dart_syntax', true, 'skipped (test file)');
  }
  final stripped = _stripNoise(src);
  // Count opener/closer pairs. A balanced file has equal counts per pair. This
  // is NOT a full parse (it can't catch a misplaced `}` that happens to balance
  // counts) — but it catches the "file got truncated / unclosed declaration"
  // case that's the R5 false-clean failure mode. dart analyze is the real parse
  // (see scripts/tests/independent_oracle.dart); this is the cheap pre-check.
  final opens = {'{': 0, '(': 0, '[': 0};
  final closes = {'}': 0, ')': 0, ']': 0};
  for (final ch in stripped.runes) {
    final s = String.fromCharCode(ch);
    if (opens.containsKey(s)) opens[s] = opens[s]! + 1;
    if (closes.containsKey(s)) closes[s] = closes[s]! + 1;
  }
  final problems = <String>[];
  if (opens['{'] != closes['}']) {
    problems.add('{ }: ${opens["{"]} open vs ${closes["}"]} close');
  }
  if (opens['('] != closes[')']) {
    problems.add('( ): ${opens["("]} open vs ${closes[")"]} close');
  }
  if (opens['['] != closes[']']) {
    problems.add('[ ]: ${opens["["]} open vs ${closes["]"]} close');
  }
  if (problems.isEmpty) {
    return CheckResult('valid_dart_syntax', true,
        'delimiters balanced ({/(/[] all matched)');
  }
  return CheckResult('valid_dart_syntax', false,
      'unbalanced delimiters: ${problems.join(", ")}. The file is likely '
      'truncated or has an unclosed declaration. (A regex gate reports "clean" '
      'on broken syntax because no slop regex matches — this check catches that '
      'false-clean. dart analyze is the full parse; this is the cheap pre-check.)');
}

/// Check 8: no cross-shell VIEW imports (the shell gate's S2 locality rule, at
/// design time). A file under /ui/views/<shellA>/ never imports another shell's
/// view tree /ui/views/<shellB>/ (B≠A). Overlay subdirs
/// (bottom_sheets|dialogs|snackbars) are EXEMPT — overlays are shared app-wide
/// (one global registration; show from anywhere); services/models may be shared
/// too. View trees stay shell-private.
final _viewsPathSegment = RegExp(r'/ui/views/([^/]+)/');
final _viewsOverlaySubdir =
    RegExp(r'/ui/views/[^/]+/(bottom_sheets|dialogs|snackbars)/');
final _crossShellImport = RegExp(r"""import\s+'([^']+)'""");

CheckResult checkNoCrossShellImports(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('no_cross_shell_imports', true,
        'skipped (kit-internal/test file)');
  }
  final shellA = _viewsPathSegment.firstMatch(path);
  if (shellA == null) {
    // No /ui/views/ segment (e.g. a standalone scenarios/ fixture) — N/A, not
    // a failure. This no-op is deliberate: it keeps the check silent on every
    // fixture that isn't part of a shell tree.
    return CheckResult('no_cross_shell_imports', true,
        'not under /ui/views/ — cross-shell check N/A');
  }
  // Comments only (NOT _stripNoise): the import path is a string literal we
  // must read — string-stripping would blank it (same choice as checkNoRawDartIo).
  final stripped = _stripComments(src);
  final offenders = <String>{};
  for (final m in _crossShellImport.allMatches(stripped)) {
    final target = m.group(1)!;
    if (_viewsOverlaySubdir.hasMatch(target)) continue; // overlays shared app-wide
    final shellB = _viewsPathSegment.firstMatch(target);
    if (shellB != null && shellB.group(1) != shellA.group(1)) {
      offenders.add(shellB.group(1)!);
    }
  }
  if (offenders.isEmpty) {
    return CheckResult('no_cross_shell_imports', true,
        'no cross-shell view imports');
  }
  return CheckResult('no_cross_shell_imports', false,
      'cross-shell import of ${offenders.join(', ')} — view trees are '
      'shell-private; overlays (bottom_sheets|dialogs|snackbars), services, '
      'and models may be shared');
}

/// Check 9: no hardcoded user-visible strings. Copy in view files comes from
/// the ARB catalogs via AppLocalizations.of(context)!.<key> — a Text('…') /
/// label: '…' literal with 3+ ASCII letters is hardcoded copy that can never be
/// localized.
///
/// THE INVERSE OF THE G4 PATH. Every other per-file check strips string
/// literals before matching (a token inside a string is not a usage); THIS
/// check matches INSIDE Text()/label: literals — the literal IS the violation.
/// It therefore runs on _stripComments only (a commented-out Text('…') is still
/// not a violation), never on _stripNoise. The two paths stay separate.
///
/// Exemptions: scaffolder stub files (the "appbox-scaffolder: … STRUCTURE
/// ONLY" header — their Text('<arb.key>') placeholders are filled by the
/// builder); strings that are clearly not copy (see [_isNonCopyLiteral]):
/// single chars/symbols/digits-only, route paths, asset paths, dotted keys.
/// A font-family name only reaches this check when placed in a Text()/label:
/// slot, which is itself a bug — so no fontFamily exemption is needed.
CheckResult checkNoHardcodedStrings(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult(
        'no_hardcoded_strings', true, 'skipped (kit-internal or test file)');
  }
  if (!_viewsTree.hasMatch(path)) {
    return CheckResult('no_hardcoded_strings', true,
        'not under /ui/views/ — hardcoded-strings check N/A');
  }
  if (_scaffolderStubHeader.hasMatch(src)) {
    return CheckResult('no_hardcoded_strings', true,
        'scaffolder stub (STRUCTURE ONLY) — placeholder keys exempt');
  }
  final stripped = _stripComments(src);
  final hits = <String>{};
  for (final m in _textOrLabelLiteral.allMatches(stripped)) {
    final s = m.group(1) ?? m.group(2) ?? '';
    if (_isNonCopyLiteral(s)) continue;
    hits.add("'$s'");
  }
  if (hits.isEmpty) {
    return CheckResult(
        'no_hardcoded_strings', true, 'no hardcoded copy literals (Text/label)');
  }
  return CheckResult('no_hardcoded_strings', false,
      'hardcoded user-visible string(s): $hits. Copy comes from the ARB '
      'catalogs — add the key to l10n/app_en.arb (+ every locale) and read it '
      'via AppLocalizations.of(context)!.<key>. Hardcoded copy can never be '
      'localized.');
}

/// True when a Text()/label: literal is clearly NOT user-visible copy (the
/// no_hardcoded_strings exemption list).
bool _isNonCopyLiteral(String s) {
  // Fewer than 3 ASCII letters: single chars, symbols, digits-only.
  if (RegExp(r'[A-Za-z]').allMatches(s).length < 3) return true;
  if (s.startsWith('/')) return true; // route path
  if (s.contains('/')) return true; // asset path
  // A dotted single token: an ARB key ('projects.home') or a filename
  // ('logo.png') — not prose.
  if (RegExp(r'^[\w.\-]+$').hasMatch(s) && s.contains('.')) return true;
  return false;
}

/// Check 5: for a view shell file, the sibling form-factor files exist.
///
/// §16 derivation: the expected factor set is DERIVED from targets (macos →
/// [desktop], 3 files), never the legacy full mobile+tablet+desktop (5 files).
/// The scaffolder records the derived set as `factors` in the nearest
/// `.shell-structure.json` (under lib/ui/views/). When that manifest is present
/// we expect exactly its factors; when absent (hand-built apps, fixtures,
/// pre-§16 trees) we fall back to the legacy 5-file set so nothing that passed
/// before now fails.
CheckResult checkFormFactorFiles(String viewShellPath) {
  final file = File(viewShellPath);
  if (!file.existsSync()) {
    return CheckResult('form_factor_files', false,
        'view shell not found: $viewShellPath');
  }
  // <surface>_view.dart → strip _view.dart to get the surface base name.
  final base = viewShellPath.endsWith('_view.dart')
      ? viewShellPath.substring(0, viewShellPath.length - '_view.dart'.length)
      : null;
  if (base == null) {
    return CheckResult('form_factor_files', true,
        'not a *_view.dart shell — sibling check skipped');
  }
  final manifestFactors = _derivedFactorsFromManifest(viewShellPath);
  // No manifest → legacy 5-file expectation (mobile + tablet + desktop).
  final factors = manifestFactors ?? const ['mobile', 'tablet', 'desktop'];
  final expected = <String>[
    '${base}_view.dart',
    for (final f in factors) '${base}_view.$f.dart',
    '${base}_viewmodel.dart',
  ];
  final missing = expected.where((p) => !File(p).existsSync()).toList();
  if (missing.isEmpty) {
    final src = manifestFactors != null
        ? 'derived factors ${manifestFactors.join(", ")} (§16) per .shell-structure.json'
        : 'all form-factor files present (legacy 5-file set)';
    return CheckResult('form_factor_files', true, src);
  }
  final because = manifestFactors != null
      ? 'targets derive form factors [${manifestFactors.join(", ")}] per '
          '.shell-structure.json (§16) — a macos target is a 3-file set, not 5. '
          'See stacked-patterns.md / architecture §16.'
      : 'Every surface is a 5-file set (view + mobile + tablet + desktop + '
          'viewmodel). See stacked-patterns.md.';
  return CheckResult('form_factor_files', false,
      'missing form-factor file(s): $missing. $because');
}

/// Walk up from a view file to find the nearest `.shell-structure.json` (the
/// scaffolder writes it under lib/ui/views/) and return its declared `factors`.
/// Returns null when no manifest is reachable — caller falls back to legacy.
List<String>? _derivedFactorsFromManifest(String viewPath) {
  var dir = File(viewPath).parent;
  for (var i = 0; i < 16 && dir.path.isNotEmpty; i++) {
    final candidate = File('${dir.path}/.shell-structure.json');
    if (candidate.existsSync()) {
      try {
        final doc = jsonDecode(candidate.readAsStringSync());
        if (doc is Map<String, dynamic> && doc['factors'] is List) {
          final fs = (doc['factors'] as List)
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
          return fs;
        }
        return null; // manifest present but no `factors` field → legacy
      } catch (_) {
        return null;
      }
    }
    dir = dir.parent;
  }
  return null;
}

/// Check 6: design-system.md exists in the surface directory (mandatory).
CheckResult checkDesignSystemDoc(String surfaceDirOrViewPath) {
  // Resolve the surface dir: if given a file, take its parent.
  final dir = File(surfaceDirOrViewPath).existsSync()
      ? File(surfaceDirOrViewPath).parent
      : Directory(surfaceDirOrViewPath);
  if (!dir.existsSync()) {
    return CheckResult('design_system_doc', false,
        'surface directory not found: ${dir.path}');
  }
  final ds = File('${dir.path}/design-system.md');
  if (!ds.existsSync()) {
    return CheckResult('design_system_doc', false,
        'design-system.md missing in ${dir.path}. It is mandatory — the carrier '
        'of intent (palette/type/spacing/motion/forbidden). See design-system-template.md.');
  }
  // Light content check: must mention at least palette + forbidden (the minimum).
  final text = ds.readAsStringSync();
  final missing = <String>[];
  if (!RegExp(r'\b(palette|color|accent|AppBoxKitColors)\b', caseSensitive: false).hasMatch(text)) {
    missing.add('palette');
  }
  if (!RegExp(r'\b(forbidden|avoid|never|don.t)\b', caseSensitive: false).hasMatch(text)) {
    missing.add('forbidden');
  }
  if (missing.isEmpty) {
    return CheckResult('design_system_doc', true,
        'design-system.md present with required sections');
  }
  return CheckResult('design_system_doc', false,
      'design-system.md present but missing section(s): $missing. Must cover at '
      'least palette + forbidden (see design-system-template.md).');
}

/// Check 7: iteration drift — for a vN (N≥2) surface, no DROPPED AppBoxKitGlyphs/
/// AppBoxKitColors references vs the nearest existing prior (the improve≠rebrand
/// enforcement, mechanical).
///
/// Iteration-suffix detection: matches `_vN` / `-vN` / `.vN` for any N≥2 (G6 —
/// previously only `_v2`/`-v2` were detected, so a `_v3` iterating a `_v2`
/// silently skipped). When found, walk the version numbers DOWN to the nearest
/// existing sibling (`thing_v3` → `thing_v2` → `thing`) and diff against it.
/// If no versioned prior exists, the check skips (a lone `thing_v3` with no
/// `thing_v2`/`thing` is not a comparable iteration).
CheckResult checkIterationDrift(String surfaceDirOrViewPath) {
  final surfaceDir = File(surfaceDirOrViewPath).existsSync()
      ? File(surfaceDirOrViewPath).parent
      : Directory(surfaceDirOrViewPath);
  final surfaceName = surfaceDir.path.split('/').last;
  // Strip a single trailing version suffix: "thing_v3" → ("thing", 3),
  // "thing-v2" → ("thing", 2), "thing.v5" → ("thing", 5). Non-iterating names
  // (no suffix, or N<2) return null → skip.
  final match = RegExp(r'^(.*?)[-_\.]v(\d+)$').firstMatch(surfaceName);
  if (match == null || int.parse(match.group(2)!) < 2) {
    return CheckResult('iteration_drift', true,
        'not an iteration (no _vN/-vN/.vN suffix with N≥2) — drift check skipped');
  }
  final stem = match.group(1)!;
  final curN = int.parse(match.group(2)!);
  // Walk version numbers down from curN-1 to 1, then the bare stem, return the
  // first existing sibling dir. `thing_v3` tries thing_v2, thing_v1, thing.
  String? priorName;
  for (var n = curN - 1; n >= 1 && priorName == null; n--) {
    final candidate = '${stem}_v$n';
    if (Directory('${surfaceDir.parent.path}/$candidate').existsSync()) {
      priorName = candidate;
    }
  }
  if (priorName == null &&
      Directory('${surfaceDir.parent.path}/$stem').existsSync()) {
    priorName = stem;
  }
  if (priorName == null) {
    return CheckResult('iteration_drift', true,
        'iteration ($surfaceName) but no prior sibling found — drift check skipped');
  }
  final priorDir = Directory('${surfaceDir.parent.path}/$priorName');
  // Collect AppBoxKitGlyphs + AppBoxKitColors refs from prior and current .dart files.
  final priorRefs = _collectTokenRefs(priorDir);
  final curRefs = _collectTokenRefs(surfaceDir);
  // Prior tokens that current DROPPED (didn't carry over).
  final dropped = priorRefs.difference(curRefs);
  if (dropped.isEmpty) {
    return CheckResult('iteration_drift', true,
        'no dropped AppBoxKitGlyphs/AppBoxKitColors tokens vs prior ($priorName)');
  }
  return CheckResult('iteration_drift', false,
      'tokens dropped vs prior ($priorName): $dropped. An iteration preserves + '
      'adds, never drops. If a token is genuinely obsolete, that is a rebrand, '
      'not an improve — say so. (Checkpoint 5 / improve≠rebrand.)');
}

Set<String> _collectTokenRefs(Directory dir) {
  final refs = <String>{};
  if (!dir.existsSync()) return refs;
  for (final ent in dir.listSync(recursive: false)) {
    if (ent is! File || !ent.path.endsWith('.dart')) continue;
    // Strip comments AND strings — a v2 file may legitimately MENTION a dropped
    // token in a comment ("// AppBoxKitGlyphs.refresh removed — replaced by …") or a
    // doc/error string; that mention is not a usage and must not cancel the drift
    // signal.
    final src = _stripNoise(ent.readAsStringSync());
    refs.addAll(_kitGlyphsRef.allMatches(src).map((m) => 'AppBoxKitGlyphs.${m.group(1)}'));
    refs.addAll(_kitColorsRef.allMatches(src).map((m) => 'AppBoxKitColors.${m.group(1)}'));
    refs.addAll(_kitDarkColorsRef.allMatches(src).map((m) => 'AppBoxKitDarkColors.${m.group(1)}'));
  }
  return refs;
}

// ---------- helpers ----------

/// Strip comments AND string literals before token matching.
///
/// Why both: a token (Icons.home, Color(0x…)) mentioned ONLY in a comment or a
/// string literal is not a real usage. The comment-stripper alone left
/// string-embedded tokens firing false positives (G4). Stripping strings too
/// means "the bad path is Icons.home" inside a `Text("…")` or a `//` note is
/// invisible to the check — exactly what we want.
///
/// Conservative by design: this is NOT a Dart lexer. It does line/block
/// comments and single/double-quoted (incl. `'''`/`"""` triple) string
/// contents. Interpolations inside strings (`"$x"`) are stripped whole; the
/// interpolation expression is therefore not scanned either. That's fine for a
/// slop-gate: interpolated tokens are vanishingly rare in the things this gate
/// forbids, and a false negative on an interpolated `Icons.$name` is far less
/// costly than a false positive on a doc string.
String _stripComments(String src) {
  // Strip // line comments.
  var out = src.replaceAll(RegExp(r'//[^\n]*'), '');
  // Strip /* */ block comments.
  out = out.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return out;
}

String _stripStrings(String src) {
  // Triple-quoted first (greedy across newlines), so a `'''…'''` block doesn't
  // get mis-truncated by the single-quote rule below.
  var out = src
      .replaceAll(RegExp(r"'''[\s\S]*?'''"), "''")
      .replaceAll(RegExp(r'"""[\s\S]*?"""'), '""');
  // Then single-line single- and double-quoted strings. `\\.` swallows an
  // escaped quote inside the string ("don\"t") so the match ends at the real
  // closing quote.
  out = out
      .replaceAll(RegExp(r"'(?:\\.|[^'\\])*'"), "''")
      .replaceAll(RegExp(r'"(?:\\.|[^"\\])*"'), '""');
  return out;
}

/// The combined noise-strip the per-file checks run on.
String _stripNoise(String src) => _stripStrings(_stripComments(src));

/// Run all per-file checks on a single .dart file.
// ---------- mirrored from review_checklist.sh (checks 1w2, 1i, 1d) ----------
//
// WHY these live here too. The design gate used to pass a surface 58/58 while
// the review gate found 13 real violations in the same files, so rework landed
// two phases late with a checkpoint in between. These three are the ones that
// actually fired; mirroring them moves the finding to the phase that can still
// cheaply fix it. review_checklist.sh remains the tree-wide backstop — this is
// an earlier tripwire, not a replacement.
//
// TRANSLATED, not verbatim. The precedent (scaffold_gate.sh ↔ check 1k) is
// bash↔bash and can copy character-for-character; this is bash↔Dart and cannot:
// POSIX `[[:space:]]` is not valid in a Dart RegExp, so it becomes `\s`. The
// two patterns that ARE literally portable — the 1w2 SizedBox pattern and 1i's
// glass alternation — are kept character-identical and asserted equal by
// tools/test_gates.sh, which is the only mechanical drift guard of the three.
//
// Comment-blindness (the review gate's own defect class) is free here:
// _stripNoise blanks comments and strings before matching. The exception is
// 1w2's `// sizing:` opt-out, which IS a comment and so is read from the raw
// source — the same split review_checklist.sh's nc_init block spells out.

/// Verbatim-portable with review_checklist.sh check 1w2's `PAT`.
final _spacingSizedBox =
    RegExp(r'SizedBox\(\s*(?:height|width)\s*:\s*[^,()\n]+?,?\s*\)');
final _sizingOptOut = RegExp(r'//\s*sizing:');
final _sizedBoxAsChild = RegExp(r'child:\s*(const\s+)?SizedBox\(');

/// 1w2: a single-argument `SizedBox(height:/width:)` with no child is a GAP,
/// not sizing — gaps are the appbox_kit_core helpers. Line-scoped opt-outs
/// (`// sizing:`, `child: SizedBox(`) match review_checklist.sh exactly.
CheckResult checkNoAdhocSpacing(String src, String path) {
  if (_isKitInternalOrTest(path) || path.endsWith('ui_helpers.dart')) {
    return CheckResult(
        'no_adhoc_spacing', true, 'skipped (kit-internal, test, or ui_helpers)');
  }
  // Raw src, exactly as the bash scanner reads it: the opt-outs are comments,
  // and line numbers must index the file the author will open. A commented-out
  // example is skipped by the `//`-precedes test below.
  final lines = src.split('\n');
  final hits = <String>[];
  for (final m in _spacingSizedBox.allMatches(src)) {
    final ln = '\n'.allMatches(src.substring(0, m.start)).length;
    final line = ln < lines.length ? lines[ln] : '';
    // lastIndexOf with start -1 throws, so a match at offset 0 is special-cased.
    final lineStart =
        m.start == 0 ? 0 : src.lastIndexOf('\n', m.start - 1) + 1;
    final col = m.start - lineStart;
    // ponytail: `//` left of the match on the same line ⇒ prose, not code.
    // Covers `///` doc examples; a match inside a /* */ block is not covered.
    final head = col <= line.length ? line.substring(0, col) : line;
    if (head.contains('//')) continue;
    if (_sizingOptOut.hasMatch(line)) continue;
    if (_sizedBoxAsChild.hasMatch(line)) continue;
    hits.add('${ln + 1}: ${m.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}');
  }
  if (hits.isEmpty) {
    return CheckResult('no_adhoc_spacing', true, 'no ad-hoc spacing SizedBox');
  }
  return CheckResult(
      'no_adhoc_spacing',
      false,
      'ad-hoc spacing SizedBox (single-arg, no child) at ${hits.join('; ')}. '
          'Gaps use the appbox_kit_core helpers (verticalSpace*/horizontalSpace*, '
          'or verticalSpace(h)/horizontalSpace(w) for one-offs, via the '
          'ui_library barrel). Placeholder sizing: mount it as `child:` or opt '
          'out with `// sizing: <reason>` (review_checklist check 1w2).');
}

/// Verbatim-portable with review_checklist.sh check 1i's `GLASS_RE`.
final _glassSurface = RegExp(
    r'AppBoxKitGlassCard|AppBoxKitNativeSearchBar|AppBoxKitNativeSplitButton|AppBoxKitNativeToolbar|AppBoxKitNativeFabMenu|AppBoxKitNativeFab');
final _scrollEdgeEffect = RegExp(r'AppBoxKitScrollEdgeEffect|scrollEdgeEffect\(');

/// 1i: a glass surface inside a CustomScrollView needs the iOS 26 scroll edge
/// effect, or content blurs under pinned chrome that never hides.
CheckResult checkScrollEdgeEffect(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult(
        'scroll_edge_effect', true, 'skipped (kit-internal or test file)');
  }
  final stripped = _stripNoise(src);
  if (!_glassSurface.hasMatch(stripped) ||
      !stripped.contains('CustomScrollView')) {
    return CheckResult(
        'scroll_edge_effect', true, 'no glass surface in a CustomScrollView');
  }
  if (_scrollEdgeEffect.hasMatch(stripped)) {
    return CheckResult('scroll_edge_effect', true, 'scroll edge effect applied');
  }
  return CheckResult(
      'scroll_edge_effect',
      false,
      'glass surface inside a CustomScrollView without AppBoxKitScrollEdgeEffect / '
          '.scrollEdgeEffect() — iOS 26 scroll edge effect: content blurs and '
          'fades under pinned chrome and the chrome never hides '
          '(review_checklist check 1i).');
}

final _appBarSlot = RegExp(r'appBar:');
final _kitAppBarCtor = RegExp(r'[A-Za-z_]AppBar\(');
final _stockAppBarCtor =
    RegExp(r'appBar:\s*(AppBar|SliverAppBar|CupertinoNavigationBar)\(');

/// 1d: chrome is owned by LEAF views via AppBoxKitNativeAppBar; shells stay bare.
///
/// COVERAGE LIMIT — this is narrower than review_checklist.sh's 1d, and
/// deliberately so. The review gate scans the whole tree; the design gate is
/// invoked per surface (`DESIGN_TARGET=<surface dir>`), so the shell-stays-bare
/// half only fires when a `*_shell_view*` file happens to sit inside the target.
/// The leaf half — the part that caught real findings — always fires.
CheckResult checkLeafAppBar(String src, String path) {
  if (_isKitInternalOrTest(path)) {
    return CheckResult('leaf_app_bar', true, 'skipped (kit-internal or test)');
  }
  final stripped = _stripNoise(src);
  if (!_appBarSlot.hasMatch(stripped)) {
    return CheckResult('leaf_app_bar', true, 'no appBar: slot');
  }
  if (path.contains('_shell_view')) {
    return CheckResult(
        'leaf_app_bar',
        false,
        'shell view sets appBar: — shells stay bare, leaves own their chrome '
            '(review_checklist check 1d).');
  }
  if (!_kitAppBarCtor.hasMatch(stripped)) {
    return CheckResult(
        'leaf_app_bar',
        false,
        'appBar: without a kit app bar — use AppBoxKitNativeAppBar (or an app '
            'wrapper of it), never a stock app bar (review_checklist check 1d).');
  }
  if (_stockAppBarCtor.hasMatch(stripped)) {
    return CheckResult('leaf_app_bar', false,
        'stock app bar alongside AppBoxKitNativeAppBar (review_checklist check 1d).');
  }
  if (stripped.contains('PreferredSize(')) {
    return CheckResult(
        'leaf_app_bar',
        false,
        'PreferredSize wrapper — AppBoxKitNativeAppBar already implements '
            'PreferredSizeWidget (review_checklist check 1d).');
  }
  return CheckResult('leaf_app_bar', true, 'kit app bar mounted on a leaf');
}

List<CheckResult> checkFile(String path) {
  final src = File(path).readAsStringSync();
  return [
    checkNoStockIcons(src, path),
    checkNoHardcodedColors(src, path),
    checkNoRawDartIo(src, path),
    checkKitThemeUsed(src, path),
    checkNoStockCtaButtons(src, path),
    checkNoStockLoadingIndicator(src, path),
    checkNoInventedNativeWidgets(src, path),
    checkNativeFirstSurface(src, path),
    checkNoStockNativeSurface(src, path),
    checkValidDartSyntax(src, path),
    checkNoCrossShellImports(src, path),
    checkNoHardcodedStrings(src, path),
    // Mirrored from review_checklist.sh so design-phase surfaces stop shipping
    // findings the review gate would raise two phases later (1w2, 1i, 1d).
    checkNoAdhocSpacing(src, path),
    checkScrollEdgeEffect(src, path),
    checkLeafAppBar(src, path),
  ];
}

/// Run all surface-level checks on a surface directory (or resolve one from a view file).
List<CheckResult> checkSurface(String surfaceDirOrViewPath) {
  final results = <CheckResult>[];
  // form-factor files + design-system + iteration drift operate at the surface level.
  final isViewFile = surfaceDirOrViewPath.endsWith('_view.dart') &&
      File(surfaceDirOrViewPath).existsSync();
  if (isViewFile) {
    results.add(checkFormFactorFiles(surfaceDirOrViewPath));
    results.add(checkDesignSystemDoc(surfaceDirOrViewPath));
    results.add(checkIterationDrift(surfaceDirOrViewPath));
  } else {
    // Assume it's a surface dir — find the view shell.
    final dir = Directory(surfaceDirOrViewPath);
    if (dir.existsSync()) {
      File? shell;
      for (final ent in dir.listSync()) {
        if (ent is File && ent.path.endsWith('_view.dart')) {
          // `_view.dart` is the shell; `_view.{mobile,tablet,desktop}.dart` end
          // with `.dart` too but NOT with `_view.dart` (they end with `.mobile.dart`
          // etc.), so endsWith('_view.dart') alone correctly picks the shell.
          shell = ent;
          break;
        }
      }
      if (shell != null) {
        results.add(checkFormFactorFiles(shell.path));
      } else {
        results.add(CheckResult('form_factor_files', false,
            'no <surface>_view.dart shell in $surfaceDirOrViewPath'));
      }
      results.add(checkDesignSystemDoc(surfaceDirOrViewPath));
      results.add(checkIterationDrift(surfaceDirOrViewPath));
    } else {
      results.add(CheckResult('form_factor_files', false,
          'not a view file or surface dir: $surfaceDirOrViewPath'));
    }
  }
  return results;
}

/// Gather all .dart files under a surface dir (or the single file).
List<String> _dartFiles(String path) {
  final f = File(path);
  if (f.existsSync()) return [path];
  final d = Directory(path);
  if (d.existsSync()) {
    return d
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList();
  }
  return [];
}

/// Full gate: run everything, return all results.
///
/// G7 — single-file short-circuit: if `path` is a single `.dart` file that is
/// NOT a `<surface>_view.dart` shell, run ONLY the per-file checks and skip
/// `checkSurface` (which would always emit a `form_factor_files` FAIL and drown
/// the real per-file results). A lone non-view file isn't a surface; pretending
/// it is one was pure noise. A `_view.dart` shell still gets the surface checks
/// (that's the meaningful case). Dirs get the full treatment.
List<CheckResult> gate(String path) {
  final all = <CheckResult>[];
  final isSingleFile = File(path).existsSync();
  final isViewShell = path.endsWith('_view.dart');
  // Per-file checks on every .dart file.
  for (final dartPath in _dartFiles(path)) {
    all.addAll(checkFile(dartPath));
  }
  // Surface-level checks only when the arg is a view shell or a directory.
  // (A lone non-view .dart file → per-file checks only; see G7 above.)
  if (!isSingleFile || isViewShell) {
    all.addAll(checkSurface(path));
  }
  return all;
}

// ---------- self-test (the calibration) ----------
//
// A green-only self-test proves nothing — the negative cases are the calibration.
// Each mutation must FAIL for the RIGHT reason (the standard freeze-gate discipline).

Future<int> _runSelfTest() async {
  // Resolve the skill root from THIS script's location (not the cwd) so
  // `--self-test` works regardless of where it's invoked from. The harness's
  // robustness suite runs it as a subprocess from a temp cwd; a cwd-dependent
  // path broke that (R8). This script is at <root>/scripts/enforce_design.dart.
  final here = File(Platform.script.toFilePath()).parent; // scripts/
  final skillRoot = here.parent.path; // <root>/
  final fixturesDir = Directory('$skillRoot/scripts/fixtures');
  var passCount = 0;
  var failCount = 0;

  void expect(bool cond, String label) {
    if (cond) {
      passCount++;
      print('  PASS: $label');
    } else {
      failCount++;
      print('  FAIL: $label');
    }
  }

  print('enforce_design.dart — self-test\n');

  // The vendored file-fixture tree (scripts/fixtures/, scripts/tests/scenarios/)
  // is NOT shipped with this repo — gates/review/selftest.sh is the repo-local
  // R5 harness that covers the same checks end-to-end via the CLI. When the
  // fixtures are absent the file-fixture sections are skipped (with a note);
  // the pure (src, path) sections below always run.
  if (fixturesDir.existsSync()) {
    _fileFixtureSections(fixturesDir, expect);
  } else {
    print('  (fixture tree not shipped — file-fixture sections skipped;');
    print('   gates/review/selftest.sh is the repo-local R5 harness)');
  }

  // ---- pure negatives (no fixture files; always run) ----

  // A7: a real kit widget name (AppBoxKitNativeButton) does NOT trip the check.
  // Verify the allowlist accepts every known name (no false negatives).
  for (final name in knownKitNativeWidgets) {
    final ok = checkNoInventedNativeWidgets(
        'final x = $name();', 'lib/ui/views/x_view.dart').ok;
    expect(ok, '4d: $name accepted (in the matrix allowlist)');
  }

  // A10: a string with delimiters inside must NOT trip the balance check.
  // (Delimiters inside strings/comments are stripped before counting.)
  final stringDelim = checkValidDartSyntax(
      "const s = '{ not a real brace }'; // (nor this)\nclass A {}",
      'lib/ui/views/x.dart');
  expect(stringDelim.ok,
      '4e: delimiters inside strings/comments do NOT trip valid_dart_syntax');

  _selfTestPureSections(expect);

  print('\n--- self-test summary ---');
  print('  $passCount passed, $failCount failed');
  if (failCount > 0) {
    print('  SELF-TEST FAILED — the gate is miscalibrated.');
    return 1;
  }
  print('  SELF-TEST PASSED — gate is calibrated (negatives fail for the right reason).');
  return 0;
}

/// The file-fixture self-test sections (1–8, A1–A6, A8–A9, A11–A15, G1–G7),
/// moved verbatim out of _runSelfTest. They depend on the vendored fixture
/// tree (scripts/fixtures/ + scripts/tests/scenarios/), which is NOT shipped
/// with this repo — _runSelfTest calls this only when the tree exists.
void _fileFixtureSections(
    Directory fixturesDir, void Function(bool, String) expect) {
  // 1. clean fixture must pass all per-file checks.
  final cleanResults = checkFile('${fixturesDir.path}/clean_surface/clean_view.mobile.dart');
  expect(cleanResults.every((r) => r.ok), 'clean fixture passes all per-file checks');
  expect(cleanResults.firstWhere((r) => r.name == 'no_stock_icons').ok,
      'clean fixture: no stock icons');
  expect(cleanResults.firstWhere((r) => r.name == 'no_hardcoded_colors').ok,
      'clean fixture: no hardcoded colors');
  expect(cleanResults.firstWhere((r) => r.name == 'no_raw_dart_io').ok,
      'clean fixture: no raw dart:io');
  expect(cleanResults.firstWhere((r) => r.name == 'kit_theme_used').ok,
      'clean fixture: no unconfigured MaterialApp (or uses kit theme)');

  // 2. sloppy fixture must FAIL no_stock_icons for the right reason.
  final sloppyResults = checkFile('${fixturesDir.path}/sloppy_view.mobile.dart');
  final iconsCheck = sloppyResults.firstWhere((r) => r.name == 'no_stock_icons');
  expect(!iconsCheck.ok, 'sloppy fixture fails no_stock_icons');
  expect(iconsCheck.message.contains('Icons.home'),
      'sloppy fixture flags Icons.home specifically');

  // 3. sloppy fixture must FAIL no_hardcoded_colors.
  final colorsCheck = sloppyResults.firstWhere((r) => r.name == 'no_hardcoded_colors');
  expect(!colorsCheck.ok, 'sloppy fixture fails no_hardcoded_colors');
  expect(colorsCheck.message.contains('Color(0x'),
      'sloppy fixture flags a Color(0x…) literal');

  // 4. sloppy fixture must FAIL no_raw_dart_io (both import + raw Platform).
  final ioCheck = sloppyResults.firstWhere((r) => r.name == 'no_raw_dart_io');
  expect(!ioCheck.ok, 'sloppy fixture fails no_raw_dart_io');
  expect(ioCheck.message.contains("import 'dart:io'"),
      'sloppy fixture flags the dart:io import');
  expect(ioCheck.message.contains('Platform.'),
      'sloppy fixture flags raw Platform.is*');

  // 5. unconfigured-theme fixture must FAIL kit_theme_used.
  final themeResults = checkFile('${fixturesDir.path}/unconfigured_theme.dart');
  final themeCheck = themeResults.firstWhere((r) => r.name == 'kit_theme_used');
  expect(!themeCheck.ok, 'unconfigured-theme fixture fails kit_theme_used');

  // 6. design-system-doc: clean surface dir (has design-system.md) passes.
  final dsClean = checkDesignSystemDoc('${fixturesDir.path}/clean_surface');
  expect(dsClean.ok, 'clean surface (design-system.md present) passes design_system_doc');

  // 7. design-system-doc: missing doc fails.
  final dsMissing = checkDesignSystemDoc('${fixturesDir.path}/no_ds_surface');
  expect(!dsMissing.ok, 'surface with no design-system.md fails design_system_doc');

  // 8. iteration_drift: a v2 surface that drops a v1 token fails.
  final driftV2 = checkIterationDrift('${fixturesDir.path}/drift_demo/mything_v2');
  expect(!driftV2.ok, 'v2 that drops a AppBoxKitGlyphs token fails iteration_drift');
  expect(driftV2.message.contains('AppBoxKitGlyphs.refresh'),
      'iteration_drift names the dropped token');

  // 9. iteration_drift: a v2 surface that preserves v1 tokens passes.
  final keepV2 = checkIterationDrift('${fixturesDir.path}/drift_demo/keep_v2');
  expect(keepV2.ok, 'v2 that preserves v1 tokens passes iteration_drift');

  // 10. iteration_drift: a non-iteration (no _v2) skips.
  final greenfield = checkIterationDrift('${fixturesDir.path}/clean_surface');
  expect(greenfield.ok, 'non-iteration surface skips iteration_drift cleanly');

  // 11. native-first content surface (4f): a *Card that hand-rolls a raw colored
  //     Material (no AppBoxKitGlassCard, no // flutter-only:) must FAIL no_raw_card_surface
  //     for the right reason; the clean fixture (no card widget class) must pass it.
  final rawCardResults =
      checkFile('${fixturesDir.path}/raw_card_view.mobile.dart');
  final cardCheck =
      rawCardResults.firstWhere((r) => r.name == 'no_raw_card_surface');
  expect(!cardCheck.ok, 'raw-card fixture fails no_raw_card_surface');
  expect(cardCheck.message.contains('AppBoxKitGlassCard'),
      'no_raw_card_surface names the AppBoxKitGlassCard fix');
  expect(cleanResults.firstWhere((r) => r.name == 'no_raw_card_surface').ok,
      'clean fixture passes no_raw_card_surface (no card widget class)');

  // 12. whole-matrix native-first (4g): a view that uses a raw stock Switch (a
  //     matrix surface not covered by 4b/4c/4f) must FAIL no_stock_native_surface
  //     naming the AppBoxKitNative* fix; the clean fixture must pass it.
  final stockSurfaceResults =
      checkFile('${fixturesDir.path}/stock_native_surface_view.mobile.dart');
  final surfaceCheck =
      stockSurfaceResults.firstWhere((r) => r.name == 'no_stock_native_surface');
  expect(!surfaceCheck.ok, 'stock-surface fixture fails no_stock_native_surface');
  expect(surfaceCheck.message.contains('AppBoxKitNativeSwitch'),
      'no_stock_native_surface names the AppBoxKitNativeSwitch fix');
  expect(cleanResults.firstWhere((r) => r.name == 'no_stock_native_surface').ok,
      'clean fixture passes no_stock_native_surface (uses kit widgets)');

  // 12b. "doesn't miss any" coverage: a fixture with one stock widget per ban row
  //      (incl. a named-constructor variant + both overlay call sites) must fail
  //      4g naming EVERY kit surface — so a future regex edit that breaks one row
  //      is caught here, not in production.
  final allSurfaceMsg = checkFile(
          '${fixturesDir.path}/all_native_surfaces_view.mobile.dart')
      .firstWhere((r) => r.name == 'no_stock_native_surface')
      .message;
  for (final kit in const [
    'AppBoxKitNativeTextField',
    'AppBoxKitNativeSwitch',
    'AppBoxKitNativeSlider',
    'AppBoxKitNativeRangeSlider',
    'AppBoxKitNativeFab',
    'AppBoxKitNativeSegmentedControl',
    'AppBoxKitNativeSearchBar',
    'AppBoxKitNativePopupMenu',
    'AppBoxKitNativeNavigationRail',
    'appBoxKitShowNativeToast',
    'appBoxKitShowNativeSheet',
  ]) {
    expect(allSurfaceMsg.contains(kit),
        '4g all-surfaces fixture names $kit (no ban row silently misses)');
  }

  // ---- closed-blind-spot negatives (one per fixed G#) ----
  // These live under scripts/tests/scenarios/ (shared with the standalone stress
  // suite). Each asserts a closed blind spot fires (or, for the
  // negative-of-false-positive cases, correctly does NOT fire).
  final scenariosDir =
      Directory('${fixturesDir.path}/../tests/scenarios');

  // G1: MaterialApp.router( without kit theme must FAIL kit_theme_used.
  final routerResults =
      checkFile('${scenariosDir.path}/router_app/main.dart');
  final routerCheck =
      routerResults.firstWhere((r) => r.name == 'kit_theme_used');
  expect(!routerCheck.ok, 'G1: MaterialApp.router( without kit theme fails');
  expect(routerCheck.message.toLowerCase().contains('kit'),
      'G1: failure message names the kit theme fix');

  // G2: Color.fromARGB() / Color.fromRGBO() must FAIL no_hardcoded_colors.
  final argbResults =
      checkFile('${scenariosDir.path}/argb_view.mobile.dart');
  final argbCheck =
      argbResults.firstWhere((r) => r.name == 'no_hardcoded_colors');
  expect(!argbCheck.ok, 'G2: Color.fromARGB/fromRGBO fails no_hardcoded_colors');
  expect(argbCheck.message.contains('fromARGB'),
      'G2: failure names the fromARGB constructor');
  expect(argbCheck.message.contains('fromRGBO'),
      'G2: failure names the fromRGBO constructor');

  // G3: `import 'dart:io' show Platform;` must FAIL no_raw_dart_io (import arm).
  final ioCombResults =
      checkFile('${scenariosDir.path}/io_combiner.dart');
  final ioCombCheck =
      ioCombResults.firstWhere((r) => r.name == 'no_raw_dart_io');
  expect(!ioCombCheck.ok, 'G3: dart:io combiner import fails no_raw_dart_io');
  expect(ioCombCheck.message.contains("import 'dart:io'"),
      'G3: failure names the dart:io import (not just raw Platform)');

  // G4: Icons.* inside a string literal must NOT trip no_stock_icons (no false
  // positive — the string-stripper prevents a wrong FAIL).
  final strResults =
      checkFile('${scenariosDir.path}/string_icon.dart');
  final strCheck =
      strResults.firstWhere((r) => r.name == 'no_stock_icons');
  expect(strCheck.ok,
      'G4: Icons.* inside a string/comment does NOT trip no_stock_icons');

  // G6: a _v3 iterating a _v2 that drops a token must FAIL iteration_drift.
  final driftV3 =
      checkIterationDrift('${scenariosDir.path}/drift_v3/thing_v3');
  expect(!driftV3.ok, 'G6: _v3 iterating _v2 with a dropped token fails drift');
  expect(driftV3.message.contains('thing_v2'),
      'G6: failure names the walked-back prior (thing_v2)');
  expect(driftV3.message.contains('AppBoxKitGlyphs.refresh'),
      'G6: failure names the dropped token');

  // G7: a lone non-view .dart file must NOT emit a form_factor_files FAIL.
  // gate() short-circuits; only per-file checks run. All must be OK → exit 0.
  final g7Gate = gate('${scenariosDir.path}/green_single.dart');
  expect(g7Gate.every((r) => r.ok),
      'G7: lone non-view file has no form_factor_files noise (all OK)');
  expect(!g7Gate.any((r) => r.name == 'form_factor_files'),
      'G7: form_factor_files check is skipped entirely for a lone file');

  // ---- anti-slop checks (no_stock_cta_buttons + no_stock_loading_indicator) ----
  // A1: clean fixture (uses AppBoxKitNativeButton) passes no_stock_cta_buttons.
  final cleanCta = cleanResults.firstWhere((r) => r.name == 'no_stock_cta_buttons');
  expect(cleanCta.ok, 'clean fixture passes no_stock_cta_buttons (uses AppBoxKitNativeButton)');

  // A2: stock-buttons fixture FAILS no_stock_cta_buttons, naming all three buttons.
  final stockBtnResults =
      checkFile('${scenariosDir.path}/stock_buttons_view.mobile.dart');
  final ctaCheck =
      stockBtnResults.firstWhere((r) => r.name == 'no_stock_cta_buttons');
  expect(!ctaCheck.ok, 'stock-buttons fixture fails no_stock_cta_buttons');
  expect(ctaCheck.message.contains('ElevatedButton'),
      'A: no_stock_cta_buttons names ElevatedButton');
  expect(ctaCheck.message.contains('FilledButton'),
      'A: no_stock_cta_buttons names FilledButton');
  expect(ctaCheck.message.contains('TextButton'),
      'A: no_stock_cta_buttons names TextButton');

  // A3: stock-buttons fixture FAILS no_stock_loading_indicator.
  final loadCheck = stockBtnResults
      .firstWhere((r) => r.name == 'no_stock_loading_indicator');
  expect(!loadCheck.ok, 'stock-buttons fixture fails no_stock_loading_indicator');

  // A4: allowlist — a kit-internal path (/widgets/appbox_kit_*) must NOT trip the checks
  // even when it uses CircularProgressIndicator. The gate is told the kit path
  // explicitly here (simulating a real kit-wrapper location).
  final kitInternalSrc = File('${scenariosDir.path}/kit_internal/appbox_kit_native_demo.dart')
      .readAsStringSync();
  final kitLoadCheck = checkNoStockLoadingIndicator(
      kitInternalSrc, 'lib/widgets/appbox_kit_native_demo.dart');
  expect(kitLoadCheck.ok,
      'A: kit-internal path (/widgets/appbox_kit_*) allowlisted for loading indicator');
  final kitCtaCheck = checkNoStockCtaButtons(
      kitInternalSrc, 'lib/widgets/appbox_kit_native_toolbar.dart');
  expect(kitCtaCheck.ok,
      'A: kit-internal path (/widgets/appbox_kit_*) allowlisted for CTA buttons');

  // ---- 4d: no_invented_native_widgets (the #0c matrix rule, now mechanical) ----
  // A5: clean fixture uses only real AppBoxKitNative* names → passes.
  final cleanInvented = cleanResults
      .firstWhere((r) => r.name == 'no_invented_native_widgets');
  expect(cleanInvented.ok,
      'clean fixture passes no_invented_native_widgets (real names only)');

  // A6: invented-widgets fixture FAILS, naming both invented names.
  final inventedResults =
      checkFile('${scenariosDir.path}/invented_widgets_view.mobile.dart');
  final inventedCheck = inventedResults
      .firstWhere((r) => r.name == 'no_invented_native_widgets');
  expect(!inventedCheck.ok,
      'invented-widgets fixture fails no_invented_native_widgets');
  expect(inventedCheck.message.contains('AppBoxKitNativeDialog'),
      '4d: failure names AppBoxKitNativeDialog (invented)');
  expect(inventedCheck.message.contains('AppBoxKitNativeCarousel'),
      '4d: failure names AppBoxKitNativeCarousel (invented)');

  // ---- 4e: valid_dart_syntax (the R5 false-clean gap, closed) ----
  // A8: clean fixture passes (balanced delimiters).
  final cleanSyntax = cleanResults
      .firstWhere((r) => r.name == 'valid_dart_syntax');
  expect(cleanSyntax.ok, 'clean fixture passes valid_dart_syntax (balanced)');

  // A9: truncated fixture FAILS (unbalanced delimiters — the R5 case).
  final truncResults =
      checkFile('${scenariosDir.path}/truncated_view.mobile.dart');
  final truncSyntax = truncResults
      .firstWhere((r) => r.name == 'valid_dart_syntax');
  expect(!truncSyntax.ok,
      'truncated fixture fails valid_dart_syntax (R5 false-clean, now caught)');
  expect(truncSyntax.message.contains('unbalanced'),
      '4e: failure names the imbalance');

  // ---- 8: no_cross_shell_imports (the S2 locality rule, at design time) ----
  // A scenario fixture's own path has no /ui/views/ segment (the path-shape
  // trap — the check would no-op), so the tree shapes are exercised BOTH with
  // synthetic paths (the harness's direct-call convention, same as A4/A7) AND
  // with a mini dir-tree fixture (shell_tree/) through the real gate wiring.
  final crossShellSrc = File(
          '${scenariosDir.path}/shell_tree/lib/ui/views/train_shell/leaf/cross_shell_view.mobile.dart')
      .readAsStringSync();
  final overlaySrc = File(
          '${scenariosDir.path}/shell_tree/lib/ui/views/train_shell/leaf/overlay_use.dart')
      .readAsStringSync();
  // A11: RED — a train_shell file importing shop_shell's VIEW fails, naming shop_shell.
  final crossView = checkNoCrossShellImports(
      crossShellSrc, 'lib/ui/views/train_shell/leaf/leaf_view.mobile.dart');
  expect(!crossView.ok, '8: cross-shell VIEW import fails no_cross_shell_imports');
  expect(crossView.message.contains('shop_shell'),
      '8: failure names the offending shell (shop_shell)');
  // A12: GREEN — the same tree shape importing shop_shell's OVERLAY is exempt.
  final crossOverlay = checkNoCrossShellImports(
      overlaySrc, 'lib/ui/views/train_shell/leaf/leaf_view.mobile.dart');
  expect(crossOverlay.ok,
      '8: cross-shell OVERLAY import (bottom_sheets/) is exempt');
  // A13: a path without /ui/views/ no-ops (protects standalone fixtures).
  final noTree = checkNoCrossShellImports(
      crossShellSrc, 'scripts/tests/scenarios/cross_shell_view.mobile.dart');
  expect(noTree.ok, '8: path without /ui/views/ no-ops (N/A, not a fail)');
  // A14: kit-internal / test paths are allowlisted.
  expect(
      checkNoCrossShellImports(crossShellSrc, 'lib/widgets/appbox_kit_native_demo.dart')
          .ok,
      '8: kit-internal path (/widgets/appbox_kit_*) allowlisted');
  // A15: the REAL gate wiring fires it — the RED fixture's own path carries
  // /ui/views/train_shell/, so gate() flags it naming shop_shell; the exempt
  // sibling passes the full per-file battery.
  final shellTreeGate = gate(
      '${scenariosDir.path}/shell_tree/lib/ui/views/train_shell/leaf/cross_shell_view.mobile.dart');
  final gateCross =
      shellTreeGate.firstWhere((r) => r.name == 'no_cross_shell_imports');
  expect(!gateCross.ok && gateCross.message.contains('shop_shell'),
      '8: gate() on the RED tree fixture fails naming shop_shell');
  expect(
      gate('${scenariosDir.path}/shell_tree/lib/ui/views/train_shell/leaf/overlay_use.dart')
          .every((r) => r.ok),
      '8: gate() on the overlay-exempt fixture is all-OK');
}

/// Self-test sections 9 (the checks mirrored from review_checklist.sh) and 10
/// (no_hardcoded_strings). Sources are inline: these are pure (src, path)
/// functions, so the sections run even when the vendored fixture tree is
/// absent.
void _selfTestPureSections(void Function(bool, String) expect) {
  // 9. the checks mirrored from review_checklist.sh (1w2, 1i, 1d).
  //    Sources are inline: these are pure (src, path) functions, so a fixture
  //    file would only add a place for the two gates to drift apart. Every
  //    negative has a positive twin — a check that failed everything would
  //    otherwise look calibrated.
  const leaf = 'lib/ui/views/train_shell/leaf/leaf_view.mobile.dart';
  const shell = 'lib/ui/views/train_shell/train_shell_view.dart';

  // 9a. 1w2 — spacing SizedBox.
  final spBad = checkNoAdhocSpacing(
      'Column(children: [SizedBox(height: 8), Text("x")]);', leaf);
  expect(!spBad.ok, '9a: single-arg spacing SizedBox fails no_adhoc_spacing');
  expect(spBad.message.contains('SizedBox(height: 8)'),
      '9a: no_adhoc_spacing names the offending token');
  expect(
      checkNoAdhocSpacing(
              'SizedBox(height: 120), // sizing: hero placeholder', leaf)
          .ok,
      '9a: `// sizing:` opt-out is honoured (read from the RAW source)');
  expect(
      checkNoAdhocSpacing('child: SizedBox(height: 120),', leaf).ok,
      '9a: SizedBox mounted as child: is sizing, not a gap');
  expect(checkNoAdhocSpacing('/// e.g. SizedBox(height: 8)', leaf).ok,
      '9a: the token in a doc comment is prose, not a violation');

  // 9b. 1i — scroll edge effect. The third case is the dangerous direction:
  //     naming the remedy in a comment must NOT grant a pass.
  expect(
      !checkScrollEdgeEffect(
              'CustomScrollView(slivers: [AppBoxKitGlassCard()]);', leaf)
          .ok,
      '9b: glass in a CustomScrollView without the effect fails');
  expect(
      checkScrollEdgeEffect(
              'CustomScrollView(slivers: [AppBoxKitGlassCard().scrollEdgeEffect()]);',
              leaf)
          .ok,
      '9b: the same tree with .scrollEdgeEffect() passes');
  expect(
      !checkScrollEdgeEffect(
              '/// TODO: wrap in AppBoxKitScrollEdgeEffect.\nCustomScrollView(slivers: [AppBoxKitGlassCard()]);',
              leaf)
          .ok,
      '9b: AppBoxKitScrollEdgeEffect named only in a comment grants no pass');

  // 9c. 1d — leaf app-bar contract.
  expect(!checkLeafAppBar('Scaffold(appBar: AppBoxKitNativeAppBar());', shell).ok,
      '9c: a shell view setting appBar: fails (shells stay bare)');
  expect(checkLeafAppBar('Scaffold(appBar: AppBoxKitNativeAppBar());', leaf).ok,
      '9c: the same code on a LEAF passes');
  expect(!checkLeafAppBar('Scaffold(appBar: AppBar());', leaf).ok,
      '9c: a stock AppBar on a leaf fails');
  expect(
      !checkLeafAppBar(
              'Scaffold(appBar: PreferredSize(child: AppBoxKitNativeAppBar()));', leaf)
          .ok,
      '9c: a PreferredSize wrapper fails');
  expect(checkLeafAppBar('/// Shells stay bare — no appBar: here.', shell).ok,
      '9c: the contract quoted in a doc comment does not violate itself');

  // 10. no_hardcoded_strings (the i18n discipline): copy comes from the ARB
  //     catalogs via AppLocalizations — a Text()/label: literal with 3+ ASCII
  //     letters in a view file fails, naming the literal. Sources are inline
  //     (pure (src, path) function, same convention as section 9).
  const i18nLeaf = 'lib/ui/views/train_shell/home/home_view.mobile.dart';

  // 10a. RED — hardcoded Text('Loading ...') fails, naming the literal.
  final hardcoded = checkNoHardcodedStrings(
      "Column(children: [Text('Loading ...'), Text(l10n.loading)]);", i18nLeaf);
  expect(!hardcoded.ok, '10a: hardcoded Text(\'Loading ...\') fails');
  expect(hardcoded.message.contains('Loading ...'),
      '10a: failure names the offending literal');

  // 10b. GREEN — copy resolved via AppLocalizations.of(context)! passes.
  expect(
      checkNoHardcodedStrings(
              'Text(AppLocalizations.of(context)!.loading);', i18nLeaf)
          .ok,
      '10b: AppLocalizations.of(context)!.loading passes');

  // 10c. GREEN — a scaffolder stub (STRUCTURE ONLY header) with a placeholder
  //      key Text('projects.home') is exempt.
  expect(
      checkNoHardcodedStrings(
              '// appbox-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.\n'
              "Text('projects.home');",
              i18nLeaf)
          .ok,
      '10c: scaffolder stub header exempts STRUCTURE ONLY placeholder keys');

  // 10d. GREEN — the non-copy exemptions: symbols, digits-only, asset paths,
  //      route paths, dotted keys/filenames.
  expect(checkNoHardcodedStrings("Text('✓');", i18nLeaf).ok,
      '10d: a bare symbol is not copy');
  expect(checkNoHardcodedStrings("Text('42');", i18nLeaf).ok,
      '10d: digits-only is not copy');
  expect(checkNoHardcodedStrings("Text('assets/logo.png');", i18nLeaf).ok,
      '10d: an asset path is not copy');
  expect(checkNoHardcodedStrings("Text('/settings');", i18nLeaf).ok,
      '10d: a route path is not copy');
  expect(checkNoHardcodedStrings("Text('projects.home');", i18nLeaf).ok,
      '10d: a dotted ARB key is not copy');

  // 10e. label: copy slots fire too; a commented-out Text() does not.
  expect(
      !checkNoHardcodedStrings(
              "InputDecoration(label: 'Search projects');", i18nLeaf)
          .ok,
      '10e: hardcoded label: literal fails');
  expect(
      checkNoHardcodedStrings(
              "// Text('Loading ...') — replaced by l10n", i18nLeaf)
          .ok,
      '10e: a commented-out Text() literal is not a violation');

  // 10f. non-view files are N/A (not a fail); kit-internal/test allowlisted.
  expect(checkNoHardcodedStrings("Text('Loading ...');", 'lib/main.dart').ok,
      '10f: a file outside /ui/views/ is N/A');
  expect(
      checkNoHardcodedStrings(
              "Text('Loading ...');", 'lib/widgets/appbox_kit_native_demo.dart')
          .ok,
      '10f: kit-internal path (/widgets/appbox_kit_*) allowlisted');
}

// ---------- CLI ----------

Future<void> main(List<String> args) async {
  if (args.contains('--self-test')) {
    exit(await _runSelfTest());
  }
  final json = args.contains('--json');
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln('Usage: dart enforce_design.dart <surface-dir-or-view-file> [--json] [--self-test]');
    exit(2);
  }
  final path = positional.first;
  final results = gate(path);
  final allOk = results.every((r) => r.ok);
  if (json) {
    print(jsonEncode({
      'ok': allOk,
      'checks': results
          .map((r) => {'name': r.name, 'ok': r.ok, 'message': r.message})
          .toList(),
    }));
  } else {
    for (final r in results) {
      final mark = r.ok ? '✓' : '✗';
      print('  $mark ${r.name}: ${r.message}');
    }
    print('');
    if (allOk) {
      print('OK — all ${results.length} checks passed.');
    } else {
      final failed = results.where((r) => !r.ok).length;
      print('FAIL — $failed/${results.length} checks failed.');
    }
  }
  exit(allOk ? 0 : 1);
}
