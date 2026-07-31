import 'package:flutter/material.dart';
import 'package:flutter_highlighting/flutter_highlighting.dart';
import 'package:flutter_highlighting/themes/github.dart';

/// Syntax-highlighted code block, backed by `flutter_highlighting`.
///
/// Also used by [KitMarkdown] for fenced code blocks — [language] is the
/// highlight.js language id (`dart`, `json`, `bash`, …; `plaintext` disables
/// highlighting).
class KitCodeBlock extends StatelessWidget {
  const KitCodeBlock(
    this.code, {
    super.key,
    this.language = 'plaintext',
    this.theme = githubTheme,
    this.padding = const EdgeInsets.all(12),
    this.textStyle = const TextStyle(fontFamily: 'monospace', fontSize: 13),
  });

  /// The source to render.
  final String code;

  /// highlight.js language id; `plaintext` renders without highlighting.
  final String language;

  /// Token colors; defaults to the GitHub light theme.
  final Map<String, TextStyle> theme;

  /// Inner padding around the code.
  final EdgeInsetsGeometry padding;

  /// Base text style for unhighlighted spans.
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return HighlightView(
      code,
      languageId: language,
      theme: theme,
      padding: padding,
      textStyle: textStyle,
    );
  }
}
