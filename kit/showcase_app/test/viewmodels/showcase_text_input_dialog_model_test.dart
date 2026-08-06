import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_showcase_app/app/app.locator.dart';
import 'package:appbox_kit_showcase_app/ui/dialogs/showcase_text_input_dialog/showcase_text_input_dialog_model.dart';


// Dialog demos have no intake story in map.json — behavior sentence only.
void main() {
  group('ShowcaseTextInputDialogModel', () {
    tearDown(() => locator.reset());

    test('seeds the controller with the initial text and disposes it with the model',
        () {
      // given
      final model = ShowcaseTextInputDialogModel('draft note');
      // when (construction is the act — the dialog opens pre-filled)
      // then
      expect(model.controller.text, 'draft note');
      // when
      model.dispose();
      // then — the controller dies with the model
      expect(() => model.controller.text = 'x', throwsFlutterError);
    });
  });
}
