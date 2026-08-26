import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';

/// Pure parse/wire-format behaviors of the notes enums — the route contract
/// (`?quickAction=`, `folder/:id`) lives on these types.
void main() {
  group('ShowcaseQuickAction.fromRoute', () {
    test(
        'search-and-attachments.media-attachments.attach-a-photo-to-a-note — '
        'parses the wire values into their actions', () {
      expect(
          ShowcaseQuickAction.fromRoute('camera'), ShowcaseQuickAction.camera);
      expect(ShowcaseQuickAction.fromRoute('mic'), ShowcaseQuickAction.mic);
    });

    test('an absent or unknown route param parses to no quick action', () {
      expect(ShowcaseQuickAction.fromRoute(null), isNull);
      expect(ShowcaseQuickAction.fromRoute(''), isNull);
      expect(ShowcaseQuickAction.fromRoute('bogus'), isNull);
    });

    test('.name IS the route param value (the wire format must not change)',
        () {
      expect(ShowcaseQuickAction.camera.name, 'camera');
      expect(ShowcaseQuickAction.mic.name, 'mic');
    });
  });

  group('ShowcaseFolderScope.parse', () {
    test(
        'notes.folders.browse-the-notes-in-a-folder — the sentinels parse to '
        'their own scope types and round-trip their route keys', () {
      final all = ShowcaseFolderScope.parse('all');
      expect(all, isA<ShowcaseFolderScopeAll>());
      expect(all.key, 'all');

      final trash = ShowcaseFolderScope.parse('trash');
      expect(trash, isA<ShowcaseFolderScopeTrash>());
      expect(trash.key, 'trash');
    });

    test(
        'notes.folders.browse-the-notes-in-a-folder — any other key is a '
        'folder id, carried through verbatim', () {
      const uuid = 'f47ac10b-58cc-4372-a567-0e02b2c3d479';
      final scope = ShowcaseFolderScope.parse(uuid);
      expect(scope, isA<ShowcaseFolderScopeFolder>());
      expect((scope as ShowcaseFolderScopeFolder).folderId, uuid);
      expect(scope.key, uuid);
    });
  });
}
