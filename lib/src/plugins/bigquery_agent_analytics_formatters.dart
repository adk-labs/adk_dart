part of 'bigquery_agent_analytics_plugin.dart';

const String _formatterFailedSentinel = '[FORMATTER_FAILED]';
const String _formattingFailedSentinel = '[FORMATTING FAILED]';
const Set<String> _responseTextSentinels = <String>{
  _formatterFailedSentinel,
  _formattingFailedSentinel,
  '[REDACTED]',
  '[CONTENT_PARSE_FAILED]',
  '[UNPARSEABLE_JSON_BLOB]',
  '[UNSUPPORTED_OBJECT]',
  '[REDACTED_SENSITIVE_TEXT]',
};

const int _maxJsonInspectChars = 512 * 1024;
const int _maxSanitizeDepth = 32;
const int _maxBasicAuthTokenChars = 16 * 1024;

const Set<String> _sensitiveKeys = <String>{
  'client_secret',
  'access_token',
  'refresh_token',
  'id_token',
  'api_key',
  'password',
  'private_key',
  'proxy_authorization',
  'google_access_id',
  'sig',
  'signature',
  'token',
  'secret',
  'authorization',
  'x_api_key',
  'x_amz_credential',
  'x_amz_signature',
  'x_goog_credential',
  'x_goog_security_token',
  'x_goog_signature',
};

final List<String> _sortedSensitiveKeyPatterns = (() {
  final List<String> keys = _sensitiveKeys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  return keys
      .map((String k) => RegExp.escape(k).replaceAll('_', '[-_]'))
      .toList(growable: false);
})();

final RegExp _sensitiveTextKeyRe = RegExp(
  r'''(?<![A-Za-z0-9_-])((?:["'])?(?:temp:[A-Za-z0-9_.-]+|'''
  '${_sortedSensitiveKeyPatterns.join('|')}'
  r''')(?:["'])?\s*[:=]\s*)("(?:\\.|[^"\\])*(")?|'(?:\\.|[^'\\])*(')?|[^\s,;&}]+)''',
  caseSensitive: false,
);

final RegExp _authHeaderRe = RegExp(
  r'(\b(?:authorization|proxy-authorization|x-api-key|api-key)[ \t]*:[ \t]*)[^\r\n]*',
  caseSensitive: false,
  multiLine: true,
);

final RegExp _bearerTokenRe = RegExp(
  r'(\bbearer\s+)(?!of(?:\s|$))(\[REDACTED\]|[^\s,;"'
  "'"
  r'}\]]+)',
  caseSensitive: false,
);

final RegExp _basicTokenRe = RegExp(
  r'(\bbasic\s+)([A-Za-z0-9+/]+={0,2})(?![A-Za-z0-9+/=])',
  caseSensitive: false,
);

final RegExp _basicRedactedRe = RegExp(
  r'\bbasic\s+\[REDACTED\]',
  caseSensitive: false,
);

final RegExp _urlUserInfoRe = RegExp(
  r'([a-zA-Z][a-zA-Z0-9+.-]*://)([^/\s:@]+:[^/\s@]+)(@)',
);

final RegExp _embeddedJsonContainerRe = RegExp(r'[\{\[][\s\ufeff]*[\{\[\"\\]');

String _stripBomWs(String text) {
  int start = 0;
  int end = text.length;
  while (start < end) {
    final int code = text.codeUnitAt(start);
    if (code == 0xFEFF || text[start].trim().isEmpty) {
      start += 1;
    } else {
      break;
    }
  }
  while (end > start) {
    final int code = text.codeUnitAt(end - 1);
    if (code == 0xFEFF || text[end - 1].trim().isEmpty) {
      end -= 1;
    } else {
      break;
    }
  }
  if (start == 0 && end == text.length) {
    return text;
  }
  return text.substring(start, end);
}

bool _isAsciiHexDigit(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}

bool _isSensitiveTextKey(String text) {
  final String normalized = text.toLowerCase().replaceAll('-', '_');
  return _sensitiveKeys.contains(normalized) || normalized.startsWith('temp:');
}

String _canonicalizeCommonAsciiEscapes(String text) {
  final List<int> output = <int>[];
  for (int i = 0; i < text.length; i += 1) {
    output.add(text.codeUnitAt(i));
    while (true) {
      final int len = output.length;
      if (len >= 2 &&
          output[len - 2] == 0x5C &&
          (output[len - 1] == 0x22 || output[len - 1] == 0x27)) {
        final int escapedQuote = output.removeLast();
        output[output.length - 1] = escapedQuote;
        continue;
      }
      int escapeStart = -1;
      String digits = '';
      if (len >= 6 &&
          output[len - 6] == 0x5C &&
          (output[len - 5] == 0x75 || output[len - 5] == 0x55) &&
          _isAsciiHexDigit(output[len - 4]) &&
          _isAsciiHexDigit(output[len - 3]) &&
          _isAsciiHexDigit(output[len - 2]) &&
          _isAsciiHexDigit(output[len - 1])) {
        escapeStart = len - 6;
        digits = String.fromCharCodes(output.sublist(len - 4));
      } else if (len >= 4 &&
          output[len - 4] == 0x5C &&
          (output[len - 3] == 0x78 || output[len - 3] == 0x58) &&
          _isAsciiHexDigit(output[len - 2]) &&
          _isAsciiHexDigit(output[len - 1])) {
        escapeStart = len - 4;
        digits = String.fromCharCodes(output.sublist(len - 2));
      } else if (len >= 3 &&
          output[len - 3] == 0x25 &&
          _isAsciiHexDigit(output[len - 2]) &&
          _isAsciiHexDigit(output[len - 1])) {
        escapeStart = len - 3;
        digits = String.fromCharCodes(output.sublist(len - 2));
      }
      if (escapeStart < 0) {
        break;
      }
      final int decoded = int.parse(digits, radix: 16);
      if (decoded > 0x7F) {
        break;
      }
      output.removeRange(escapeStart, output.length);
      output.add(decoded);
    }
  }
  return String.fromCharCodes(output);
}

