// App Assets — named bundled-asset vocabulary (generic kit template)
//
// CONVENTION (one-vocabulary rule, ratified in the Q-grill):
// - Every bundled asset path in an appbox app is declared here as an
//   `abx`-prefixed const — `Img` for assets/images/. Code and designs
//   refer to the NAME, never to a loose path string.
// - Asset layout is TYPE-FIRST, the way Flutter manages assets
//   (assets/images/, plus sibling type folders only when a real need
//   lands, e.g. assets/audio/), registered as directories in pubspec.yaml.
// - Fonts are Google Fonts by name (google_fonts package, families from
//   assets.manifest.json font roles) — no font binaries, no pubspec fonts:
//   block, unless the manifest declares "source": "file" (custom brand font
//   uploaded at intake). UI icons are code glyphs (appbox_kit_glyphs.dart
//   Lucide map). The brand icon (assets/brand-icons/) is dual-role:
//   flutter_launcher_icons master (derived platform icons committed) AND a
//   runtime asset (splash / startup brand logo), registered in pubspec and
//   named abxImgBrandIcon in the app copy of this file.
//   An app declares NO font assets of its own. Ruling exception: appbox studio's own
//   design tree uses ownership folders (assets/studio/, assets/portalo/
//   feature-scoped) — that exception is studio-only and lives designer-side.
// - Each app owns its own appbox_kit_assets.dart (scaffolded into
//   lib/ui/common/ alongside the kit common copy). This kit file carries
//   only assets generic to every appbox app; app-specific assets belong in
//   the app copy.
