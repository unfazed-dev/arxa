import 'package:flutter/widgets.dart';

extension KitDismissKeyboardExtension on BuildContext {
  /// Dismisses the virtual keyboard by unfocusing the current focus scope.
  void dismissKeyboard() {
    FocusScope.of(this).unfocus();
  }
}