class _SensitivePatternScan {
  const _SensitivePatternScan({
    required this.sanitized,
    required this.changed,
    required this.markers,
    required this.sawAlreadyRedacted,
    required this.sawUnclosedOrContainer,
  });

  final String sanitized;
  final bool changed;
  final Map<String, int> markers;
  final bool sawAlreadyRedacted;
  final bool sawUnclosedOrContainer;
}

bool _markersSubsetOrEqual(Map<String, int> left, Map<String, int> right) {
  for (final MapEntry<String, int> entry in left.entries) {
    if (entry.value > (right[entry.key] ?? 0)) {
      return false;
    }
  }
  return true;
}

_SensitivePatternScan _scanSensitivePatterns(String text) {
  final Map<String, int> markers = <String, int>{};
  bool sawAlreadyRedacted = false;
  bool sawUnclosedOrContainer = false;

  void incrementMarker(String key) {
    markers[key] = (markers[key] ?? 0) + 1;
  }

  String sanitized = text.replaceAllMapped(_urlUserInfoRe, (Match match) {
    incrementMarker('userinfo');
    final String userInfo = match.group(2)!;
    if (userInfo == '[REDACTED]') {
      sawAlreadyRedacted = true;
      return match.group(0)!;
    }
    return '${match.group(1)}[REDACTED]${match.group(3)}';
  });

  sanitized = sanitized.replaceAllMapped(_authHeaderRe, (Match match) {
    incrementMarker('header');
    final String prefix = match.group(1)!;
    final String headerValue = match.group(0)!.substring(prefix.length);
    if (headerValue.contains('[REDACTED]')) {
      sawAlreadyRedacted = true;
    }
    return '$prefix[REDACTED]';
  });

  sanitized = sanitized.replaceAllMapped(_sensitiveTextKeyRe, (Match match) {
    final String prefix = match.group(1)!;
    final String trimmedRight = prefix.replaceFirst(
      RegExp(r'[ \t\r\n:=]+$'),
      '',
    );
    final String rawKey = trimmedRight.replaceAll(
      RegExp('^["\']+|["\']+\$'),
      '',
    );
    final String normKey = rawKey.toLowerCase().replaceAll('-', '_');
    final String prefixTrimLeft = prefix.trimLeft();
    final String prefixTrimRight = prefix.trimRight();
    final String kindPrefix =
        ((prefixTrimLeft.startsWith('"') || prefixTrimLeft.startsWith("'")) &&
            prefixTrimRight.endsWith(':'))
        ? 'json_key'
        : 'kv';
    incrementMarker('$kindPrefix:$normKey');

    final String value = match.group(2)!;
    final String quoteChar =
        (value.startsWith('"') || value.startsWith("'")) ? value[0] : '';
    bool unclosedQuote = false;
    if (quoteChar == '"' && match.group(3) == null) {
      sawUnclosedOrContainer = true;
      unclosedQuote = true;
    } else if (quoteChar == "'" && match.group(4) == null) {
      sawUnclosedOrContainer = true;
      unclosedQuote = true;
    } else if (quoteChar.isEmpty &&
        (value.startsWith('{') ||
            (value.startsWith('[') && !value.startsWith('[REDACTED]')))) {
      sawUnclosedOrContainer = true;
    }
    if (value == '[REDACTED]' ||
        value == '"[REDACTED]"' ||
        value == "'[REDACTED]'") {
      sawAlreadyRedacted = true;
      if (value == '[REDACTED]') {
        return match.group(0)!;
      }
    }
    final String closingQuote = unclosedQuote ? '' : quoteChar;
    return '$prefix$quoteChar[REDACTED]$closingQuote';
  });

  sanitized = sanitized.replaceAllMapped(_bearerTokenRe, (Match match) {
    incrementMarker('bearer');
    final String prefix = match.group(1)!;
    final String value = match.group(2)!;
    if (value.toUpperCase() == '[REDACTED]') {
      sawAlreadyRedacted = true;
    }
    return '$prefix[REDACTED]';
  });

  for (final Match _ in _basicRedactedRe.allMatches(sanitized)) {
    incrementMarker('basic');
    sawAlreadyRedacted = true;
  }

  sanitized = sanitized.replaceAllMapped(_basicTokenRe, (Match match) {
    final String prefix = match.group(1)!;
    final String encoded = match.group(2)!;
    if (encoded.length > _maxBasicAuthTokenChars) {
      incrementMarker('basic');
      return '$prefix[REDACTED]';
    }
    List<int> decoded;
    try {
      decoded = base64Decode(encoded);
    } on FormatException {
      return match.group(0)!;
    }
    if (!encoded.contains('=') && !decoded.contains(0x3A)) {
      return match.group(0)!;
    }
    incrementMarker('basic');
    return '$prefix[REDACTED]';
  });

  return _SensitivePatternScan(
    sanitized: sanitized,
    changed: sanitized != text,
    markers: markers,
    sawAlreadyRedacted: sawAlreadyRedacted,
    sawUnclosedOrContainer: sawUnclosedOrContainer,
  );
}

bool _redactionCovers({required String redacted, required String reference}) {
  final List<String> segments = redacted.split('[REDACTED]');
  if (segments.length == 1) {
    return redacted == reference;
  }
  final String first = segments.first;
  final String last = segments.last;
  final int end = reference.length - last.length;
  if (end < first.length ||
      !reference.startsWith(first) ||
      !reference.endsWith(last)) {
    return false;
  }
  int pos = first.length;
  for (int i = 1; i < segments.length - 1; i += 1) {
    final String segment = segments[i];
    final int found = reference.indexOf(segment, pos);
    if (found < 0 || found + segment.length > end) {
      return false;
    }
    pos = found + segment.length;
  }
  return true;
}

