import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:arxa_kit_showcase_app/app/app.locator.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_notes_widgets/showcase_note_photo_strip_widget.dart';

import 'package:arxa_kit_core/platform/arxa_kit_platform.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ArxaKitNativeIconButton, CNTabBarRouteObserver, StackedService;

import 'helpers/test_helpers.dart';

class _FakeAttachment extends Fake implements ShowcaseNoteAttachmentModel {}

/// Photo-strip perf contract (sweep gap: the 84pt thumb decoded the full
/// capture — up to 2048px — per cell). The strip must bound the decode to
/// display pixels; the fullscreen viewer keeps the full capture on purpose.
void main() {
  late MockShowcaseNotesFacadeService notes;

  setUpAll(() => registerFallbackValue(_FakeAttachment()));

  setUp(() {
    registerServices();
    registerArxaKitActionServices();
    notes = getAndRegisterShowcaseNotesFacadeService();
  });

  tearDown(() => locator.reset());

  testWidgets(
      '[Photo display] — attach-a-photo-to-a-note — strip thumbnails decode at '
      'display pixels (84pt x devicePixelRatio), never the full capture',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    when(() => notes.note$('n1')).thenAnswer((_) => Stream.value(null));
    when(() => notes.resolvePath(any())).thenAnswer((_) async => '/tmp/a1.jpg');
    final vm = ShowcaseNoteEditorViewModel(noteId: 'n1');
    addTearDown(vm.dispose);
    // No pumpEventQueue(): testWidgets runs in FakeAsync where its zero-delay
    // futures never fire — pumpWidget's pump flushes the note$ microtask.

    final photo = ShowcaseNoteAttachmentModel(
      id: 'a1',
      kind: ShowcaseNoteAttachmentKind.photo,
      fileName: 'a1.jpg',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShowcaseNotePhotoStripWidget(viewModel: vm, photos: [photo]),
      ),
    ));
    await tester.pump(); // the memoized resolvePath future lands

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<ResizeImage>(),
        reason: 'cacheWidth/cacheHeight wrap the FileImage in a ResizeImage');
    final resize = provider as ResizeImage;
    expect(resize.width, 168,
        reason: '84pt x dpr 2.0 — the decode request is bounded to the thumb');
    expect(resize.height, 168);

    await tester.pump();
    tester.takeException(); // FileImage 404s on the fake path — not under test
  });

  testWidgets(
      '[Photo display] — attach-a-photo-to-a-note — the lightbox presents from '
      'the root navigator over ALL chrome and brackets the shared modal depth '
      'while open', (tester) async {
    ArxaKitPlatform.override =
        const ArxaKitPlatformOverride(isAndroid: true);
    addTearDown(ArxaKitPlatform.reset);
    when(() => notes.note$('n1')).thenAnswer((_) => Stream.value(null));
    when(() => notes.resolvePath(any())).thenAnswer((_) async => '/tmp/a1.jpg');
    final vm = ShowcaseNoteEditorViewModel(noteId: 'n1');
    addTearDown(vm.dispose);
    final photo = ShowcaseNoteAttachmentModel(
      id: 'a1',
      kind: ShowcaseNoteAttachmentKind.photo,
      fileName: 'a1.jpg',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    // Mirror the app shells: tab scaffold with chrome, strip inside a NESTED
    // navigator (the tab's router outlet).
    await tester.pumpWidget(MaterialApp(
      navigatorKey: StackedService.navigatorKey,
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) =>
                ShowcaseNotePhotoStripWidget(viewModel: vm, photos: [photo]),
          ),
        ),
        bottomNavigationBar: const SizedBox(height: 64),
      ),
    ));
    await tester.pump();
    tester.takeException(); // FileImage 404 on the fake path

    final depthBefore = CNTabBarRouteObserver.anyModalDepth.value;
    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();

    expect(CNTabBarRouteObserver.anyModalDepth.value, depthBefore + 1,
        reason: 'every kit sheet/dialog brackets anyModalDepth — without it '
            'native glass on the obscured page composites above the lightbox '
            '(arxa_kit_native_sheet.dart:145-153)');
    expect(tester.getSize(find.byType(InteractiveViewer)),
        const Size(800, 600),
        reason: 'root-navigator presentation covers the shared chrome too; a '
            'nested presentation stops at the tab bar (64px shorter)');

    await tester.tap(find.byType(ArxaKitNativeIconButton));
    await tester.pumpAndSettle();
    expect(CNTabBarRouteObserver.anyModalDepth.value, depthBefore,
        reason: 'the bracket unwinds on dismiss');
  });
}
