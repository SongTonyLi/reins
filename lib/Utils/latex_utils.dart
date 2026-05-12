import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// Simplified boundary check inspired by open-webui's ALLOWED_SURROUNDING_CHARS.
// A $ delimiter is valid if preceded/followed by whitespace, punctuation, or start/end of string.

/// Pre-processes message content to convert LaTeX delimiters from $ notation
/// to \(\) and \[\] notation, applying open-webui's boundary checking to avoid
/// false matches (e.g. "$100" should not be treated as math).
///
/// This must happen BEFORE markdown parsing to avoid $ conflicting with ** bold.
String preprocessLatex(String content) {
  final buffer = StringBuffer();
  var i = 0;

  while (i < content.length) {
    // Check for display math $$...$$
    if (i < content.length - 1 && content[i] == '\$' && content[i + 1] == '\$') {
      // Check allowed boundary before
      final before = i > 0 ? content[i - 1] : ' ';
      if (_isAllowedBefore(before)) {
        final closeIdx = content.indexOf('\$\$', i + 2);
        if (closeIdx != -1) {
          final mathContent = content.substring(i + 2, closeIdx);
          buffer.write('\\[');
          buffer.write(mathContent);
          buffer.write('\\]');
          i = closeIdx + 2;
          continue;
        }
      }
    }

    // Check for inline math $...$
    if (content[i] == '\$') {
      final before = i > 0 ? content[i - 1] : ' ';
      if (_isAllowedBefore(before)) {
        // Find closing $ (not $$, not escaped, not spanning newlines)
        final closeIdx = _findClosingDollar(content, i + 1);
        if (closeIdx != -1) {
          final after = closeIdx + 1 < content.length ? content[closeIdx + 1] : ' ';
          if (_isAllowedAfter(after)) {
            final mathContent = content.substring(i + 1, closeIdx);
            // Skip if content is empty or looks like currency ($100)
            if (mathContent.isNotEmpty && !RegExp(r'^\d').hasMatch(mathContent)) {
              buffer.write('\\(');
              buffer.write(mathContent);
              buffer.write('\\)');
              i = closeIdx + 1;
              continue;
            }
          }
        }
      }
    }

    buffer.write(content[i]);
    i++;
  }

  return buffer.toString();
}

/// Find the closing $ for inline math, handling escapes.
int _findClosingDollar(String src, int start) {
  for (var i = start; i < src.length; i++) {
    if (src[i] == '\\') {
      i++; // skip escaped char
      continue;
    }
    if (src[i] == '\n') return -1; // inline math can't span lines
    if (src[i] == '\$') {
      // Make sure it's not $$ (display math)
      if (i + 1 < src.length && src[i + 1] == '\$') return -1;
      return i;
    }
  }
  return -1;
}

bool _isAllowedBefore(String char) {
  // Whitespace, punctuation, or common delimiters
  return RegExp(r'[\s\p{P}\p{S}]', unicode: true).hasMatch(char);
}

bool _isAllowedAfter(String char) {
  return RegExp(r'[\s\p{P}\p{S}]', unicode: true).hasMatch(char);
}

/// Inline syntax for \(...\) LaTeX expressions.
class SafeLatexInlineSyntax extends md.InlineSyntax {
  SafeLatexInlineSyntax() : super(r'\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('latex', match[1]!.trim());
    parser.addNode(el);
    return true;
  }
}

/// Block syntax for \[...\] display math.
class SafeLatexBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\\\[(.*)$');

  @override
  md.Node parse(md.BlockParser parser) {
    final buffer = StringBuffer();
    final firstLine = parser.current.content;

    // Single line: \[...\]
    final singleLine = RegExp(r'^\\\[(.*?)\\\]$').firstMatch(firstLine);
    if (singleLine != null) {
      buffer.write(singleLine.group(1)!.trim());
      parser.advance();
    } else {
      // Multi-line: collect until \]
      final opening = firstLine.replaceFirst(RegExp(r'^\\\['), '').trim();
      if (opening.isNotEmpty) buffer.writeln(opening);
      parser.advance();

      while (!parser.isDone) {
        final line = parser.current.content;
        if (line.trim() == '\\]' || line.trimRight().endsWith('\\]')) {
          final closing = line.replaceFirst(RegExp(r'\\\]\s*$'), '').trim();
          if (closing.isNotEmpty) buffer.write(closing);
          parser.advance();
          break;
        }
        buffer.writeln(line);
        parser.advance();
      }
    }

    return md.Element.text('latexBlock', buffer.toString().trim());
  }
}

/// Builds inline LaTeX widgets.
class InlineLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Math.tex(
      element.textContent,
      textStyle: preferredStyle,
      onErrorFallback: (err) => Text(
        '\$${element.textContent}\$',
        style: preferredStyle?.copyWith(
          fontStyle: FontStyle.italic,
          color: Colors.orange,
        ),
      ),
    );
  }
}

/// Builds display (block) LaTeX widgets, centered with horizontal scroll.
class BlockLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            element.textContent,
            textStyle: preferredStyle?.copyWith(
              fontSize: (preferredStyle.fontSize ?? 16) * 1.2,
            ),
            onErrorFallback: (err) => Text(
              '\$\$${element.textContent}\$\$',
              style: preferredStyle?.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.orange,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
