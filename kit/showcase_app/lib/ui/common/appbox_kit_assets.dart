// App Assets — named bundled-asset vocabulary (showcase app copy)
//
// CONVENTION (one-vocabulary rule, ratified in the Q-grill):
// - Every bundled asset path in this app is declared here as an
//   `abx`-prefixed const — `Img` for assets/images/. Code and designs
//   refer to the NAME, never to a loose path string.
// - Asset layout is TYPE-FIRST, the way Flutter manages assets
//   (assets/images/, plus sibling type folders only when a real need
//   lands, e.g. assets/audio/), registered as directories in pubspec.yaml.
// - The kit already manages the other asset classes — fonts ship inside the
//   kit package (appbox_kit_fonts.dart catalogue + vendored binaries) and
//   icons are code glyphs (appbox_kit_glyphs.dart Lucide map). An app
//   declares NO font or icon assets of its own.

// Brand
const String abxImgShowcaseLogo = 'assets/images/showcase_logo.png';
