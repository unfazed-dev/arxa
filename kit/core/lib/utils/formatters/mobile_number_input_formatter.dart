import 'package:flutter/services.dart';

class KitMobileNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Remove all non-digits
    final newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

// Format to Australian mobile number format -- 04__ ___ ___
    final buffer = StringBuffer();
    for (int i = 0; i < newText.length; i++) {
      if (i == 4 || i == 7) buffer.write(' ');
      buffer.write(newText[i]);
    }
    final formattedText = buffer.toString();
    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
