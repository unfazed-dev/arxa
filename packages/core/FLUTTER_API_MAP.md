# stacked_kit — Flutter API Map (right problem → right API)

> **Version pin:** Flutter **3.44.0 / stable** (framework revision `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`,
> Dart **3.12.0**) — the repo's SDK, per `.metadata` + `flutter --version`; pubspecs declare `sdk: '>=3.0.3 <4.0.0'`.
> Re-pin this header when the repo's Flutter release line moves.
>
> **Verification:** every `E` (enforced) row and every deprecation claim below was fetched from
> api.flutter.dev on **2026-07-21**. "Removed" claims are evidenced by the class page returning
> **HTTP 404** (the SDK no longer documents the class) plus the sanctioned replacement's live page.
> All 16 `A` (advisory) rows were then fetch-verified the same way on **2026-07-22** — every cited
> URL returned HTTP 200 with the claimed API symbol present on the page (25/25 checks).
> This is an offline, curated artifact — do **not** refresh it from memory; re-fetch the cited URL.
> A new row whose source cannot be fetched stays `A` (advisory) and is never scanned.

## Boundary with the other gates

- **This map** bans *deprecated / removed Flutter SDK APIs* (things that no longer compile, or
  carry `@Deprecated` on the pinned release line). Enforced by `tools/api_map_scan.sh`.
- **[`NATIVE_COMPONENTS.md`](NATIVE_COMPONENTS.md)** bans *stock Flutter widgets where a Kit-native
  tier exists* (`TextField` → `KitNativeTextField`, …) — enforced by `enforce_design.dart` (4b/4c/4g)
  and `review_checklist.sh`. The two ban lists do not overlap by design: SDK-rot here, tier-drift there.
- The **kit column** only names surfaces the tier matrix / `ui_library/COMPONENTS.md` actually ship —
  never invent a `KitNative*` here that the matrix doesn't have.

## Grammar (parsed by `tools/api_map_scan.sh` — single source of truth)

One row per line inside the fenced `map` block, pipe-delimited, exactly 7 fields:

```
problem-class | mode | banned-tokens | sanctioned-material | sanctioned-cupertino | kit-equivalent | source-urls
```

- `mode` — `E`: scanner fails on any banned token in `$APPBOX_APP/lib`; `A`: guidance only, not scanned.
- `banned-tokens` — comma-separated literals matched against comment-stripped Dart source. Word
  boundaries are added around tokens that start/end alphanumeric. A `*` inside a token is a
  `.*?` wildcard (for `Scaffold.of(ctx)`-style variants). `—` = nothing banned.
- `—` in any other cell = not applicable (e.g. no Cupertino counterpart exists).
- Lines starting with `#` and blank lines inside the block are ignored.