bool _isMalformedJsonContainerShape(String text) {
  final String stripped = _stripBomWs(text);
  if (stripped.startsWith('{')) {
    return true;
  }
  if (stripped.startsWith('[')) {
    final String afterBracket = _stripBomWs(stripped.substring(1));
    return afterBracket.startsWith('{') ||
        afterBracket.startsWith('[') ||
        afterBracket.startsWith('"') ||
        afterBracket.startsWith(r'\');
  }
  return false;
}

bool _hasMalformedJsonMarker(String text, Map<String, int> markers) {
  if (markers.isEmpty) {
    return false;
  }
  if (_isMalformedJsonContainerShape(text) ||
      _embeddedJsonContainerRe.hasMatch(text)) {
    return true;
  }
  return markers.keys.any((String kind) => kind.startsWith('json_key:'));
}

bool _containsSensitiveTextMarker(String text) {
  final _SensitivePatternScan rawScan = _scanSensitivePatterns(text);
  if (rawScan.changed || _hasMalformedJsonMarker(text, rawScan.markers)) {
    return true;
  }
  final String canonical = _canonicalizeCommonAsciiEscapes(text);
  if (canonical == text) {
    return false;
  }
  final _SensitivePatternScan canonicalScan = _scanSensitivePatterns(canonical);
  return canonicalScan.changed ||
      _hasMalformedJsonMarker(canonical, canonicalScan.markers);
}

bool _jsonNestingExceedsLimit(String text, [int maxDepth = _maxSanitizeDepth]) {
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int i = 0; i < text.length; i += 1) {
    final int ch = text.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == 0x5C) {
        escaped = true;
      } else if (ch == 0x22) {
        inString = false;
      }
      continue;
    }
    if (ch == 0x22) {
      inString = true;
    } else if (ch == 0x7B || ch == 0x5B) {
      depth += 1;
      if (depth > maxDepth) {
        return true;
      }
    } else if (ch == 0x7D || ch == 0x5D) {
      if (depth > 0) {
        depth -= 1;
      }
    }
  }
  return false;
}

bool _jsonHasDuplicateObjectKeys(String stripped) {
  final List<Set<String>> keyStacks = <Set<String>>[];
  final List<bool> isObjectStack = <bool>[];
  final List<bool> expectingKeyStack = <bool>[];
  int i = 0;
  while (i < stripped.length) {
    final int ch = stripped.codeUnitAt(i);
    if (ch == 0x22) {
      final int start = i;
      i += 1;
      while (i < stripped.length) {
        final int c = stripped.codeUnitAt(i);
        if (c == 0x5C) {
          i += 2;
          continue;
        }
        if (c == 0x22) {
          i += 1;
          break;
        }
        i += 1;
      }
      if (expectingKeyStack.isNotEmpty && expectingKeyStack.last) {
        int j = i;
        while (j < stripped.length && stripped[j].trim().isEmpty) {
          j += 1;
        }
        if (j < stripped.length && stripped.codeUnitAt(j) == 0x3A) {
          try {
            final Object? decodedKey = jsonDecode(stripped.substring(start, i));
            if (decodedKey is String) {
              if (!keyStacks.last.add(decodedKey)) {
                return true;
              }
            }
          } catch (_) {}
          expectingKeyStack[expectingKeyStack.length - 1] = false;
        }
      }
      continue;
    }
    if (ch == 0x7B) {
      keyStacks.add(<String>{});
      isObjectStack.add(true);
      expectingKeyStack.add(true);
    } else if (ch == 0x7D) {
      if (keyStacks.isNotEmpty) {
        keyStacks.removeLast();
        isObjectStack.removeLast();
        expectingKeyStack.removeLast();
      }
    } else if (ch == 0x5B) {
      keyStacks.add(<String>{});
      isObjectStack.add(false);
      expectingKeyStack.add(false);
    } else if (ch == 0x5D) {
      if (keyStacks.isNotEmpty) {
        keyStacks.removeLast();
        isObjectStack.removeLast();
        expectingKeyStack.removeLast();
      }
    } else if (ch == 0x2C) {
      if (isObjectStack.isNotEmpty && isObjectStack.last) {
        expectingKeyStack[expectingKeyStack.length - 1] = true;
      }
    }
    i += 1;
  }
  return false;
}

const Set<String> _knownBracketedSentinels = <String>{
  ..._responseTextSentinels,
  '[MEDIA OFFLOADED]',
  '[UPLOAD FAILED]',
  '[BINARY DATA]',
  '[BINARY_DATA]',
  '[CIRCULAR_REFERENCE]',
  '[MAX_DEPTH_EXCEEDED]',
  '[SANITIZE_BUDGET_EXCEEDED]',
  _cycleDetectedMessage,
};

