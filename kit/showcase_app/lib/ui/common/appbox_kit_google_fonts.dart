import 'package:google_fonts/google_fonts.dart';

import 'appbox_kit_fonts.dart';

/// Runtime resolution of the kit font catalogue through `google_fonts`.
///
/// Font law v2 (ratified): type families are **Google Fonts by name** on both
/// sides of the pipeline. `appbox_kit_fonts.dart` is the catalogue —
/// [AppBoxKitFontFamily.cssName] is the family name handed to `google_fonts`
/// here. Calling [appBoxKitGoogleFontFamily] registers the face's runtime
/// loader with Flutter's font registry and returns the fontFamily string that
/// `ThemeData`/`TextStyle.fontFamily:` will actually resolve — this is what
/// makes an unbundled catalogue face render instead of falling back to the
/// platform default silently (see the `appBoxKitFontIsBundled` note).
///
/// The scaffolder emits exactly this wiring into generated apps, driven by
/// `assets.manifest.json` font roles; the showcase app demos it in `main.dart`
/// by passing [appBoxKitDefaultGoogleFontFamily] to `appBoxKitLightTheme` /
/// `appBoxKitDarkTheme`.
///
/// Throws for a family name unknown to `google_fonts` — the catalogue only
/// lists Google Fonts faces, so an unknown name is a catalogue bug, not a
/// runtime condition. The sole non-Google exception ("source": "file" custom
/// brand fonts) bundles binaries under a pubspec `fonts:` block and never
/// reaches this resolver.
String appBoxKitGoogleFontFamily(AppBoxKitFontFamily face) =>
    GoogleFonts.getFont(face.cssName).fontFamily ?? face.cssName;

/// The [appBoxKitDefaultFont] face (`fonts.json` `default`), resolved and
/// registered through `google_fonts` — the app-wide `ui`-role family a host
/// passes to the kit theme builders.
String appBoxKitDefaultGoogleFontFamily() =>
    appBoxKitGoogleFontFamily(appBoxKitFontById(appBoxKitDefaultFont));