```map
# problem-class | mode | banned-tokens | sanctioned-material | sanctioned-cupertino | kit-equivalent | source-urls
buttons | E | FlatButton, RaisedButton, OutlineButton | FilledButton, ElevatedButton, TextButton, OutlinedButton | CupertinoButton | KitNativeButton (+KitButtonStyle) | https://api.flutter.dev/flutter/material/FilledButton-class.html, https://api.flutter.dev/flutter/material/FlatButton-class.html (404 = removed)
icon-buttons | A | — | IconButton | CupertinoButton (icon child) | KitNativeIconButton | https://api.flutter.dev/flutter/material/IconButton-class.html
app-bars-back | A | — | AppBar, BackButton, SliverAppBar | CupertinoNavigationBar, CupertinoNavigationBarBackButton | KitNativeAppBar, KitNativeSliverAppBar | https://api.flutter.dev/flutter/material/AppBar-class.html, https://api.flutter.dev/flutter/cupertino/CupertinoNavigationBar-class.html
tab-bars-nav | A | — | NavigationBar, NavigationRail, TabBar | CupertinoTabBar | KitNativeTabBar, KitNativeNavigationRail | https://api.flutter.dev/flutter/material/NavigationBar-class.html, https://api.flutter.dev/flutter/cupertino/CupertinoTabBar-class.html
dialogs | A | — | showDialog, AlertDialog | showCupertinoDialog, CupertinoAlertDialog | kitShowNativeDialog() | https://api.flutter.dev/flutter/material/showDialog.html, https://api.flutter.dev/flutter/cupertino/CupertinoAlertDialog-class.html
sheets | A | — | showModalBottomSheet | showCupertinoModalPopup | kitShowNativeSheet(), KitBottomSheetService | https://api.flutter.dev/flutter/material/showModalBottomSheet.html, https://api.flutter.dev/flutter/cupertino/showCupertinoModalPopup.html
pickers-date-time | A | — | showDatePicker, showTimePicker | CupertinoDatePicker, CupertinoTimerPicker (via showCupertinoModalPopup) | — (no kit picker; present via kitShowNativeSheet) | https://api.flutter.dev/flutter/material/showDatePicker.html, https://api.flutter.dev/flutter/cupertino/CupertinoDatePicker-class.html
pickers-photo | A | — | — (no framework API — plugin: image_picker `pickImage`/`pickMedia` → XFile; `getImage`/`PickedFile` removed in image_picker 1.0.0) | same plugin | stacked_kit_media | https://pub.dev/packages/image_picker
text-fields-forms | E | ToolbarOptions, toolbarOptions: | TextField, TextFormField, Form (context menu: `contextMenuBuilder`) | CupertinoTextField, CupertinoFormSection | KitNativeTextField, KitNativeInputBar | https://api.flutter.dev/flutter/widgets/ToolbarOptions-class.html (@Deprecated v3.3), https://api.flutter.dev/flutter/material/TextField-class.html
lists-sections | A | — | ListView, ListTile | CupertinoListSection(.insetGrouped), CupertinoListTile | KitListSection, KitListTile | https://api.flutter.dev/flutter/cupertino/CupertinoListSection-class.html, https://api.flutter.dev/flutter/material/ListTile-class.html
spacing | A | — | SizedBox, EdgeInsets, Padding | (same widgets) | verticalSpace(), spacedDivider (core/lib/common/kit_ui_helpers.dart) | https://api.flutter.dev/flutter/widgets/SizedBox-class.html
colors-alpha | E | .withOpacity( | .withValues(alpha: x) | .withValues(alpha: x) | KitColors/KitDarkColors tokens | https://api.flutter.dev/flutter/dart-ui/Color/withOpacity.html (@Deprecated 'Use .withValues() to avoid precision loss.')
colors-theme-access | A | — (kit rule: no `Color(0x…)`/`Colors.*` literals — enforce_design.dart 2x) | Theme.of(context).colorScheme, Color.fromARGB, Color.from | CupertinoDynamicColor, CupertinoColors.of | KitColors/KitDarkColors, kitLightTheme()/kitDarkTheme() | https://api.flutter.dev/flutter/dart-ui/Color-class.html
colors-channel-accessors | A | — (deprecated, advisory: `.red`/`.green`/`.blue`/`.opacity` → `.r`/`.g`/`.b`/`.a`; `.value` → `.toARGB32()`) | Color.toARGB32(), .r/.g/.b/.a doubles | (same) | — | https://api.flutter.dev/flutter/dart-ui/Color/red.html (@Deprecated), https://api.flutter.dev/flutter/dart-ui/Color-class.html
text-theme-names | E | .headline1, .headline2, .headline3, .headline4, .headline5, .headline6, .bodyText1, .bodyText2, .subtitle1, .subtitle2 | displayLarge…labelSmall (15 M3 names — the only properties left on TextTheme; 2018 names removed) | CupertinoTextThemeData | kitLightTheme()/kitDarkTheme() textTheme | https://api.flutter.dev/flutter/material/TextTheme-class.html
snackbars-toasts | E | Scaffold.of(*).showSnackBar | ScaffoldMessenger.of(context).showSnackBar (ScaffoldState has no showSnackBar) | — (no Cupertino snackbar) | KitNotificationService.show (CNToast on iOS) | https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html, https://api.flutter.dev/flutter/material/ScaffoldState-class.html
loading-progress | A | — | CircularProgressIndicator, LinearProgressIndicator | CupertinoActivityIndicator | KitNativeLoadingIndicator, KitNativeProgress | https://api.flutter.dev/flutter/material/CircularProgressIndicator-class.html, https://api.flutter.dev/flutter/cupertino/CupertinoActivityIndicator-class.html
switches-sliders-segmented | A | — | Switch, Slider, RangeSlider, SegmentedButton | CupertinoSwitch, CupertinoSlider, CupertinoSlidingSegmentedControl | KitNativeSwitch, KitNativeSlider, KitNativeRangeSlider, KitNativeSegmentedControl | https://api.flutter.dev/flutter/cupertino/CupertinoSlidingSegmentedControl-class.html, https://api.flutter.dev/flutter/material/Switch-class.html
scroll-behavior | E | isAlwaysShown: | Scrollbar(thumbVisibility: …), CustomScrollView, ScrollConfiguration | CupertinoScrollbar | KitScrollEdgeEffect (content under pinned chrome) | https://api.flutter.dev/flutter/material/Scrollbar-class.html (param is thumbVisibility; isAlwaysShown gone)
media-query-size | A | — (guidance: prefer sized `MediaQuery.*Of` lookups) | MediaQuery.sizeOf(context) over MediaQuery.of(context).size | (same) | screenWidth()/screenHeight() helpers | https://api.flutter.dev/flutter/widgets/MediaQuery/sizeOf.html
images | A | — | Image.asset, Image.network | (same widgets — content, no native tier) | KitImage | https://api.flutter.dev/flutter/widgets/Image-class.html
gesture-handling | A | — | GestureDetector, InkWell/InkResponse (needs Material ancestor) | CupertinoButton (tappable) | KitNativeIconButton/KitNativeButton for chrome taps | https://api.flutter.dev/flutter/widgets/GestureDetector-class.html, https://api.flutter.dev/flutter/material/InkWell-class.html
navigation-pop-scope | E | WillPopScope( | PopScope(canPop:, onPopInvokedWithResult:) — `onPopInvoked` itself deprecated after v3.22; NavigatorPopHandler for nested navigators | (same — widgets library) | — (router seam: KitNavigationControllerService) | https://api.flutter.dev/flutter/widgets/WillPopScope-class.html (@Deprecated v3.12), https://api.flutter.dev/flutter/widgets/PopScope-class.html
```

## Notes for scaffolders

- **Deliberate exclusions** (considered, kept advisory or out):
  `Color` channel accessors (`.red`/`.opacity`) are `@Deprecated` but only *advisory* — tokens like
  `.red` false-positive on `Colors.red`; fix opportunistically, don't gate. `TextTheme` 2018 aliases
  `.caption`/`.button`/`.overline` are likewise excluded from the enforced set (generic identifiers);
  their 6 unambiguous siblings above are enforced. `MediaQuery.of().size` is a perf preference, not
  a deprecation — advisory. Stock-widget bans (`TextField(`, `Switch(`, `showModalBottomSheet(`, …)
  belong to `enforce_design.dart`, not here.
- **Deprecated-vs-removed:** `E` rows fail the gate for both. Removed symbols (FlatButton family,
  ToolbarOptions, ScaffoldState.showSnackBar, 2018 TextTheme getters, Scrollbar.isAlwaysShown) are
  compile errors on 3.44 — the scanner catches them before the analyzer has to.
- **Scanner caveat:** matching is literal on comment-stripped source; a banned symbol inside a
  *string literal* still hits (same trade-off as `capability_scan.sh`). Don't name banned APIs in
  user-facing strings.
