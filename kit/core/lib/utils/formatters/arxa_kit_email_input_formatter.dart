import 'package:flutter/services.dart';

/// A [TextInputFormatter] that formats email input by:
/// - Converting to lowercase
/// - Removing invalid email characters
/// - Preventing multiple @ symbols
/// - Handling common email domain suggestions
class ArxaKitEmailInputFormatter extends TextInputFormatter {
  static const _validEmailChars = r'[a-zA-Z0-9.!#$%&*+/=?^_`{|}~@-]';
  static const _commonDomains = [
    'gmail.com',
    'yahoo.com',
    'outlook.com',
    'hotmail.com',
    'icloud.com',
    'proton.me',
    'optusnet.com.au',
    'telstra.com',
    'bigpond.com',
    'bigpond.net.au'
  ];

  /// Minimum number of characters after @ before suggesting domain
  static const _minDomainCharsForSuggestion = 4;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Convert to lowercase
    var text = newValue.text.toLowerCase();

    // Remove invalid characters
    text = text.replaceAll(RegExp('[^$_validEmailChars]'), '');

    // Handle @ symbol
    if (text.contains('@')) {
      // Only keep the first @ symbol
      final parts = text.split('@');
      if (parts.length > 2) {
        text = '${parts[0]}@${parts[1]}';
      }

      // Handle domain suggestions
      if (parts.length == 2) {
        final domain = parts[1];
        // Only suggest if we have enough characters
        if (domain.length >= _minDomainCharsForSuggestion) {
          // Find all matching domains
          final matches = _commonDomains
              .where(
                (d) => d.startsWith(domain),
              )
              .toList();

          // Only suggest if we have exactly one match or the domain exactly matches one option
          if (matches.length == 1 &&
              domain != matches[0] &&
              oldValue.text.length < newValue.text.length) {
            text = '${parts[0]}@${matches[0]}';
          }
        }
      }
    }

    // Update selection
    final selection = newValue.selection.copyWith(
      baseOffset: text.length,
      extentOffset: text.length,
    );

    return TextEditingValue(
      text: text,
      selection: selection,
      composing: TextRange.empty,
    );
  }
}