(String, bool, bool) _sanitizeJsonBlob(
  String value,
  Set<int> seen, [
  int depth = 0,
  int maxLen = -1,
]) {
  final String stripped = _stripBomWs(value);
  if (_knownBracketedSentinels.contains(stripped)) {
    return (value, false, false);
  }
  final int inspectLimit = maxLen != -1 && maxLen < _maxJsonInspectChars
      ? maxLen
      : _maxJsonInspectChars;

  if (stripped.startsWith('"')) {
    if (depth >= _maxSanitizeDepth) {
      return ('[UNPARSEABLE_JSON_BLOB]', true, true);
    }
    if (stripped.length > inspectLimit) {
      final String emitted = maxLen == -1
          ? stripped
          : stripped.substring(0, maxLen);
      if (emitted.contains('{') ||
          emitted.contains('[') ||
          emitted.contains(r'\')) {
        return ('[UNPARSEABLE_JSON_BLOB]', true, true);
      }
      return (value, false, false);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(stripped);
    } catch (_) {
      final String afterQuote = _stripBomWs(stripped.substring(1));
      if (afterQuote.startsWith('{') ||
          afterQuote.startsWith('[') ||
          afterQuote.startsWith(r'\') ||
          afterQuote.startsWith('"')) {
        return ('[UNPARSEABLE_JSON_BLOB]', true, true);
      }
      return (value, false, false);
    }
    if (decoded is! String) {
      return (value, false, false);
    }
    final String inner = _stripBomWs(decoded);
    if (inner.startsWith('{') ||
        inner.startsWith('[') ||
        inner.startsWith('"')) {
      final (String pSanitized, bool pChanged, bool pTruncated) =
          _sanitizeJsonBlob(decoded, seen, depth + 1, maxLen);
      if (pChanged && pSanitized == '[UNPARSEABLE_JSON_BLOB]') {
        return ('[UNPARSEABLE_JSON_BLOB]', true, true);
      }
      if (!pChanged) {
        return (value, false, false);
      }
      return (jsonEncode(pSanitized), true, pTruncated);
    }
    final (String sText, bool sChanged) = _sanitizeSensitiveText(decoded, -1);
    if (sText == '[REDACTED_SENSITIVE_TEXT]' &&
        decoded != '[REDACTED_SENSITIVE_TEXT]') {
      return ('[UNPARSEABLE_JSON_BLOB]', true, true);
    }
    if (!sChanged) {
      return (value, false, false);
    }
    return (jsonEncode(sText), true, sChanged);
  }

  if (!stripped.startsWith('{') && !stripped.startsWith('[')) {
    return (value, false, false);
  }
  if (stripped.length > inspectLimit || _jsonNestingExceedsLimit(stripped)) {
    return ('[UNPARSEABLE_JSON_BLOB]', true, true);
  }

  try {
    final Object? parsed = jsonDecode(stripped);
    if (parsed is! Map && parsed is! List) {
      return (value, false, false);
    }
    final bool sawDuplicate = _jsonHasDuplicateObjectKeys(stripped);
    final _TruncateResult sanitizedResult = _recursiveSmartTruncate(
      parsed,
      -1,
      seen,
      depth + 1,
    );
    final String encodedSanitized = jsonEncode(sanitizedResult.value);
    final String encodedParsed = jsonEncode(parsed);
    if (encodedSanitized == encodedParsed &&
        !sawDuplicate &&
        !sanitizedResult.isTruncated) {
      return (value, false, false);
    }
    return (encodedSanitized, true, sanitizedResult.isTruncated);
  } catch (_) {
    return ('[UNPARSEABLE_JSON_BLOB]', true, true);
  }
}

(String, bool) _sanitizeSensitiveText(String text, int maxLen) {
  final int inspectCap = maxLen != -1
      ? max(maxLen, _maxJsonInspectChars)
      : _maxJsonInspectChars;
  bool lengthTruncated = false;
  String working = text;
  if (working.length > inspectCap) {
    working = working.substring(0, inspectCap);
    lengthTruncated = true;
  }

  String sanitized = working;
  bool parsedJson = false;
  bool malformedContainer = false;
  final String stripped = _stripBomWs(working);
  if (stripped.startsWith('{') ||
      stripped.startsWith('[') ||
      stripped.startsWith('"')) {
    try {
      final Object? loaded = jsonDecode(stripped);
      parsedJson = loaded is Map || loaded is List;
      final _TruncateResult structured = _recursiveSmartTruncate(working, -1);
      if (structured.value is String) {
        sanitized = structured.value as String;
      } else {
        sanitized = '[REDACTED_SENSITIVE_TEXT]';
      }
    } catch (_) {
      malformedContainer =
          stripped.startsWith('{') || stripped.startsWith('[');
    }
  }

  bool changed = sanitized != working;
  final String beforePatterns = sanitized;
  final _SensitivePatternScan rawScan = _scanSensitivePatterns(sanitized);
  sanitized = rawScan.sanitized;
  final Map<String, int> rawMarkers = rawScan.markers;
  changed = changed || rawScan.changed;

  if (!parsedJson) {
    if (rawScan.sawUnclosedOrContainer) {
      return ('[REDACTED_SENSITIVE_TEXT]', true);
    }
    if (_hasMalformedJsonMarker(beforePatterns, rawMarkers) &&
        (rawScan.sawAlreadyRedacted ||
            rawMarkers.keys.any((String k) => k.startsWith('json_key:')))) {
      return ('[REDACTED_SENSITIVE_TEXT]', true);
    }
  }

  final String canonicalInput = _canonicalizeCommonAsciiEscapes(beforePatterns);
  if (canonicalInput != beforePatterns) {
    final String canonical = _canonicalizeCommonAsciiEscapes(sanitized);
    final _SensitivePatternScan canonicalScan = _scanSensitivePatterns(
      canonical,
    );
    final _SensitivePatternScan referenceScan = _scanSensitivePatterns(
      canonicalInput,
    );
    final bool hasUnparsedContainer =
        malformedContainer || _embeddedJsonContainerRe.hasMatch(canonicalInput);
    if (canonicalScan.changed ||
        canonicalScan.sawUnclosedOrContainer ||
        referenceScan.sawUnclosedOrContainer ||
        !_redactionCovers(
          redacted: canonical,
          reference: referenceScan.sanitized,
        ) ||
        (!parsedJson &&
            hasUnparsedContainer &&
            !_markersSubsetOrEqual(canonicalScan.markers, rawMarkers)) ||
        (!parsedJson &&
            _hasMalformedJsonMarker(canonicalInput, referenceScan.markers) &&
            (referenceScan.sawAlreadyRedacted ||
                referenceScan.markers.keys.any(
                  (String k) => k.startsWith('json_key:'),
                )))) {
      return ('[REDACTED_SENSITIVE_TEXT]', true);
    }
  }

  if (maxLen != -1 && sanitized.length > maxLen) {
    sanitized = '${sanitized.substring(0, maxLen)}...[TRUNCATED]';
    lengthTruncated = true;
  } else if (lengthTruncated) {
    sanitized = '$sanitized...[TRUNCATED]';
  }

  return (sanitized, changed || lengthTruncated);
}

/// Content parser and fail-closed credential sanitizer for BigQuery rows.
class HybridContentParser {
  /// Creates a [HybridContentParser] with the given [maxLength].
  HybridContentParser({this.maxLength = 500 * 1024});

  /// Maximum character length for inline text fields (`-1` for unlimited).
  final int maxLength;

  /// Sanitizes raw user/model text while rescuing safe non-JSON prose.
  static (String, bool) sanitizeRawText(String text) {
    if (text == _formatterFailedSentinel || text == '[REDACTED]') {
      return (text, false);
    }
    if (_responseTextSentinels.contains(text)) {
      return (text, true);
    }
    final _TruncateResult truncated = _recursiveSmartTruncate(text, -1);
    final Object? sanitizedObj = truncated.value;
    if (sanitizedObj == '[UNPARSEABLE_JSON_BLOB]') {
      final String stripped = _stripBomWs(text);
      if (stripped.length <= _maxJsonInspectChars &&
          !_jsonNestingExceedsLimit(stripped) &&
          !_containsSensitiveTextMarker(text)) {
        try {
          jsonDecode(stripped);
        } catch (_) {
          return (text, false);
        }
      }
      return ('[UNPARSEABLE_JSON_BLOB]', true);
    }
    if (sanitizedObj is! String) {
      return ('[UNSUPPORTED_OBJECT]', true);
    }
    final (String sensSanitized, bool sensLost) = _sanitizeSensitiveText(
      sanitizedObj,
      -1,
    );
    return (sensSanitized, truncated.isTruncated || sensLost);
  }

  /// Sanitizes [text] and applies [maxLength] truncation.
  (String, bool) sanitizeAndTruncate(String text) {
    final (String sanitized, bool contentLost) = sanitizeRawText(text);
    if (maxLength != -1 && sanitized.length > maxLength) {
      return ('${sanitized.substring(0, maxLength)}...[TRUNCATED]', true);
    }
    return (sanitized, contentLost);
  }
}

String _getToolOrigin(BaseTool tool) {
  if (tool is McpTool) {
    return 'MCP';
  }
  if (tool is TransferToAgentTool) {
    return 'TRANSFER_AGENT';
  }
  if (tool is AgentTool) {
    if (tool.agent is RemoteA2aAgent) {
      return 'A2A';
    }
    return 'SUB_AGENT';
  }
  if (tool is FunctionTool) {
    return 'LOCAL';
  }
  final String runtimeTypeName = tool.runtimeType.toString();
  if (runtimeTypeName == 'ToolboxTool') {
    return 'TOOLBOX';
  }
  if (_skillToolTypeNames.contains(runtimeTypeName)) {
    return 'SKILL';
  }
  return 'UNKNOWN';
}

/// Extracts structured tool metadata for the `LLM_REQUEST` event.
///
/// Earlier versions logged only the tool names. Downstream consumers such as
/// online evaluation need the tool *description* and *parameter schema* to judge
/// whether the model selected and invoked the right tool, so this returns one
/// `{name, description?, parameters?}` entry per tool instead of a bare name.
///
/// Extraction is best-effort and per-tool: a tool whose declaration cannot be
/// resolved still contributes its name and description, so one misbehaving tool
/// never drops the whole `tools` attribute. Ports adk-python ecef5f85.
List<Map<String, Object?>> _extractToolDeclarations(
  Map<String, BaseTool> toolsDict,
) {
  final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
  toolsDict.forEach((String name, BaseTool tool) {
    // Fall back to the map key when the tool has no (or an empty) name.
    final Map<String, Object?> entry = <String, Object?>{
      'name': tool.name.isNotEmpty ? tool.name : name,
    };
    if (tool.description.isNotEmpty) {
      entry['description'] = tool.description;
    }

    // The parameter schema lives on the tool's FunctionDeclaration, which some
    // tools (e.g. built-in tools) do not provide. Resolve defensively so a
    // single failing tool does not discard the whole tools list.
    FunctionDeclaration? declaration;
    try {
      declaration = tool.getDeclaration();
    } catch (_) {
      declaration = null;
    }

    if (declaration != null) {
      if (!entry.containsKey('description') &&
          declaration.description.isNotEmpty) {
        entry['description'] = declaration.description;
      }
      if (declaration.parameters.isNotEmpty) {
        entry['parameters'] = declaration.parameters;
      }
    }

    tools.add(entry);
  });
  return tools;
}

class _FormatResult {
  _FormatResult({required this.text, required this.isTruncated});

  final String text;
  final bool isTruncated;
}

_FormatResult _formatContent(Content? content, {int maxLen = 5000}) {
  if (content == null || content.parts.isEmpty) {
    return _FormatResult(text: 'None', isTruncated: false);
  }

  final List<String> parts = <String>[];
  bool truncated = false;
  final HybridContentParser parser = HybridContentParser(maxLength: -1);
  for (final Part part in content.parts) {
    if (part.text != null) {
      final (String sanitized, bool contentLost) = parser.sanitizeAndTruncate(
        part.text!,
      );
      String value = sanitized;
      if (maxLen != -1 && value.length > maxLen) {
        value = '${value.substring(0, maxLen)}...';
        truncated = true;
      }
      truncated = truncated || contentLost;
      parts.add("text: '$value'");
    } else if (part.functionCall != null) {
      parts.add('call: ${part.functionCall!.name}');
    } else if (part.functionResponse != null) {
      parts.add('resp: ${part.functionResponse!.name}');
    } else {
      parts.add('other');
    }
  }
  return _FormatResult(text: parts.join(' | '), isTruncated: truncated);
}

_TruncateResult _serializeContentPayload(
  Object? value, {
  required int maxLength,
}) {
  if (value is LlmRequest) {
    final List<Object?> prompt = value.contents
        .map((Content content) => _contentToJson(content))
        .toList(growable: false);
    return _recursiveSmartTruncate(<String, Object?>{
      'prompt': prompt,
      if (value.config.systemInstruction != null)
        'system_prompt': value.config.systemInstruction,
    }, maxLength);
  }

  if (value is LlmResponse) {
    return _recursiveSmartTruncate(<String, Object?>{
      'content': _contentToJson(value.content),
      'partial': value.partial,
      'turn_complete': value.turnComplete,
      'error_code': value.errorCode,
      'error_message': value.errorMessage,
    }, maxLength);
  }

  if (value is Content) {
    return _recursiveSmartTruncate(_contentToJson(value), maxLength);
  }

  if (value is Part) {
    return _recursiveSmartTruncate(_partToJson(value), maxLength);
  }

  if (value is String) {
    final (String sanitized, bool isTruncated) = HybridContentParser(
      maxLength: maxLength,
    ).sanitizeAndTruncate(value);
    return _TruncateResult(value: sanitized, isTruncated: isTruncated);
  }

  if (value is Map && value['text_summary'] is String) {
    final String rawTextSummary = value['text_summary'] as String;
    String summaryVal;
    bool summaryTrunc;
    if (_responseTextSentinels.contains(rawTextSummary)) {
      summaryVal = rawTextSummary;
      summaryTrunc =
          rawTextSummary == _formattingFailedSentinel ||
          rawTextSummary == '[CONTENT_PARSE_FAILED]' ||
          rawTextSummary == '[UNPARSEABLE_JSON_BLOB]' ||
          rawTextSummary == '[UNSUPPORTED_OBJECT]' ||
          rawTextSummary == '[REDACTED_SENSITIVE_TEXT]';
    } else {
      final (String sVal, bool sTrunc) = HybridContentParser(
        maxLength: maxLength,
      ).sanitizeAndTruncate(rawTextSummary);
      summaryVal = sVal;
      summaryTrunc = sTrunc;
    }
    final Map<Object?, Object?> staged = Map<Object?, Object?>.from(value);
    staged['text_summary'] = '';
    final _TruncateResult dictResult = _recursiveSmartTruncate(
      staged,
      maxLength,
    );
    if (dictResult.value is Map) {
      final Map<String, Object?> outMap = Map<String, Object?>.from(
        dictResult.value! as Map,
      );
      if (outMap.containsKey('text_summary')) {
        outMap['text_summary'] = summaryVal;
      }
      return _TruncateResult(
        value: outMap,
        isTruncated: summaryTrunc || dictResult.isTruncated,
      );
    }
    return _TruncateResult(
      value: dictResult.value,
      isTruncated: summaryTrunc || dictResult.isTruncated,
    );
  }

  return _recursiveSmartTruncate(value, maxLength);
}

Future<List<Object?>> _extractContentPartsForLogging(
  Object? value, {
  required int maxLength,
  required BigQueryGcsUploadProvider? gcsUploadProvider,
  required String traceId,
  required String? spanId,
  required String? connectionId,
}) async {
  if (value is Content) {
    final List<Object?> parts = <Object?>[];
    for (int index = 0; index < value.parts.length; index += 1) {
      parts.add(
        await _partToContentPartForLogging(
          value.parts[index],
          index,
          maxLength: maxLength,
          gcsUploadProvider: gcsUploadProvider,
          traceId: traceId,
          spanId: spanId,
          connectionId: connectionId,
        ),
      );
    }
    return parts;
  }

  if (value is Part) {
    return <Object?>[
      await _partToContentPartForLogging(
        value,
        0,
        maxLength: maxLength,
        gcsUploadProvider: gcsUploadProvider,
        traceId: traceId,
        spanId: spanId,
        connectionId: connectionId,
      ),
    ];
  }

  if (value is LlmResponse) {
    return _extractContentPartsForLogging(
      value.content,
      maxLength: maxLength,
      gcsUploadProvider: gcsUploadProvider,
      traceId: traceId,
      spanId: spanId,
      connectionId: connectionId,
    );
  }

  if (value is LlmRequest) {
    final List<Object?> parts = <Object?>[];
    for (final Content content in value.contents) {
      parts.addAll(
        await _extractContentPartsForLogging(
          content,
          maxLength: maxLength,
          gcsUploadProvider: gcsUploadProvider,
          traceId: traceId,
          spanId: spanId,
          connectionId: connectionId,
        ),
      );
    }
    return parts;
  }

  if (value is Map) {
    final Map<String, Object?> map = _toStringObjectMap(value);
    final Object? explicitParts = map['content_parts'];
    if (explicitParts is List) {
      return explicitParts
          .map((Object? part) => _recursiveSmartTruncate(part, maxLength).value)
          .toList(growable: false);
    }

    final Map<String, Object?> content = _toStringObjectMap(map['content']);
    final Object? partsRaw = content['parts'];
    if (partsRaw is List) {
      return partsRaw
          .map((Object? part) => _recursiveSmartTruncate(part, maxLength).value)
          .toList(growable: false);
    }
  }

  return const <Object?>[];
}

Future<Object?> _partToContentPartForLogging(
  Part part,
  int index, {
  required int maxLength,
  required BigQueryGcsUploadProvider? gcsUploadProvider,
  required String traceId,
  required String? spanId,
  required String? connectionId,
}) async {
  final Map<String, Object?> partData = <String, Object?>{
    'part_index': index,
    'mime_type': 'text/plain',
    'uri': null,
    'text': null,
    'part_attributes': '{}',
    'storage_mode': 'INLINE',
    'object_ref': null,
  };

  final FileData? fileData = part.fileData;
  if (fileData != null) {
    partData['storage_mode'] = 'EXTERNAL_URI';
    final (String safeUri, _) = _sanitizeSensitiveText(
      fileData.fileUri,
      maxLength,
    );
    partData['uri'] = safeUri;
    partData['mime_type'] = fileData.mimeType;
    return _recursiveSmartTruncate(partData, maxLength).value;
  }

  final InlineData? inlineData = part.inlineData;
  if (inlineData != null) {
    final String mimeType = inlineData.mimeType.isEmpty
        ? 'application/octet-stream'
        : inlineData.mimeType;
    partData['mime_type'] = mimeType;
    if (gcsUploadProvider != null) {
      final String path = _gcsOffloadPath(
        traceId: traceId,
        spanId: spanId,
        partIndex: index,
        extension: _mimeTypeExtension(mimeType),
      );
      try {
        final String uri = await gcsUploadProvider(
          data: List<int>.from(inlineData.data),
          contentType: mimeType,
          path: path,
        );
        partData['storage_mode'] = 'GCS_REFERENCE';
        partData['uri'] = uri;
        partData['text'] = '[MEDIA OFFLOADED]';
        partData['object_ref'] = _gcsObjectRef(
          uri: uri,
          contentType: mimeType,
          connectionId: connectionId,
        );
      } catch (error) {
        stderr.writeln('Failed to offload content to GCS: $error');
        partData['text'] = '[UPLOAD FAILED]';
      }
    } else {
      partData['text'] = '[BINARY DATA]';
    }
    return _recursiveSmartTruncate(partData, maxLength).value;
  }

  final String? text = part.text;
  if (text != null) {
    final (String safeText, _) = HybridContentParser.sanitizeRawText(text);
    final int byteLength = utf8.encode(safeText).length;
    final bool exceedsByteLimit = byteLength > 32 * 1024;
    final bool exceedsCharLimit =
        maxLength != -1 && safeText.length > maxLength;
    if (gcsUploadProvider != null && (exceedsByteLimit || exceedsCharLimit)) {
      final String path = _gcsOffloadPath(
        traceId: traceId,
        spanId: spanId,
        partIndex: index,
        extension: '.txt',
      );
      try {
        final String uri = await gcsUploadProvider(
          data: utf8.encode(safeText),
          contentType: 'text/plain',
          path: path,
        );
        partData['storage_mode'] = 'GCS_REFERENCE';
        partData['uri'] = uri;
        partData['mime_type'] = 'text/plain';
        partData['text'] = _truncateAndAddSuffix(
          safeText,
          200,
          '... [OFFLOADED]',
        );
        partData['object_ref'] = _gcsObjectRef(
          uri: uri,
          contentType: 'text/plain',
          connectionId: connectionId,
        );
        return _recursiveSmartTruncate(partData, maxLength).value;
      } catch (error) {
        stderr.writeln('Failed to offload text to GCS: $error');
      }
    }
    partData['text'] = maxLength != -1 && safeText.length > maxLength
        ? '${safeText.substring(0, maxLength)}...[TRUNCATED]'
        : safeText;
    return partData;
  }

  final FunctionCall? functionCall = part.functionCall;
  if (functionCall != null) {
    partData['mime_type'] = 'application/json';
    partData['text'] = 'Function: ${functionCall.name}';
    partData['part_attributes'] = jsonEncode(<String, Object?>{
      'function_name': functionCall.name,
    });
    return _recursiveSmartTruncate(partData, maxLength).value;
  }

  final FunctionResponse? functionResponse = part.functionResponse;
  if (functionResponse != null) {
    partData['mime_type'] = 'application/json';
    partData['text'] = 'Function response: ${functionResponse.name}';
    partData['part_attributes'] = jsonEncode(<String, Object?>{
      'function_name': functionResponse.name,
    });
    return _recursiveSmartTruncate(partData, maxLength).value;
  }

  partData['part_attributes'] = jsonEncode(_partToJson(part));
  return _recursiveSmartTruncate(partData, maxLength).value;
}

Map<String, Object?> _gcsObjectRef({
  required String uri,
  required String contentType,
  required String? connectionId,
}) {
  return <String, Object?>{
    'uri': uri,
    'version': null,
    'authorizer': connectionId,
    'details': jsonEncode(<String, Object?>{
      'gcs_metadata': <String, Object?>{'content_type': contentType},
    }),
  };
}

String _gcsOffloadPath({
  required String traceId,
  required String? spanId,
  required int partIndex,
  required String extension,
}) {
  final String date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final String safeTrace = _safeGcsPathSegment(traceId);
  final String safeSpan = _safeGcsPathSegment(spanId ?? 'root');
  return '$date/$safeTrace/${safeSpan}_p${partIndex}_${_newInsertId()}$extension';
}

String _safeGcsPathSegment(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

String _mimeTypeExtension(String mimeType) {
  const Map<String, String> known = <String, String>{
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'audio/wav': '.wav',
    'audio/mpeg': '.mp3',
    'audio/ogg': '.ogg',
    'video/mp4': '.mp4',
    'application/pdf': '.pdf',
    'text/plain': '.txt',
  };
  final String? mapped = known[mimeType.toLowerCase()];
  if (mapped != null) {
    return mapped;
  }
  return '.bin';
}

String _truncateAndAddSuffix(String text, int maxLength, String suffix) {
  if (text.length <= maxLength) {
    return '$text$suffix';
  }
  return '${text.substring(0, maxLength)}$suffix';
}

Map<String, Object?> _toStringObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, Object?>? _contentToJson(Content? content) {
  if (content == null) {
    return null;
  }

  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_partToJson).toList(growable: false),
  };
}

Map<String, Object?> _partToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    if (part.thought) 'thought': true,
    if (part.thoughtSignature != null)
      'thought_signature': List<int>.from(part.thoughtSignature!),
    if (part.functionCall != null)
      'function_call': <String, Object?>{
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
        'name': part.functionCall!.name,
        'args': Map<String, dynamic>.from(part.functionCall!.args),
        if (part.functionCall!.partialArgs != null)
          'partial_args': part.functionCall!.partialArgs
              ?.map(
                (Map<String, Object?> value) =>
                    Map<String, Object?>.from(value),
              )
              .toList(growable: false),
        if (part.functionCall!.willContinue != null)
          'will_continue': part.functionCall!.willContinue,
      },
    if (part.functionResponse != null)
      'function_response': <String, Object?>{
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
        'name': part.functionResponse!.name,
        'response': Map<String, dynamic>.from(part.functionResponse!.response),
      },
    if (part.inlineData != null)
      'inline_data': <String, Object?>{
        'mime_type': part.inlineData!.mimeType,
        if (part.inlineData!.displayName != null)
          'display_name': part.inlineData!.displayName,
      },
    if (part.fileData != null)
      'file_data': <String, Object?>{
        'file_uri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mime_type': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'display_name': part.fileData!.displayName,
      },
  };
}

