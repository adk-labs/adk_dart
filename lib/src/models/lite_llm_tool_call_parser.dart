part of 'lite_llm.dart';

Map<String, Object?>? _buildToolCallFromJsonDict(
  Object? candidate, {
  required int index,
}) {
  if (candidate is! Map) {
    return null;
  }
  final Object? nameRaw = candidate['name'];
  final Object? argsRaw = candidate['arguments'];
  if (nameRaw is! String || argsRaw == null) {
    return null;
  }
  String argumentsPayload;
  if (argsRaw is String) {
    argumentsPayload = argsRaw;
  } else {
    try {
      argumentsPayload = jsonEncode(argsRaw);
    } on StackOverflowError {
      return null;
    } catch (_) {
      try {
        argumentsPayload = '$argsRaw';
      } on StackOverflowError {
        return null;
      }
    }
  }
  final Object? rawId = candidate['id'];
  final String callId =
      (rawId != null && '$rawId'.isNotEmpty)
          ? '$rawId'
          : 'adk_tool_call_${newUuid().replaceAll('-', '')}';
  final Object? rawIndex = candidate['index'];
  final int resolvedIndex = rawIndex is int ? rawIndex : index;
  return <String, Object?>{
    'type': 'function',
    'id': callId,
    'index': resolvedIndex,
    'function': <String, Object?>{
      'name': nameRaw,
      'arguments': argumentsPayload,
    },
  };
}

(Object?, int)? _rawJsonDecode(String text, int start) {
  if (start < 0 || start >= text.length) {
    return null;
  }
  final String first = text[start];
  if (first != '{' && first != '[') {
    return null;
  }
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  int end = -1;
  for (int i = start; i < text.length; i += 1) {
    final String ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{' || ch == '[') {
      depth += 1;
    } else if (ch == '}' || ch == ']') {
      depth -= 1;
      if (depth == 0) {
        end = i + 1;
        break;
      }
      if (depth < 0) {
        return null;
      }
    }
  }
  if (end == -1) {
    return null;
  }
  final String slice = text.substring(start, end);
  if (_hugeIntLiteralPattern.hasMatch(slice)) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(slice);
    return (decoded, end);
  } on StackOverflowError {
    return null;
  } catch (_) {
    return null;
  }
}

String? _extractJsonFromDeepseekArgs(String argsText) {
  if (argsText.isEmpty) {
    return null;
  }
  final RegExpMatch? fenceMatch = _dsFenceArgsRe.firstMatch(argsText);
  if (fenceMatch != null) {
    final String candidate = (fenceMatch.group(1) ?? '').trim();
    if (!_hugeIntLiteralPattern.hasMatch(candidate)) {
      try {
        jsonDecode(candidate);
        return candidate;
      } on StackOverflowError {
        // Fall through.
      } catch (_) {}
    }
  }
  final int openBrace = argsText.indexOf('{');
  if (openBrace == -1) {
    return null;
  }
  final (Object? decoded, int _)? raw = _rawJsonDecode(argsText, openBrace);
  if (raw == null) {
    return null;
  }
  try {
    return jsonEncode(raw.$1);
  } on StackOverflowError {
    return null;
  } catch (_) {
    return null;
  }
}

