import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'kit_code_block.dart';

/// Markdown viewer, backed by `flutter_markdown_plus`.
///
/// Fenced code blocks render as [KitCodeBlock] (syntax highlighting via
/// `flutter_highlighting`); everything else follows the ambient
/// [MarkdownStyleSheet] unless [styleSheet] is given.
class KitMarkdown extends StatelessWidget {
  const KitMarkdown(
    this.data, {
    super.key,
    this.styleSheet,
    this.onTapLink,
    this.codeTheme,
    this.selectable = false,
  });

  /// The markdown source.
  final String data;

  /// Optional style overrides; falls back to the theme-derived sheet.
  final MarkdownStyleSheet? styleSheet;

  /// Link tap callback `(text, href, title)`.
  final MarkdownTapLinkCallback? onTapLink;

  /// Code-block token colors; defaults to [KitCodeBlock]'s GitHub light
  /// theme when null.
  final Map<String, TextStyle>? codeTheme;

  /// Whether the rendered text is selectable.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final builders = <String, MarkdownElementBuilder>{
      'code': _KitCodeElementBuilder(codeTheme),
    };
    if (selectable) {
      return MarkdownBody(
        data: data,
        styleSheet: styleSheet,
        onTapLink: onTapLink,
        builders: builders,
        selectable: true,
      );
    }
    return MarkdownBody(
      data: data,
      styleSheet: styleSheet,
      onTapLink: onTapLink,
      builders: builders,
    );
  }
}

/// Routes fenced code elements to [KitCodeBlock], mapping the
/// `language-xxx` info-string class onto the highlight.js language id.
class _KitCodeElementBuilder extends MarkdownElementBuilder {
  _KitCodeElementBuilder(this.codeTheme);

  final Map<String, TextStyle>? codeTheme;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = 'plaintext';
    final cls = element.attributes['class'];
    if (cls != null && cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }
    final code = element.textContent.trimRight();
    if (codeTheme == null) {
      return KitCodeBlock(code, language: language);
    }
    return KitCodeBlock(code, language: language, theme: codeTheme!);
  }
}
