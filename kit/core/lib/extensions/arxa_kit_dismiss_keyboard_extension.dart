import 'package:flutter/widgets.dart';

extension ArxaKitDismissKeyboardExtension on BuildContext {
  /// Dismisses the virtual keyboard by unfocusing the current focus scope.
  void dismissKeyboard() {
    FocusScope.of(this).unfocus();
  }
}