(List<Map<String, Object?>>, String?) _parseDeepseekToolCallsFromText(
  String textBlock, {
  int startIndex = 0,
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  if (textBlock.isEmpty) {
    return (toolCalls, null);
  }
  if (!textBlock.contains(_dsTcallsBegin) &&
      !textBlock.contains(_dsTcallBegin)) {
    return (toolCalls, null);
  }
  final List<String> remainderParts = <String>[];
  int cursor = 0;
  while (true) {
    final int callsIdx = textBlock.indexOf(_dsTcallsBegin, cursor);
    final int callIdx = textBlock.indexOf(_dsTcallBegin, cursor);
    if (callsIdx == -1 && callIdx == -1) {
      remainderParts.add(textBlock.substring(cursor));
      break;
    }
    final int beginIdx;
    final bool inWrappedBlock;
    if (callsIdx != -1 && (callIdx == -1 || callsIdx < callIdx)) {
      beginIdx = callsIdx;
      inWrappedBlock = true;
    } else {
      beginIdx = callIdx;
      inWrappedBlock = false;
    }
    if (beginIdx > cursor) {
      remainderParts.add(textBlock.substring(cursor, beginIdx));
    }
    String block;
    if (inWrappedBlock) {
      final int endIdx = textBlock.indexOf(
        _dsTcallsEnd,
        beginIdx + _dsTcallsBegin.length,
      );
      if (endIdx == -1) {
        remainderParts.add(textBlock.substring(beginIdx));
        break;
      }
      block = textBlock.substring(beginIdx + _dsTcallsBegin.length, endIdx);
      cursor = endIdx + _dsTcallsEnd.length;
    } else {
      final int endIdx = textBlock.indexOf(
        _dsTcallEnd,
        beginIdx + _dsTcallBegin.length,
      );
      if (endIdx == -1) {
        remainderParts.add(textBlock.substring(beginIdx));
        break;
      }
      block = textBlock.substring(beginIdx, endIdx + _dsTcallEnd.length);
      cursor = endIdx + _dsTcallEnd.length;
    }
    for (final RegExpMatch match in _dsToolCallRe.allMatches(block)) {
      final String funcName = (match.group(1) ?? '').trim();
      final String argsRaw = (match.group(2) ?? '').trim();
      final String? argsJson = _extractJsonFromDeepseekArgs(argsRaw);
      if (funcName.isEmpty || argsJson == null) {
        continue;
      }
      final Map<String, Object?>? toolCall = _buildToolCallFromJsonDict(
        <String, Object?>{'name': funcName, 'arguments': argsJson},
        index: startIndex + toolCalls.length,
      );
      if (toolCall != null) {
        toolCalls.add(toolCall);
      }
    }
  }
  final String remainder = remainderParts
      .where((String p) => p.isNotEmpty)
      .join()
      .trim();
  return (toolCalls, remainder.isEmpty ? null : remainder);
}

int _skipWhitespace(String text, int pos) {
  int i = pos;
  while (i < text.length && text[i].trim().isEmpty) {
    i += 1;
  }
  return i;
}

int? _spanEndAt(List<(int, int)> spans, int pos) {
  int lo = 0;
  int hi = spans.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (spans[mid].$1 <= pos) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final int idx = lo - 1;
  if (idx >= 0 && pos < spans[idx].$2) {
    return spans[idx].$2;
  }
  return null;
}

(List<Map<String, Object?>>, int) _decodeToolCalls(
  String text,
  int pos, {
  int startIndex = 0,
  List<(int, int)> indentedCode = const <(int, int)>[],
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  int cursor = pos;
  while (cursor < text.length &&
      (text.startsWith('{', cursor) || text.startsWith('[', cursor)) &&
      _spanEndAt(indentedCode, cursor) == null) {
    final (Object? candidate, int end)? decoded = _rawJsonDecode(text, cursor);
    if (decoded == null) {
      break;
    }
    final List<Object?> candidates = decoded.$1 is List
        ? List<Object?>.from(decoded.$1 as List)
        : <Object?>[decoded.$1];
    final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
    for (int i = 0; i < candidates.length; i += 1) {
      final Map<String, Object?>? call = _buildToolCallFromJsonDict(
        candidates[i],
        index: startIndex + toolCalls.length + i,
      );
      if (call != null) {
        calls.add(call);
      }
    }
    if (calls.isEmpty || calls.length != candidates.length) {
      break;
    }
    toolCalls.addAll(calls);
    cursor = _skipWhitespace(text, decoded.$2);
  }
  return (toolCalls, cursor);
}

(List<Map<String, Object?>>, int)? _matchToolCallTag(
  String text,
  int pos, {
  int startIndex = 0,
}) {
  int start = _skipWhitespace(text, pos + _toolCallOpen.length);
  final Match? fence = _tagPayloadFenceRe.matchAsPrefix(text, start);
  if (fence != null) {
    start = _skipWhitespace(text, fence.end);
  }
  final (List<Map<String, Object?>> toolCalls, int decodedEnd) =
      _decodeToolCalls(text, start, startIndex: startIndex);
  int end = decodedEnd;
  if (fence != null) {
    final String fenceMark = fence.group(1)!;
    if (!text.startsWith(fenceMark, end)) {
      return null;
    }
    end = _skipWhitespace(text, end + fenceMark.length);
  }
  if (toolCalls.isEmpty || !text.startsWith(_toolCallClose, end)) {
    return null;
  }
  return (toolCalls, end + _toolCallClose.length);
}

int? _callBlockEnd(String text, int start, String token) {
  if (token == _toolCallOpen) {
    final (List<Map<String, Object?>>, int)? tag = _matchToolCallTag(
      text,
      start,
    );
    return tag?.$2;
  }
  final String endToken = _callBlockEnds[token]!;
  final int end = text.indexOf(endToken, start + token.length);
  if (end == -1) {
    return null;
  }
  final int inner = start + token.length;
  final int nextSame = text.indexOf(token, inner);
  if (nextSame != -1 && nextSame < end) {
    return null;
  }
  final int nextOuter = text.indexOf(_dsTcallsBegin, inner);
  if (nextOuter != -1 && nextOuter < end) {
    return null;
  }
  final int blockEnd = end + endToken.length;
  final (List<Map<String, Object?>> dsCalls, String? dsRemainder) =
      _parseDeepseekToolCallsFromText(text.substring(start, blockEnd));
  return dsCalls.isNotEmpty && dsRemainder == null ? blockEnd : null;
}

RegExpMatch? _searchRe(RegExp re, String text, int start, [int? end]) {
  final int limit = end ?? text.length;
  if (start >= limit) {
    return null;
  }
  for (final RegExpMatch m in re.allMatches(text, start)) {
    if (m.start >= limit) {
      return null;
    }
    if (m.end <= limit) {
      return m;
    }
  }
  return null;
}

int? _findThinkClose(String text, int pos) {
  int scanPos = pos;
  while (true) {
    final int close = text.indexOf('</think>', scanPos);
    if (close == -1) {
      return null;
    }
    bool jumpedPastClose = false;
    while (true) {
      final RegExpMatch? call = _searchRe(_callBlockRe, text, scanPos, close);
      if (call == null) {
        break;
      }
      final int? blockEnd = _callBlockEnd(text, call.start, call.group(0)!);
      scanPos = blockEnd ?? call.end;
      if (blockEnd != null && blockEnd > close) {
        jumpedPastClose = true;
        break;
      }
    }
    if (!jumpedPastClose) {
      return close + '</think>'.length;
    }
  }
}

List<(int, int)> _callBlockSpans(String text) {
  final List<(int, int)> spans = <(int, int)>[];
  int pos = 0;
  while (pos < text.length) {
    final RegExpMatch? call = _searchRe(_callBlockRe, text, pos);
    if (call == null) {
      break;
    }
    final int? blockEnd = _callBlockEnd(text, call.start, call.group(0)!);
    if (blockEnd != null) {
      spans.add((call.start, blockEnd));
    }
    pos = blockEnd ?? call.end;
  }
  return spans;
}

int _rfindNewline(String text, int start, int end) {
  for (int i = math.min(end, text.length) - 1; i >= start; i -= 1) {
    if (text.codeUnitAt(i) == 0x0A) {
      return i;
    }
  }
  return -1;
}

List<(int, int)> _indentedCodeSpans(String text, List<(int, int)> opaque) {
  final List<String> parts = <String>[];
  int prev = 0;
  for (final (int rawStart, int end) in opaque) {
    if (end <= prev) {
      continue;
    }
    final int start = math.max(rawStart, prev);
    parts.add(text.substring(prev, start));
    final int lineStart = _rfindNewline(text, 0, start) + 1;
    final int closeLineStart = _rfindNewline(text, start, end) + 1;
    if (text.substring(start, end).contains('\n') &&
        (_codeIndentRe.matchAsPrefix(text, lineStart) == null ||
            (text.startsWith('<think>', start) &&
                _codeIndentRe.matchAsPrefix(text, closeLineStart) == null))) {
      parts.add('x\n${'x' * math.max(0, end - start - 2)}');
    } else {
      parts.add('x' * (end - start));
    }
    prev = end;
  }
  parts.add(text.substring(prev));
  final String masked = parts.join();
  final List<(int, int)> result = <(int, int)>[];
  for (final RegExpMatch m in _indentedCodeRe.allMatches(masked)) {
    final String? g1 = m.group(1);
    if (g1 != null) {
      final int g1End = m.end;
      final int g1Start = g1End - g1.length;
      result.add((g1Start, g1End));
    }
  }
  return result;
}

int _openInlineTicks(int initialTicks, String line) {
  int ticks = initialTicks;
  for (final RegExpMatch run in _backtickRunRe.allMatches(line)) {
    final String group = run.group(0)!;
    if (ticks != 0) {
      if (group.length == ticks) {
        ticks = 0;
      }
      continue;
    }
    int escapeStart = run.start;
    while (escapeStart > 0 && line[escapeStart - 1] == r'\') {
      escapeStart -= 1;
    }
    ticks = group.length - ((run.start - escapeStart) % 2);
  }
  return ticks;
}

List<(int, int)> _sortSpans(List<(int, int)> spans) {
  final List<(int, int)> copy = List<(int, int)>.from(spans);
  copy.sort(((int, int) a, (int, int) b) {
    final int cmp = a.$1.compareTo(b.$1);
    return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
  });
  return copy;
}

List<(int, int)> _markdownCodeSpans(
  String text, {
  int startPos = 0,
  List<(int, int)>? opaque,
}) {
  if (opaque == null) {
    final List<(int, int)> prefix = startPos > 0
        ? <(int, int)>[(0, startPos)]
        : const <(int, int)>[];
    final List<(int, int)> callBlocks = _sortSpans(<(int, int)>[
      ...prefix,
      ..._callBlockSpans(text),
    ]);
    final List<(int, int)> firstPass = _markdownCodeSpans(
      text,
      startPos: startPos,
      opaque: callBlocks,
    );
    final List<(int, int)> thinkBlocks = <(int, int)>[
      for (final (int s, int e) in firstPass)
        if (text.startsWith('<think>', s)) (s, e),
    ];
    if (thinkBlocks.isEmpty) {
      return firstPass;
    }
    return _markdownCodeSpans(
      text,
      startPos: startPos,
      opaque: _sortSpans(<(int, int)>[...callBlocks, ...thinkBlocks]),
    );
  }

  final List<(int, int)> indented = <(int, int)>[
    for (final (int s, int e) in _indentedCodeSpans(text, opaque))
      if (e > startPos) (s, e),
  ];
  final List<(int, int)> spans = <(int, int)>[];
  int pos = startPos;
  int paragraphEndPos = -1;
  bool thinkUnclosed = false;
  final Map<String, int> unclosedFenceLen = <String, int>{};

  while (pos < text.length) {
    final RegExpMatch? match = _searchRe(_codeScanRe, text, pos);
    if (match == null) {
      break;
    }
    int start = match.start;
    String run = match.group(0)!;
    pos = match.end;
    int? end;

    if (run == '<think>') {
      final int? thinkClose = thinkUnclosed ? null : _findThinkClose(text, pos);
      if (thinkClose == null) {
        thinkUnclosed = true;
        continue;
      }
      spans.add((start, thinkClose));
      pos = thinkClose;
      continue;
    }

    final int? blockEnd = _spanEndAt(indented, start);
    if (blockEnd != null) {
      spans.add((start, blockEnd));
      pos = blockEnd;
      continue;
    }

    if (_callBlockEnds.containsKey(run)) {
      pos = _callBlockEnd(text, start, run) ?? pos;
      continue;
    }

    final int lineStart = _rfindNewline(text, 0, start) + 1;
    final Match? fence = _fenceOpenRe.matchAsPrefix(text, lineStart);
    if (fence != null &&
        fence.group(1) != null &&
        lineStart + fence.group(0)!.indexOf(fence.group(1)!) == start) {
      final String fenceChar = run[0];
      final int minUnclosed = unclosedFenceLen[fenceChar] ?? (run.length + 1);
      if (run.length >= minUnclosed) {
        continue;
      }
      int scanPos = pos;
      while (scanPos < text.length) {
        final RegExpMatch? close = _searchRe(_fenceCloseRe, text, scanPos);
        if (close == null) {
          break;
        }
        bool jumpedPastClose = false;
        while (true) {
          final RegExpMatch? call = _searchRe(
            _callBlockRe,
            text,
            scanPos,
            close.start,
          );
          if (call == null) {
            break;
          }
          final int? callEnd = _callBlockEnd(text, call.start, call.group(0)!);
          scanPos = callEnd ?? call.end;
          if (callEnd != null && callEnd > close.start) {
            jumpedPastClose = true;
            break;
          }
        }
        if (!jumpedPastClose) {
          final String closeGroup = close.group(1)!;
          if (closeGroup[0] == fenceChar && closeGroup.length >= run.length) {
            end = close.end;
            break;
          }
          scanPos = close.end;
        }
      }
      if (end == null) {
        unclosedFenceLen[fenceChar] = run.length;
      }
    } else if (run.startsWith('`')) {
      int escapeStart = start;
      while (escapeStart > 0 && text[escapeStart - 1] == r'\') {
        escapeStart -= 1;
      }
      if ((start - escapeStart) % 2 == 1) {
        start += 1;
        run = run.substring(1);
        if (run.isEmpty) {
          continue;
        }
      }
      if (pos > paragraphEndPos) {
        final RegExpMatch? paragraphEnd = _searchRe(
          _paragraphEndRe,
          text,
          pos,
        );
        paragraphEndPos = paragraphEnd?.start ?? text.length;
      }
      int scanPos = pos;
      while (scanPos < paragraphEndPos) {
        final RegExpMatch? inner = _searchRe(
          _inlineCodeScanRe,
          text,
          scanPos,
          paragraphEndPos,
        );
        if (inner == null) {
          break;
        }
        final String innerGroup = inner.group(0)!;
        if (_callBlockEnds.containsKey(innerGroup)) {
          scanPos = _callBlockEnd(text, inner.start, innerGroup) ?? inner.end;
          if (paragraphEndPos < scanPos) {
            final RegExpMatch? paragraphEnd = _searchRe(
              _paragraphEndRe,
              text,
              scanPos,
            );
            paragraphEndPos = paragraphEnd?.start ?? text.length;
          }
        } else if (innerGroup == run) {
          end = inner.end;
          break;
        } else {
          scanPos = inner.end;
        }
      }
    }
    if (end != null) {
      spans.add((start, end));
      pos = end;
    }
  }
  return spans;
}

String _nextFence(String fence, String line) {
  if (fence.isEmpty) {
    final Match? match = _fenceOpenRe.matchAsPrefix(line);
    return match?.group(1) ?? '';
  }
  final RegExpMatch? close = _fenceCloseRe.firstMatch(line);
  if (close != null &&
      close.start == 0 &&
      close.end == line.length &&
      close.group(1)![0] == fence[0] &&
      close.group(1)!.length >= fence.length) {
    return '';
  }
  return fence;
}

class _StreamTextTracker {
  _StreamTextTracker() {
    reset();
  }

  bool hasNonWhitespace = false;
  String _fence = '';
  final List<String> _lineParts = <String>[];
  String _lineHead = '';
  bool _lineHasText = false;
  int _lineStartTicks = 0;
  bool _paragraphHasCodeMark = false;
  bool _indentedCodeMayFollow = true;
  bool inThink = false;
  final List<String> _thinkParts = <String>[];
  String _thinkTail = '';
  final List<int> _maybeThinkOffsets = <int>[];
  bool _maybeInThink = false;

  void reset() {
    hasNonWhitespace = false;
    _fence = '';
    _lineParts.clear();
    _lineHead = '';
    _lineHasText = false;
    _lineStartTicks = 0;
    _paragraphHasCodeMark = false;
    _indentedCodeMayFollow = true;
    inThink = false;
    _thinkParts.clear();
    _thinkTail = '';
    _maybeThinkOffsets.clear();
    _maybeInThink = false;
  }

  bool get inCode {
    if (_fence.isNotEmpty || _paragraphHasCodeMark) {
      return true;
    }
    return _indentedCodeMayFollow &&
        _lineHead.isNotEmpty &&
        (_lineHead.trim().isEmpty ||
            _codeIndentRe.matchAsPrefix(_lineHead) != null);
  }

  bool inThinkFor(String text) {
    return inThink ||
        _maybeInThink ||
        _thinkTagRe.hasMatch('$_thinkTail$text');
  }

  bool completesLine(String text) {
    return _lineHasText && text.contains('\n');
  }

  void feed(String text) {
    if (text.trim().isNotEmpty) {
      hasNonWhitespace = true;
    }
    final String window = '$_thinkTail$text';
    final int offset = _thinkTail.length;
    int pos = 0;
    for (final RegExpMatch tag in _thinkTagRe.allMatches(window)) {
      if (tag.end <= offset) {
        continue;
      }
      final int tagStart = math.max(tag.start - offset, pos);
      final int tagEnd = tag.end - offset;
      if (inThink) {
        _thinkParts.add(text.substring(pos, tagStart));
        if (tag.group(0) == '</think>') {
          _closeThink();
        }
        if (inThink) {
          _thinkParts.add(text.substring(tagStart, tagEnd));
        }
      } else {
        _feedMarkdown(text.substring(pos, tagStart));
        final String line = _lineParts.join();
        if (tag.group(0) == '<think>' && _fence.isEmpty) {
          if (_openInlineTicks(_lineStartTicks, line) != 0) {
            _maybeThinkOffsets.add(
              line.length + math.min(0, tag.start - offset),
            );
          } else {
            inThink = true;
            _thinkParts.clear();
            _feedMarkdown('<think>');
          }
        }
        if (!inThink) {
          _feedMarkdown(text.substring(tagStart, tagEnd));
        }
      }
      pos = tagEnd;
    }
    if (inThink) {
      _thinkParts.add(text.substring(pos));
    } else {
      _feedMarkdown(text.substring(pos));
    }
    const int tailKeep = '</think'.length;
    _thinkTail = window.length <= tailKeep
        ? window
        : window.substring(window.length - tailKeep);
  }

  void _closeThink() {
    final String body = _thinkParts.join();
    int scanPos = 0;
    while (scanPos < body.length) {
      final RegExpMatch? call = _searchRe(_callBlockRe, body, scanPos);
      if (call == null) {
        break;
      }
      final String callGroup = call.group(0)!;
      final int? blockEnd = _callBlockEnd(body, call.start, callGroup);
      if (blockEnd == null &&
          body.indexOf(_callBlockEnds[callGroup]!, call.end) == -1) {
        return;
      }
      scanPos = blockEnd ?? call.end;
    }
    inThink = false;
    if (!body.contains('\n')) {
      _feedMarkdown('</think>');
    } else if (_codeIndentRe.matchAsPrefix(_lineParts.join()) != null &&
        _codeIndentRe.matchAsPrefix(body, body.lastIndexOf('\n') + 1) != null) {
      _feedMarkdown('\n    </think>');
    } else {
      _feedMarkdown('\n</think>');
    }
  }

  void _feedMarkdown(String text) {
    final List<String> split = text.split('\n');
    final String tail = split.last;
    for (int i = 0; i < split.length - 1; i += 1) {
      _lineParts.add(split[i]);
      final String line = _lineParts.join();
      _lineParts.clear();
      _lineHead = '';
      _lineHasText = false;
      if (_maybeThinkOffsets.isNotEmpty) {
        final int textStart = line.length - line.trimLeft().length;
        final List<(int, int)> spans = _markdownCodeSpans(
          line.substring(textStart),
        );
        final bool allInsideCode = _maybeThinkOffsets.every(
          (int tagPos) => spans.any(
            ((int, int) span) =>
                span.$1 < tagPos - textStart && tagPos - textStart < span.$2,
          ),
        );
        if (!allInsideCode) {
          _maybeInThink = true;
        }
        _maybeThinkOffsets.clear();
      }
      final String fence = _nextFence(_fence, line);
      if (fence.isNotEmpty || _fence.isNotEmpty || line.trim().isEmpty) {
        _paragraphHasCodeMark = false;
        _lineStartTicks = 0;
      } else {
        if (line.contains('`') || line.contains('~')) {
          _paragraphHasCodeMark = true;
        }
        _lineStartTicks = _openInlineTicks(_lineStartTicks, line);
      }
      if (fence.isNotEmpty || _fence.isNotEmpty) {
        _indentedCodeMayFollow = fence.isEmpty;
      } else if (line.trim().isNotEmpty) {
        _indentedCodeMayFollow =
            _atxHeadingRe.matchAsPrefix(line) != null ||
            (_indentedCodeMayFollow &&
                _codeIndentRe.matchAsPrefix(line) != null);
      } else {
        _indentedCodeMayFollow = true;
      }
      _fence = fence;
    }
    _lineParts.add(tail);
    final String combinedHead =
        '$_lineHead${tail.length > 4 ? tail.substring(0, 4) : tail}';
    _lineHead = combinedHead.length > 4
        ? combinedHead.substring(0, 4)
        : combinedHead;
    _lineHasText = _lineHasText || tail.trim().isNotEmpty;
    if (tail.contains('`') || tail.contains('~')) {
      _paragraphHasCodeMark = true;
    }
  }
}

/// Extracts inline JSON tool calls from LiteLLM text responses while ignoring
/// tool calls quoted inside Markdown code spans/fences, `<think>` blocks, or
/// bare JSON following prose.
(List<Map<String, Object?>>, String?) parseToolCallsFromText(
  String? textBlock, {
  bool allowBareJson = true,
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  if (textBlock == null || textBlock.isEmpty) {
    return (toolCalls, null);
  }

  List<(int, int)>? codeSpans;
  int codeStart = 0;
  int pos = _skipWhitespace(textBlock, 0);
  final List<(int, int)> thinkBlocks = <(int, int)>[];
  while (textBlock.startsWith('<think>', pos)) {
    final int? thinkClose = _findThinkClose(
      textBlock,
      pos + '<think>'.length,
    );
    if (thinkClose == null) {
      break;
    }
    thinkBlocks.add((pos, thinkClose));
    pos = _skipWhitespace(textBlock, thinkClose);
  }
  final Match? prefix = _leadingCallPrefixRe.matchAsPrefix(textBlock, pos);
  int runPos = allowBareJson ? (prefix?.end ?? pos) : -1;
  final List<(int, int)> callBlocks = allowBareJson
      ? _callBlockSpans(textBlock)
      : const <(int, int)>[];
  List<(int, int)> indentedCode = allowBareJson
      ? _indentedCodeSpans(
          textBlock,
          _sortSpans(<(int, int)>[...thinkBlocks, ...callBlocks]),
        )
      : const <(int, int)>[];
  final List<String> remainderParts = <String>[];
  int cursor = 0;

  while (true) {
    if (pos == runPos) {
      final (List<Map<String, Object?>> jsonCalls, int end) = _decodeToolCalls(
        textBlock,
        pos,
        startIndex: toolCalls.length,
        indentedCode: indentedCode,
      );
      if (jsonCalls.isNotEmpty) {
        final int jsonEnd = textBlock.substring(0, end).trimRight().length;
        final bool multiLine = textBlock.substring(pos, jsonEnd).contains('\n');
        if (multiLine && _spanEndAt(indentedCode, end) != null) {
          indentedCode = _indentedCodeSpans(
            textBlock,
            _sortSpans(<(int, int)>[(0, jsonEnd), ...callBlocks]),
          );
        }
        if (multiLine || _searchRe(_codeScanRe, textBlock, pos, jsonEnd) != null) {
          codeStart = jsonEnd;
        }
        remainderParts.add(textBlock.substring(cursor, pos));
        toolCalls.addAll(jsonCalls);
        cursor = pos = runPos = end;
        continue;
      }
    }
    final int searchEnd = pos < runPos ? runPos : textBlock.length;
    final RegExpMatch? match = _searchRe(_callBlockRe, textBlock, pos, searchEnd);
    if (match == null) {
      if (pos >= runPos) {
        break;
      }
      pos = runPos;
      continue;
    }
    final int start = match.start;
    final String token = match.group(0)!;
    final int? spanEnd;
    if (start == runPos) {
      spanEnd = _spanEndAt(indentedCode, start);
    } else {
      codeSpans ??= _markdownCodeSpans(textBlock, startPos: codeStart);
      spanEnd = _spanEndAt(codeSpans, start);
    }
    if (spanEnd != null) {
      pos = spanEnd;
      continue;
    }
    (List<Map<String, Object?>>, int)? found;
    if (token == _toolCallOpen) {
      found = _matchToolCallTag(
        textBlock,
        start,
        startIndex: toolCalls.length,
      );
    } else {
      final int? blockEnd = _callBlockEnd(textBlock, start, token);
      if (blockEnd != null) {
        final (List<Map<String, Object?>> dsCalls, String? _) =
            _parseDeepseekToolCallsFromText(
              textBlock.substring(start, blockEnd),
              startIndex: toolCalls.length,
            );
        if (dsCalls.isNotEmpty) {
          found = (dsCalls, blockEnd);
        }
      }
    }
    if (found == null) {
      if (token == _toolCallOpen && start == runPos) {
        pos = runPos = _skipWhitespace(textBlock, match.end);
      } else {
        pos = match.end;
      }
      continue;
    }
    final (List<Map<String, Object?>> blockCalls, int end) = found;
    remainderParts.add(textBlock.substring(cursor, start));
    toolCalls.addAll(blockCalls);
    cursor = pos = end;
    if (start == runPos) {
      pos = runPos = _skipWhitespace(textBlock, end);
    }
  }
  remainderParts.add(textBlock.substring(cursor));
  final String joinedRemainder = remainderParts.join().trim();
  return (toolCalls, joinedRemainder.isEmpty ? null : joinedRemainder);
}

(Object?, List<Object?>) _splitMessageContentAndToolCalls(
  Map<String, Object?> message, {
  bool parseInlineToolCalls = true,
  bool allowBareJson = true,
}) {
  final List<Object?> existingToolCalls =
      (message['tool_calls'] as List<Object?>?) ?? const <Object?>[];
  final List<Object?> normalizedToolCalls = existingToolCalls.isNotEmpty
      ? List<Object?>.from(existingToolCalls)
      : <Object?>[];
  final Object? content = message['content'];

  if (normalizedToolCalls.isNotEmpty ||
      content is! String ||
      !parseInlineToolCalls) {
    return (content, normalizedToolCalls);
  }

  final (List<Map<String, Object?>> fallbackToolCalls, String? remainder) =
      parseToolCallsFromText(content, allowBareJson: allowBareJson);
  if (fallbackToolCalls.isNotEmpty) {
    return (remainder, fallbackToolCalls);
  }

  return (content, <Object?>[]);
}


