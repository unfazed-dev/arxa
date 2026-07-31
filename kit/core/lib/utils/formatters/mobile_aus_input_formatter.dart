import 'dart:math';

import 'package:flutter/services.dart';

class KitMobileAusInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;

    // Allow + only at the start
    if (text.startsWith('+')) {
      // Remove any other + signs that aren't at the start
      text = '+${text.substring(1).replaceAll('+', '')}';
    }

    // Remove any non-digit characters (except + at start)
    var formatted = text.startsWith('+')
        ? '+${text.substring(1).replaceAll(RegExp(r'[^\d]'), '')}'
        : text.replaceAll(RegExp(r'[^\d]'), '');

    if (formatted.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Handle international format
    if (formatted.startsWith('+61')) {
      // Keep the +61 prefix for international format
      var digitsAfterPrefix = formatted.substring(3);
      final buffer = StringBuffer('+61');

      // Add spaces after prefix
      if (digitsAfterPrefix.isNotEmpty) {
        buffer.write(
            ' ${digitsAfterPrefix.substring(0, min(3, digitsAfterPrefix.length))}');
      }
      if (digitsAfterPrefix.length > 3) {
        buffer.write(
            ' ${digitsAfterPrefix.substring(3, min(6, digitsAfterPrefix.length))}');
      }
      if (digitsAfterPrefix.length > 6) {
        buffer.write(
            ' ${digitsAfterPrefix.substring(6, min(9, digitsAfterPrefix.length))}');
      }

      return newValue.copyWith(
        text: buffer.toString(),
        selection: TextSelection.collapsed(offset: buffer.toString().length),
      );
    } else {
      // Handle local format (starting with 0)
      final buffer = StringBuffer();

      // First group (0412)
      buffer.write(formatted.substring(0, min(4, formatted.length)));

      // Second group (345)
      if (formatted.length > 4) {
        buffer.write(' ${formatted.substring(4, min(7, formatted.length))}');
      }

      // Third group (678)
      if (formatted.length > 7) {
        buffer.write(' ${formatted.substring(7, min(10, formatted.length))}');
      }

      return newValue.copyWith(
        text: buffer.toString(),
        selection: TextSelection.collapsed(offset: buffer.toString().length),
      );
    }
  }
}
