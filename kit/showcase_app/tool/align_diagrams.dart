/// Mechanically re-aligns ASCII relationship diagrams in `///` doc comments.
///
/// Usage: dart run tool/align_diagrams.dart [directory]
/// Default directory: lib (relative to kit/showcase_app).
///
/// Reads every .dart file, finds diagram blocks in `///` doc comments,
/// re-aligns tier centers to the middle-tier anchor, regenerates arrows
/// and the rail, and writes back if changed.
library;

import 'dart:io';

void main(List<String> args) {
  final dir = args.isNotEmpty ? args.first : 'lib';
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    stderr.writeln('Directory not found: $dir');
    exit(1);
  }

  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final modified = <String>[];
  for (final file in files) {
    if (_processFile(file)) modified.add(file.path);
  }

  if (modified.isEmpty) {
    print('No diagrams needed alignment.');
  } else {
    for (final path in modified) {
      print('  aligned: $path');
    }
    print('\n${modified.length} file(s) aligned.');
  }
  exit(0);
}

// ── Prefix helpers ──────────────────────────────────────────────────────

bool _isDocLine(String line) => line.startsWith('///');

String _stripPrefix(String line) {
  if (!line.startsWith('///')) return line;
  var s = line.substring(3);
  if (s.startsWith(' ')) s = s.substring(1);
  return s;
}

String _addPrefix(String content) =>
    content.isEmpty ? '///' : '/// $content';

bool _isDiagramLine(String content) =>
    content.contains('┌') ||
    content.contains('└') ||
    content.contains('│') ||
    content.contains('─') ||
    content.contains('▼') ||
    content.contains('▲') ||
    content.contains('═') ||
    content.contains('ACT') ||
    content.contains('STRM') ||
    RegExp(r'\[\d').hasMatch(content);

// ── Data types ──────────────────────────────────────────────────────────

class _Box {
  final int start, end;
  final String label;
  _Box(this.start, this.end, this.label);
  double get center => (start + end) / 2;
  int get width => end - start + 1;
}

class _Tier {
  final List<_Box> boxes;
  _Tier(this.boxes);
  double get center {
    if (boxes.length == 1) return boxes.first.center;
    return (boxes.first.start + boxes.last.end) / 2;
  }

  int get leftEdge => boxes.first.start;
  int get rightEdge => boxes.last.end;

  _Tier shifted(int s) =>
      _Tier(boxes.map((b) => _Box(b.start + s, b.end + s, b.label)).toList());
}

class _Gap {
  final List<String> lines;
  _Gap(this.lines);

  bool get hasArrow => lines.any(
      (l) => l.contains('ACT') || l.contains('STRM') || l.contains('▼') || l.contains('▲'));
  bool get hasAct => lines.any((l) => l.contains('ACT'));
  bool get hasStrm => lines.any((l) => l.contains('STRM'));
  bool get hasRange =>
      lines.any((l) => RegExp(r'\[\d+(?:-\d+)?\]').hasMatch(l));

  List<String> get rangeTexts {
    for (final l in lines) {
      final ms = RegExp(r'\[\d+(?:-\d+)?\]').allMatches(l);
      if (ms.isNotEmpty) return ms.map((m) => m.group(0)!).toList();
    }
    return [];
  }
}

// ── File processing ────────────────────────────────────────────────────

bool _processFile(File file) {
  final original = file.readAsStringSync();
  final result = _processSource(original, file.path);
  if (result != null) {
    file.writeAsStringSync(result);
    return true;
  }
  return false;
}

String? _processSource(String src, String filePath) {
  final lines = src.split('\n');
  var changed = false;

  int i = 0;
  while (i < lines.length) {
    if (_isDocLine(lines[i]) && lines[i].contains('┌')) {
      final blockStart = i;
      var blockEnd = i + 1;
      while (blockEnd < lines.length) {
        if (!_isDocLine(lines[blockEnd])) break;
        if (!_isDiagramLine(_stripPrefix(lines[blockEnd]))) break;
        blockEnd++;
      }

      final contentLines =
          lines.sublist(blockStart, blockEnd).map(_stripPrefix).toList();
      final aligned = _realignDiagram(contentLines, filePath);
      if (aligned != null) {
        for (int j = 0; j < aligned.length; j++) {
          final newLine = _addPrefix(aligned[j]);
          if (lines[blockStart + j] != newLine) changed = true;
          lines[blockStart + j] = newLine;
        }
      }
      i = blockEnd;
    } else {
      i++;
    }
  }

  return changed ? lines.join('\n') : null;
}

// ── Diagram parsing + re-alignment ──────────────────────────────────────

List<_Box> _parseBoxes(String topLine, String labelLine) {
  final maxLen = topLine.length > labelLine.length
      ? topLine.length
      : labelLine.length;
  final top = topLine.padRight(maxLen);
  final label = labelLine.padRight(maxLen);
  final lefts = <int>[];
  final rights = <int>[];
  for (int c = 0; c < top.length; c++) {
    if (top[c] == '┌') lefts.add(c);
    if (top[c] == '┐') rights.add(c);
  }
  final boxes = <_Box>[];
  for (int i = 0; i < lefts.length && i < rights.length; i++) {
    final labelText = label.substring(lefts[i] + 1, rights[i]).trim();
    boxes.add(_Box(lefts[i], rights[i], labelText));
  }
  return boxes;
}

