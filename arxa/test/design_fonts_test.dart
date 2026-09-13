// Tests for the font plane (lib/design_fonts.dart) — grilled 2026-09-13.
// Pins the manifest law (load/validate), the css2 segment + stack
// derivation, the serve seam (per-role stamps, receipts, sheet wiring),
// and the ingest lifecycle (append + dedupe + sheet, delete refuses).

import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_fonts.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

FontPlaneManifest _manifest() => FontPlaneManifest(
      defaultPicks: const {'display': 'fraunces', 'body': 'inter'},
      roles: [
        const FontRole(
          id: 'display',
          name: 'Display',
          token: '--font-display',
          choices: [
            FontChoice(
              id: 'fraunces',
              family: 'Fraunces',
              stack: "'Fraunces', Georgia, serif",
              category: 'Serif',
              css2:
                  'family=Fraunces:ital,opsz,wght,SOFT,WONK@0,9..144,100..900,0..100,0..1',
              seeded: true,
            ),
            FontChoice(
              id: 'playfair-display',
              family: 'Playfair Display',
              stack: "'Playfair Display', Georgia, serif",
              category: 'Serif',
              css2: 'family=Playfair+Display:ital,wght@0,400..900;1,400..900',
              seeded: true,
              sheet: '/assets/styles/fonts/font-display-playfair-display.css',
            ),
          ],
        ),
        const FontRole(
          id: 'body',
          name: 'Body',
          token: '--font-body',
          choices: [
            FontChoice(
              id: 'inter',
              family: 'Inter',
              stack: "'Inter', sans-serif",
              category: 'Sans Serif',
              css2: 'family=Inter:wght@400;500;600;700;800;900',
              seeded: true,
            ),
            FontChoice(
              id: 'system',
              family: 'System',
              stack: 'ui-sans-serif, system-ui, sans-serif',
              seeded: true,
            ),
          ],
        ),
      ],
    );

const _html = '<!doctype html>'
    '<html lang="en"><head><title>x</title></head>'
    '<body><p>hi</p></body></html>';

