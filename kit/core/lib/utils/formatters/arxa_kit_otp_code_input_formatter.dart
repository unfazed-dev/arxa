import 'package:flutter/services.dart';

class ArxaKitOtpCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Remove all non-digits
    final newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Format to OTP code format -- 99 99 99
    final buffer = StringBuffer();
    for (int i = 0; i < newText.length; i++) {
      if (i == 1 || i == 2 || i == 3 || i == 4 || i == 5) buffer.write('  ');
      buffer.write(newText[i]);
    }
    final formattedText = buffer.toString();

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