_TruncateResult _recursiveSmartTruncate(
  Object? value,
  int maxLength, [
  Set<int>? seen,
  int depth = 0,
]) {
  final Set<int> visited = seen ?? <int>{};
  if (depth >= _maxSanitizeDepth) {
    return _TruncateResult(value: '[MAX_DEPTH_EXCEEDED]', isTruncated: true);
  }

  if (value == null || value is num || value is bool) {
    return _TruncateResult(value: value, isTruncated: false);
  }

  if (value is String) {
    final (String blobValue, bool blobChanged, bool blobTruncated) =
        _sanitizeJsonBlob(value, visited, depth, maxLength);
    if (blobChanged && blobValue == '[UNPARSEABLE_JSON_BLOB]') {
      return _TruncateResult(value: blobValue, isTruncated: true);
    }
    if (maxLength != -1 && blobValue.length > maxLength) {
      return _TruncateResult(
        value: '${blobValue.substring(0, maxLength)}...[TRUNCATED]',
        isTruncated: true,
      );
    }
    return _TruncateResult(value: blobValue, isTruncated: blobTruncated);
  }
  if (value is CacheMetadata) {
    return _recursiveSmartTruncate(
      <String, Object?>{
        if (value.cacheName != null) 'cache_name': value.cacheName,
        if (value.expireTime != null) 'expire_time': value.expireTime,
        'fingerprint': value.fingerprint,
        if (value.invocationsUsed != null)
          'invocations_used': value.invocationsUsed,
        'contents_count': value.contentsCount,
        if (value.createdAt != null) 'created_at': value.createdAt,
      },
      maxLength,
      visited,
      depth + 1,
    );
  }

  final int identity = identityHashCode(value);
  if (visited.contains(identity)) {
    return _TruncateResult(value: _cycleDetectedMessage, isTruncated: true);
  }

  final bool isCompound = value is Map || value is List || value is Set;
  if (isCompound) {
    visited.add(identity);
  }

  try {
    if (value is List) {
      bool truncated = false;
      final List<Object?> converted = <Object?>[];
      for (final Object? item in value) {
        final _TruncateResult child = _recursiveSmartTruncate(
          item,
          maxLength,
          visited,
          depth + 1,
        );
        converted.add(child.value);
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    if (value is Set) {
      bool truncated = false;
      final List<Object?> converted = <Object?>[];
      for (final Object? item in value) {
        final _TruncateResult child = _recursiveSmartTruncate(
          item,
          maxLength,
          visited,
          depth + 1,
        );
        converted.add(child.value);
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    if (value is Map) {
      bool truncated = false;
      final Map<String, Object?> converted = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final String keyStr = '${entry.key}';
        final String canonicalKey = _canonicalizeCommonAsciiEscapes(keyStr);
        if (_isSensitiveTextKey(keyStr) || _isSensitiveTextKey(canonicalKey)) {
          converted[keyStr] = '[REDACTED]';
          continue;
        }
        final _TruncateResult child = _recursiveSmartTruncate(
          entry.value,
          maxLength,
          visited,
          depth + 1,
        );
        converted[keyStr] = child.value;
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    final String fallback = '$value';
    final (String safeFallback, bool fallbackLost) = _sanitizeSensitiveText(
      fallback,
      maxLength,
    );
    return _TruncateResult(value: safeFallback, isTruncated: fallbackLost);
  } finally {
    if (isCompound) {
      visited.remove(identity);
    }
  }
}

void _putIfNotNull(Map<String, Object?> map, String key, Object? value) {
  if (value != null) {
    map[key] = value;
  }
}

Future<String?> _defaultBigQueryAccessTokenProvider() async {
  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
}

String _newInsertId() {
  final int micros = DateTime.now().microsecondsSinceEpoch;
  final int randomBits = Random().nextInt(1 << 20);
  return '${micros.toRadixString(16)}${randomBits.toRadixString(16)}';
}

Map<String, Object?> _toJsonSafeMap(Map<String, Object?> source) {
  final Map<String, Object?> converted = <String, Object?>{};
  final Set<int> visited = <int>{identityHashCode(source)};
  source.forEach((String key, Object? value) {
    converted[key] = _toJsonSafeValue(value, visited);
  });
  return converted;
}

Object? _toJsonSafeValue(Object? value, Set<int> visited) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }

  final bool isCompound = value is List || value is Set || value is Map;
  final int identity = identityHashCode(value);
  if (isCompound) {
    if (visited.contains(identity)) {
      return _cycleDetectedMessage;
    }
    visited.add(identity);
  }

  try {
    if (value is List) {
      return value
          .map((Object? item) => _toJsonSafeValue(item, visited))
          .toList(growable: false);
    }
    if (value is Set) {
      return value
          .map((Object? item) => _toJsonSafeValue(item, visited))
          .toList(growable: false);
    }
    if (value is Map) {
      final Map<String, Object?> nested = <String, Object?>{};
      value.forEach((Object? nestedKey, Object? nestedValue) {
        nested['$nestedKey'] = _toJsonSafeValue(nestedValue, visited);
      });
      return nested;
    }
    return '$value';
  } finally {
    if (isCompound) {
      visited.remove(identity);
    }
  }
}
