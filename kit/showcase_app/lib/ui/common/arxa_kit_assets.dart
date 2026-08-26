// App Assets — named bundled-asset vocabulary (showcase app copy)
//
// CONVENTION (one-vocabulary rule, ratified in the Q-grill):
// - Every bundled asset path in this app is declared here as an
//   `abx`-prefixed const — `Img` for assets/images/. Code and designs
//   refer to the NAME, never to a loose path string.
// - Asset layout is TYPE-FIRST, the way Flutter manages assets
//   (assets/images/, plus sibling type folders only when a real need
//   lands, e.g. assets/audio/), registered as directories in pubspec.yaml.
// - Fonts are Google Fonts by name (google_fonts package, families from
//   assets.manifest.json font roles) — no font binaries, no pubspec fonts:
//   block, unless the manifest declares "source": "file" (custom brand font
//   uploaded at intake). UI icons are code glyphs (arxa_kit_glyphs.dart
//   Lucide map). An app declares NO font assets and no per-platform
//   hand-authored icon sets of its own.
// - The brand icon (assets/brand-icons/) is dual-role: master for
//   flutter_launcher_icons (derived platform icons committed) AND a runtime
//   asset (splash / startup brand logo), registered in pubspec and named
//   here as abxImgBrandIcon.

// Brand
const String abxImgShowcaseLogo = 'assets/images/showcase_logo.png';
const String abxImgBrandIcon = 'assets/brand-icons/arxa-icon.png';