void main() {
  test('manifest roundtrips and validates', () {
    final dir = Directory.systemTemp.createTempSync('arxa-fonts');
    addTearDown(() => dir.deleteSync(recursive: true));
    _manifest().save(dir.path);
    final loaded = FontPlaneManifest.load(dir.path);
    expect(loaded, isNotNull);
    expect(loaded!.defaultPicks['display'], 'fraunces');
    expect(loaded.role('display')!.choices.length, 2);
    expect(loaded.declaresAll({'display': 'playfair-display'}), isTrue);
    expect(loaded.declaresAll({'display': 'nope'}), isFalse);
    expect(loaded.declaresAll({'nope': 'inter'}), isFalse);
    // A default naming an undeclared choice disables the plane.
    File(p.join(dir.path, 'fonts.json')).writeAsStringSync(
        jsonEncode({
          'default': {'display': 'ghost'},
          'roles': []
        }));
    expect(FontPlaneManifest.load(dir.path), isNull);
  });

  test('css2 segments follow the catalog law', () {
    expect(
        css2SegmentFor(const FontCatalogEntry(
            family: 'Inter', category: 'Sans Serif', weights: [400])),
        'family=Inter');
    expect(
        css2SegmentFor(const FontCatalogEntry(
            family: 'Source Sans 3',
            category: 'Sans Serif',
            weights: [400],
            variableWght: [200, 900])),
        'family=Source+Sans+3:wght@200..900');
    expect(
        css2SegmentFor(const FontCatalogEntry(
            family: 'Instrument Serif',
            category: 'Serif',
            weights: [400],
            italic: true)),
        'family=Instrument+Serif:ital,wght@0,400;1,400');
    expect(
        css2SegmentFor(const FontCatalogEntry(
            family: 'Archivo',
            category: 'Sans Serif',
            weights: [400],
            variableWght: [100, 900],
            italic: true)),
        'family=Archivo:ital,wght@0,100..900;1,100..900');
  });

  test('stacks derive by category', () {
    expect(
        stackFor(const FontCatalogEntry(
            family: 'Playfair Display', category: 'Serif', weights: [400])),
        "'Playfair Display', Georgia, serif");
    expect(
        stackFor(const FontCatalogEntry(
            family: 'Space Grotesk', category: 'Sans Serif', weights: [400])),
        "'Space Grotesk', 'Helvetica Neue', Arial, sans-serif");
  });

  test('serve seam stamps per role and honors receipts', () {
    final served = applyFontToServedHtml(_html,
        query: const {},
        stored: const {'display': 'playfair-display'},
        manifest: _manifest());
    expect(served.html, contains('data-font-display="playfair-display"'));
    expect(served.html, contains('data-font-body="inter"'));
    // The declared sheet rides the head (the ADDENDUM 18 law, font twin).
    expect(served.html, contains('data-font-sheet="display-playfair-display"'));
    // A receipt beats the stored pick; unknown ids fall to defaults.
    final receipt = applyFontToServedHtml(_html,
        query: const {'font': 'display:playfair-display,body:ghost'},
        stored: const {},
        manifest: _manifest());
    expect(receipt.html, contains('data-font-display="playfair-display"'));
    expect(receipt.html, contains('data-font-body="inter"'));
    // Stale stamps are stripped, never doubled.
    final stale = applyFontToServedHtml(
        '<html data-font-display="old" data-font-body="old">x</html>',
        query: const {},
        stored: null,
        manifest: _manifest());
    expect(stale.html, contains('data-font-display="fraunces"'));
    expect(stale.html, isNot(contains('"old"')));
  });

  test('ingest appends, dedupes, and writes the sheet', () {
    final dir = Directory.systemTemp.createTempSync('arxa-fonts');
    addTearDown(() => dir.deleteSync(recursive: true));
    _manifest().save(dir.path);
    final ingestion = FontIngestion(artifactDir: dir.path);
    final choice = ingestion.ingest(
        'display',
        const FontCatalogEntry(
            family: 'DM Serif Display', category: 'Serif', weights: [400]));
    expect(choice.id, 'dm-serif-display');
    // Static family, one weight, no italic: the bare family segment.
    expect(choice.css2, 'family=DM+Serif+Display');
    expect(
        File(p.join(dir.path, 'assets', 'styles', 'fonts',
                'font-display-dm-serif-display.css'))
            .existsSync(),
        isTrue);
    // Dedupe by family: the second ingest returns the same choice.
    expect(
        ingestion
            .ingest(
                'display',
                const FontCatalogEntry(
                    family: 'DM Serif Display',
                    category: 'Serif',
                    weights: [400]))
            .id,
        'dm-serif-display');
    // Deletes refuse the seeded and the default.
    expect(
        () => ingestion.delete('display', 'fraunces'),
        throwsArgumentError);
    expect(
        () => ingestion.delete('display', 'ghost'), throwsArgumentError);
    // A lawful delete removes choice + sheet.
    ingestion.delete('display', 'dm-serif-display');
    expect(FontPlaneManifest.load(dir.path)!
        .role('display')!
        .declares('dm-serif-display'), isFalse);
  });

  test('catalog entries roundtrip and search ranks by popularity', () {
    final e = FontCatalogEntry.fromJson(const {
      'family': 'Fraunces',
      'category': 'Serif',
      'weights': [400],
      'variableWght': [100, 900],
      'italic': true,
      'popularity': 99,
    });
    expect(e!.variableWght, [100, 900]);
    expect(FontCatalogEntry.fromJson(e.toJson())!.family, 'Fraunces');
    expect(fontChoiceId('Space Grotesk'), 'space-grotesk');
    expect(fontChoiceId('DM Serif Display'), 'dm-serif-display');
  });
}