List<String>? _realignDiagram(List<String> contentLines, String filePath) {
  // Find tier start indices (lines containing ┌).
  final tierStarts = <int>[];
  for (int i = 0; i < contentLines.length; i++) {
    if (contentLines[i].contains('┌')) tierStarts.add(i);
  }
  if (tierStarts.isEmpty) return null;

  // Parse tiers.
  final tiers = <_Tier>[];
  for (final start in tierStarts) {
    if (start + 2 >= contentLines.length) {
      stderr.writeln('  warning: $filePath — truncated tier, skipping');
      return null;
    }
    final labelLine = contentLines[start + 1];
    if (!labelLine.contains('│')) {
      stderr.writeln('  warning: $filePath — expected │ on label line, skipping');
      return null;
    }
    final boxes = _parseBoxes(contentLines[start], labelLine);
    if (boxes.isEmpty) {
      stderr.writeln('  warning: $filePath — no boxes parsed, skipping');
      return null;
    }
    tiers.add(_Tier(boxes));
  }

  // Parse gaps between tiers.
  final gaps = <_Gap>[];
  for (int t = 0; t < tierStarts.length - 1; t++) {
    final gs = tierStarts[t] + 3;
    final ge = tierStarts[t + 1];
    gaps.add(_Gap(contentLines.sublist(gs, ge)));
  }

  // Rail detection.
  final afterLast = tierStarts.last + 3;
  final hasRail = afterLast < contentLines.length &&
      contentLines[afterLast].contains('════');

  // Compute anchor and shifts.
  final anchorIdx = tiers.length ~/ 2;
  final anchorCenter = tiers[anchorIdx].center;

  final shiftedTiers = <_Tier>[];
  for (final tier in tiers) {
    var shift = (anchorCenter - tier.center).truncate();
    final minStart =
        tier.boxes.map((b) => b.start).reduce((a, b) => a < b ? a : b);
    if (shift < 0 && minStart + shift < 0) shift = -minStart;
    shiftedTiers.add(tier.shifted(shift));
  }

  // Re-assemble.
  final result = <String>[];
  for (int t = 0; t < shiftedTiers.length; t++) {
    final tier = shiftedTiers[t];
    result.add(_buildMultiBoxLine(tier.boxes, _buildTop));
    result.add(_buildMultiBoxLine(tier.boxes, _buildLabel));
    result.add(_buildMultiBoxLine(tier.boxes, _buildBottom));

    if (t < gaps.length) {
      final gap = gaps[t];
      if (gap.hasArrow || gap.hasRange) {
        final upper = shiftedTiers[t];
        final lower = shiftedTiers[t + 1];
        final maxLeft = upper.leftEdge > lower.leftEdge
            ? upper.leftEdge
            : lower.leftEdge;
        final minRight = upper.rightEdge < lower.rightEdge
            ? upper.rightEdge
            : lower.rightEdge;
        int actStart;
        int strmEnd;
        if (maxLeft <= minRight) {
          actStart = maxLeft;
          strmEnd = minRight;
        } else {
          actStart = (anchorCenter - 5).round();
          strmEnd = (anchorCenter + 5).round();
        }

        if (gap.hasArrow) {
          result.add(
              _buildArrowLine(actStart, strmEnd, gap.hasAct, gap.hasStrm));
        }
        if (gap.hasRange) {
          result.add(_buildRangeLine(actStart, strmEnd, gap.rangeTexts));
        }
      }
    }
  }

  if (hasRail) {
    final start = (anchorCenter - 13).round();
    result.add('${' ' * (start < 0 ? 0 : start)}════════ abxAction ════════');
  }

  return result;
}

// ── Builders ────────────────────────────────────────────────────────────

String _buildTop(_Box b) => '┌${'─' * (b.width - 2)}┐';

String _buildLabel(_Box b) {
  final interior = b.width - 2;
  final pad = interior - b.label.length;
  final left = pad ~/ 2;
  final right = pad - left;
  return '│${' ' * left}${b.label}${' ' * right}│';
}

String _buildBottom(_Box b) => '└${'─' * (b.width - 2)}┘';

String _buildMultiBoxLine(
    List<_Box> boxes, String Function(_Box) builder) {
  final sb = StringBuffer();
  for (int i = 0; i < boxes.length; i++) {
    if (i == 0) {
      sb.write(' ' * boxes[i].start);
    } else {
      sb.write(' ' * (boxes[i].start - boxes[i - 1].end - 1));
    }
    sb.write(builder(boxes[i]));
  }
  return sb.toString();
}

String _buildArrowLine(
    int actStart, int strmEnd, bool hasAct, bool hasStrm) {
  final strmStart = strmEnd - 6;
  final sb = StringBuffer();
  if (hasAct) {
    sb.write(' ' * actStart);
    sb.write('ACT ▼');
  }
  if (hasAct && hasStrm) {
    final actEnd = actStart + 5; // exclusive end of "ACT ▼"
    final gap = strmStart - actEnd;
    sb.write(' ' * (gap < 1 ? 1 : gap));
  }
  if (hasStrm) {
    if (!hasAct) sb.write(' ' * strmStart);
    sb.write('▲ STRM');
  }
  return sb.toString();
}

String _buildRangeLine(int actStart, int strmEnd, List<String> ranges) {
  final strmStart = strmEnd - 6;
  final sb = StringBuffer();
  if (ranges.isNotEmpty) {
    sb.write(' ' * actStart);
    sb.write(ranges[0]);
  }
  if (ranges.length > 1) {
    final firstEnd = actStart + ranges[0].length;
    final gap = strmStart - firstEnd;
    sb.write(' ' * (gap < 1 ? 1 : gap));
    sb.write(ranges[1]);
  }
  return sb.toString();
}
