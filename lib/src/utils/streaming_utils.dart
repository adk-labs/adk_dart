/// Shared utility and helper APIs for ADK runtime behavior.
library;

import 'dart:convert';

import '../flows/llm_flows/functions.dart' as flow_functions;
import '../features/_feature_registry.dart';
import '../models/llm_response.dart';
import '../types/content.dart';

/// Aggregates streamed [LlmResponse] chunks into coherent final responses.
class StreamingResponseAggregator {
  String _text = '';
  String _thoughtText = '';
  List<int>? _textThoughtSignature;
  List<int>? _thoughtTextSignature;
  Object? _usageMetadata;
  Object? _citationMetadata;
  Object? _groundingMetadata;
  double? _avgLogprobs;
  Object? _logprobsResult;
  Object? _cacheMetadata;
  String? _interactionId;
  String? _modelVersion;
  LlmResponse? _response;

  final List<Part> _partsSequence = <Part>[];
  String _currentTextBuffer = '';
  bool? _currentTextIsThought;
  List<int>? _currentTextThoughtSignature;
  List<int>? _currentThoughtSignature;
  String? _finishReason;

  String? _currentFcName;
  Map<String, Object?> _currentFcArgs = <String, Object?>{};
  String? _currentFcId;
  List<int>? _currentFcThoughtSignature;
  bool _sawFunctionCall = false;

  void _flushTextBufferToSequence() {
    if (_currentTextBuffer.isEmpty) {
      return;
    }
    _partsSequence.add(
      Part.text(
        _currentTextBuffer,
        thought: _currentTextIsThought ?? false,
        thoughtSignature: _currentTextThoughtSignature,
      ),
    );
    _currentTextBuffer = '';
    _currentTextIsThought = null;
    _currentTextThoughtSignature = null;
  }

  (Object?, bool) _getValueFromPartialArg(
    Map<String, Object?> partialArg,
    String jsonPath,
  ) {
    final Object? stringValue =
        partialArg['string_value'] ?? partialArg['stringValue'];
    if (stringValue != null) {
      final String chunk = '$stringValue';
      final Object? existing = _getValueByJsonPath(jsonPath);
      if (existing is String) {
        return (existing + chunk, true);
      }
      return (chunk, true);
    }
    final Object? numberValue =
        partialArg['number_value'] ?? partialArg['numberValue'];
    if (numberValue != null) {
      return (numberValue, true);
    }
    final Object? boolValue =
        partialArg['bool_value'] ?? partialArg['boolValue'];
    if (boolValue != null) {
      return (boolValue, true);
    }
    if (partialArg.containsKey('null_value') ||
        partialArg.containsKey('nullValue')) {
      return (null, true);
    }
    return (null, false);
  }

  Object? _getValueByJsonPath(String jsonPath) {
    final List<String> pathParts = _jsonPathParts(jsonPath);
    if (pathParts.isEmpty) {
      return null;
    }

    Object? current = _currentFcArgs;
    for (final String part in pathParts) {
      if (current is! Map<String, Object?> || !current.containsKey(part)) {
        return null;
      }
      current = current[part];
    }
    return current;
  }

  void _setValueByJsonPath(String jsonPath, Object? value) {
    final List<String> pathParts = _jsonPathParts(jsonPath);
    if (pathParts.isEmpty) {
      return;
    }

    Map<String, Object?> current = _currentFcArgs;
    for (final String part in pathParts.take(pathParts.length - 1)) {
      final Object? next = current[part];
      if (next is Map<String, Object?>) {
        current = next;
        continue;
      }
      final Map<String, Object?> nested = <String, Object?>{};
      current[part] = nested;
      current = nested;
    }
    current[pathParts.last] = value;
  }

  void _flushFunctionCallToSequence() {
    final String? name = _currentFcName;
    if (name == null || name.isEmpty) {
      return;
    }

    _partsSequence.add(
      Part.fromFunctionCall(
        name: name,
        args: Map<String, dynamic>.from(_currentFcArgs),
        id: _currentFcId,
        thoughtSignature: _currentFcThoughtSignature,
      ),
    );
    _currentFcName = null;
    _currentFcArgs = <String, Object?>{};
    _currentFcId = null;
    _currentFcThoughtSignature = null;
  }

  void _processStreamingFunctionCall(FunctionCall functionCall, Part part) {
    if ((functionCall.id ?? '').isEmpty && (_currentFcId ?? '').isEmpty) {
      final String generatedId = flow_functions.generateClientFunctionCallId();
      functionCall.id = generatedId;
      _currentFcId = generatedId;
    }
    if (functionCall.name.isNotEmpty) {
      _currentFcName = functionCall.name;
    }
    if (functionCall.id != null && functionCall.id!.isNotEmpty) {
      _currentFcId = functionCall.id;
    }
    if (part.thoughtSignature != null && part.thoughtSignature!.isNotEmpty) {
      _currentFcThoughtSignature = List<int>.from(part.thoughtSignature!);
    }

    final List<Map<String, Object?>> partialArgs = _partialArgs(functionCall);
    for (final Map<String, Object?> partialArg in partialArgs) {
      final String? jsonPath =
          partialArg['json_path']?.toString() ??
          partialArg['jsonPath']?.toString();
      if (jsonPath == null || jsonPath.isEmpty) {
        continue;
      }
      final (Object? value, bool hasValue) = _getValueFromPartialArg(
        partialArg,
        jsonPath,
      );
      if (hasValue) {
        _setValueByJsonPath(jsonPath, value);
      }
    }

    if (!_willContinue(functionCall)) {
      _flushTextBufferToSequence();
      _flushFunctionCallToSequence();
    }
  }

  void _processFunctionCallPart(Part part) {
    final FunctionCall? functionCall = part.functionCall;
    if (functionCall == null) {
      return;
    }

    Part effectivePart = part;
    if ((part.thoughtSignature == null || part.thoughtSignature!.isEmpty) &&
        _currentThoughtSignature != null &&
        functionCall.name.isNotEmpty) {
      effectivePart = part.copyWith(
        thoughtSignature: List<int>.from(_currentThoughtSignature!),
      );
    }

    if (_isStreamingFunctionCall(functionCall)) {
      _processStreamingFunctionCall(functionCall, effectivePart);
      if (functionCall.name.isNotEmpty) {
        _currentThoughtSignature = null;
      }
      return;
    }

    if (functionCall.name.isEmpty) {
      return;
    }
    if ((functionCall.id ?? '').isEmpty) {
      functionCall.id = flow_functions.generateClientFunctionCallId();
    }

    _flushTextBufferToSequence();
    _partsSequence.add(effectivePart.copyWith());
    _currentThoughtSignature = null;
  }

  List<Map<String, Object?>> _partialArgs(FunctionCall functionCall) {
    final List<Map<String, Object?>>? direct = functionCall.partialArgs;
    if (direct != null && direct.isNotEmpty) {
      return direct
          .map((Map<String, Object?> value) => Map<String, Object?>.from(value))
          .toList(growable: false);
    }
    final Object? raw =
        functionCall.args['partial_args'] ?? functionCall.args['partialArgs'];
    if (raw is! List) {
      return const <Map<String, Object?>>[];
    }
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Object? item in raw) {
      if (item is Map<String, Object?>) {
        result.add(item);
      } else if (item is Map) {
        result.add(
          item.map((Object? key, Object? value) => MapEntry('$key', value)),
        );
      }
    }
    return result;
  }

  bool _willContinue(FunctionCall functionCall) {
    final bool? direct = functionCall.willContinue;
    if (direct != null) {
      return direct;
    }
    final Object? raw =
        functionCall.args['will_continue'] ?? functionCall.args['willContinue'];
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final String lowered = raw.toLowerCase();
      return lowered == 'true' || lowered == '1';
    }
    return false;
  }

  bool _isStreamingFunctionCall(FunctionCall functionCall) {
    if (functionCall.partialArgs != null || functionCall.willContinue != null) {
      return true;
    }
    return _partialArgs(functionCall).isNotEmpty || _willContinue(functionCall);
  }

  bool _isEmptyContentPart(Part part) {
    return part.functionCall == null &&
        part.functionResponse == null &&
        part.inlineData == null &&
        part.fileData == null &&
        part.executableCode == null &&
        part.codeExecutionResult == null &&
        (part.text == null || part.text!.isEmpty);
  }

  bool _hasBufferedNonProgressiveText() {
    return _thoughtText.isNotEmpty || _text.isNotEmpty;
  }

  LlmResponse _flushBufferedNonProgressiveText(LlmResponse response) {
    final List<Part> mergedParts = <Part>[
      if (_thoughtText.isNotEmpty)
        Part.text(
          _thoughtText,
          thought: true,
          thoughtSignature: _thoughtTextSignature,
        ),
      if (_text.isNotEmpty)
        Part.text(_text, thoughtSignature: _textThoughtSignature),
    ];
    final String? finishReason = _finishReason ?? response.finishReason;
    final bool success = finishReason == null || finishReason == 'STOP';
    final LlmResponse merged = LlmResponse(
      modelVersion: response.modelVersion ?? _modelVersion,
      content: Content(parts: mergedParts),
      usageMetadata: response.usageMetadata,
      citationMetadata: response.citationMetadata,
      groundingMetadata: response.groundingMetadata,
      avgLogprobs: response.avgLogprobs,
      logprobsResult: response.logprobsResult,
      cacheMetadata: response.cacheMetadata,
      interactionId: response.interactionId,
      errorCode: success ? null : finishReason,
      errorMessage: success ? null : response.errorMessage,
      finishReason: finishReason,
      partial: false,
    );
    _thoughtText = '';
    _text = '';
    _thoughtTextSignature = null;
    _textThoughtSignature = null;
    return merged;
  }

  void _appendNonProgressiveTextPart(Part part) {
    final String text = part.text ?? '';
    if (part.thought) {
      _thoughtText += text;
      if (part.thoughtSignature != null &&
          part.thoughtSignature!.isNotEmpty &&
          _thoughtTextSignature == null) {
        _thoughtTextSignature = List<int>.from(part.thoughtSignature!);
      }
      return;
    }

    _text += text;
    if (part.thoughtSignature != null &&
        part.thoughtSignature!.isNotEmpty &&
        _textThoughtSignature == null) {
      _textThoughtSignature = List<int>.from(part.thoughtSignature!);
    }
  }

  /// Processes one streamed [response] and yields incremental outputs.
  Stream<LlmResponse> processResponse(LlmResponse response) async* {
    _response = response;
    _usageMetadata = response.usageMetadata;
    _modelVersion = response.modelVersion ?? _modelVersion;
    if (response.citationMetadata != null) {
      _citationMetadata = response.citationMetadata;
    }
    if (response.groundingMetadata != null) {
      _groundingMetadata = response.groundingMetadata;
    }
    if (response.avgLogprobs != null) {
      _avgLogprobs = response.avgLogprobs;
    }
    if (response.logprobsResult != null) {
      _logprobsResult = response.logprobsResult;
    }
    if (response.cacheMetadata != null) {
      _cacheMetadata = response.cacheMetadata;
    }
    if ((response.interactionId ?? '').isNotEmpty) {
      _interactionId = response.interactionId;
    }
    if (response.finishReason != null) {
      _finishReason = response.finishReason;
    }

    final List<Part> parts = response.content?.parts ?? const <Part>[];
    for (final Part part in parts) {
      final FunctionCall? functionCall = part.functionCall;
      if (functionCall == null) {
        continue;
      }
      _sawFunctionCall = true;
      if ((functionCall.id ?? '').isNotEmpty) {
        continue;
      }
      if (_isStreamingFunctionCall(functionCall)) {
        if ((_currentFcId ?? '').isEmpty) {
          final String generatedId = flow_functions
              .generateClientFunctionCallId();
          functionCall.id = generatedId;
          _currentFcId = generatedId;
        }
        continue;
      }
      if (functionCall.name.isNotEmpty) {
        functionCall.id = flow_functions.generateClientFunctionCallId();
      }
    }

    if (_sawFunctionCall &&
        response.finishReason == 'STOP' &&
        parts.isNotEmpty &&
        parts.every(_isEmptyContentPart)) {
      return;
    }

    if (isFeatureEnabled(FeatureName.progressiveSseStreaming)) {
      for (final Part part in parts) {
        if (part.thoughtSignature != null &&
            part.thoughtSignature!.isNotEmpty) {
          _currentThoughtSignature = List<int>.from(part.thoughtSignature!);
        }
        if (part.text != null) {
          if (_currentTextBuffer.isNotEmpty &&
              part.thought != _currentTextIsThought) {
            _flushTextBufferToSequence();
          }
          if (_currentTextBuffer.isEmpty) {
            _currentTextIsThought = part.thought;
          }
          _currentTextBuffer += part.text!;
          if (part.thoughtSignature != null &&
              part.thoughtSignature!.isNotEmpty &&
              _currentTextThoughtSignature == null) {
            _currentTextThoughtSignature = List<int>.from(
              part.thoughtSignature!,
            );
          }
        } else if (part.functionCall != null) {
          _processFunctionCallPart(part);
        } else {
          _flushTextBufferToSequence();
          _partsSequence.add(part.copyWith());
        }
      }
      yield response.copyWith(partial: true);
      return;
    }

    final List<Part> nonTextParts = <Part>[];
    bool sawTextPart = false;
    for (final Part part in parts) {
      if (part.text != null) {
        sawTextPart = true;
        _appendNonProgressiveTextPart(part);
        continue;
      }
      nonTextParts.add(part.copyWith());
    }

    if (nonTextParts.isNotEmpty) {
      if (_hasBufferedNonProgressiveText()) {
        yield _flushBufferedNonProgressiveText(response);
      }
      yield response.copyWith(
        content: Content(role: response.content?.role, parts: nonTextParts),
        partial: false,
      );
      return;
    }

    if (sawTextPart) {
      yield response.copyWith(partial: true);
      return;
    }

    if (_hasBufferedNonProgressiveText() &&
        (parts.isEmpty || response.content == null)) {
      yield _flushBufferedNonProgressiveText(response);
      return;
    }
    yield response;
  }

  /// Finalizes aggregation and returns the terminal merged response.
  LlmResponse? close() {
    final LlmResponse? response = _response;
    if (response == null) {
      return null;
    }

    if (isFeatureEnabled(FeatureName.progressiveSseStreaming)) {
      _flushTextBufferToSequence();
      _flushFunctionCallToSequence();
      return _terminalResponse(
        response,
        content: _partsSequence.isEmpty
            ? null
            : Content(
                parts: _partsSequence
                    .map((Part part) => part.copyWith())
                    .toList(growable: false),
              ),
      );
    }

    final bool hasBufferedText = _text.isNotEmpty || _thoughtText.isNotEmpty;
    return _terminalResponse(
      response,
      content: hasBufferedText
          ? Content(
              parts: <Part>[
                if (_thoughtText.isNotEmpty)
                  Part.text(
                    _thoughtText,
                    thought: true,
                    thoughtSignature: _thoughtTextSignature,
                  ),
                if (_text.isNotEmpty)
                  Part.text(_text, thoughtSignature: _textThoughtSignature),
              ],
            )
          : null,
    );
  }

  LlmResponse _terminalResponse(LlmResponse response, {Content? content}) {
    final String? finishReason = _finishReason ?? response.finishReason;
    final bool success = finishReason == null || finishReason == 'STOP';
    return LlmResponse(
      modelVersion: response.modelVersion ?? _modelVersion,
      content: content,
      citationMetadata: _citationMetadata,
      groundingMetadata: _groundingMetadata,
      avgLogprobs: _avgLogprobs,
      logprobsResult: _logprobsResult,
      cacheMetadata: _cacheMetadata,
      interactionId: _interactionId,
      errorCode: response.errorCode ?? (success ? null : finishReason),
      errorMessage: response.errorMessage,
      usageMetadata: _usageMetadata,
      finishReason: finishReason,
      partial: false,
    );
  }
}

List<String> _jsonPathParts(String jsonPath) {
  String path = jsonPath.trim();
  if (path.startsWith(r'$')) {
    path = path.substring(1);
  }
  if (path.startsWith('.')) {
    path = path.substring(1);
  }
  if (path.isEmpty) {
    return const <String>[];
  }

  final List<String> parts = <String>[];
  final StringBuffer current = StringBuffer();
  int index = 0;
  while (index < path.length) {
    final String char = path[index];
    if (char == '.') {
      if (current.isNotEmpty) {
        parts.add(current.toString());
        current.clear();
      }
      index += 1;
      continue;
    }
    if (char == '[') {
      if (current.isNotEmpty) {
        parts.add(current.toString());
        current.clear();
      }
      final int start = index + 1;
      if (start >= path.length) {
        return const <String>[];
      }
      final String quote = path[start];
      if (quote != '\'' && quote != '"') {
        return const <String>[];
      }
      final StringBuffer quoted = StringBuffer();
      index = start + 1;
      bool closed = false;
      while (index < path.length) {
        final String quotedChar = path[index];
        if (quotedChar == r'\' && index + 1 < path.length) {
          quoted.write(path[index + 1]);
          index += 2;
          continue;
        }
        if (quotedChar == quote &&
            index + 1 < path.length &&
            path[index + 1] == ']') {
          closed = true;
          index += 2;
          break;
        }
        quoted.write(quotedChar);
        index += 1;
      }
      if (!closed || quoted.isEmpty) {
        return const <String>[];
      }
      parts.add(quoted.toString());
      continue;
    }
    current.write(char);
    index += 1;
  }
  if (current.isNotEmpty) {
    parts.add(current.toString());
  }
  return parts;
}

final RegExp _jsonHighSurrogateEscapeRe = RegExp(
  r'^\\u[dD][89aAbB][0-9a-fA-F]{2}$',
);
final RegExp _simpleJsonKeyRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _hugeIntLiteralRe = RegExp(r'\d{4301,}');

/// Incremental argument delta produced by [JsonPathTracker].
class PartialArg {
  /// Creates a partial argument descriptor.
  PartialArg({
    this.jsonPath,
    this.stringValue,
    this.numberValue,
    this.boolValue,
    this.nullValue,
    this.willContinue = false,
  });

  /// JSONPath location of the argument value.
  String? jsonPath;

  /// Incremental string value delta, when applicable.
  String? stringValue;

  /// Numeric value, when applicable.
  num? numberValue;

  /// Boolean value, when applicable.
  bool? boolValue;

  /// Null marker (`'NULL_VALUE'`), when applicable.
  String? nullValue;

  /// Whether additional string chunks will follow for [jsonPath].
  bool willContinue;

  /// Serializes this partial argument to a JSON map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (jsonPath != null) 'json_path': jsonPath,
      if (stringValue != null) 'string_value': stringValue,
      if (numberValue != null) 'number_value': numberValue,
      if (boolValue != null) 'bool_value': boolValue,
      if (nullValue != null) 'null_value': nullValue,
      'will_continue': willContinue,
    };
  }
}

/// Tracks JSON paths and values from a streaming JSON argument string.
class JsonPathTracker {
  /// Accumulated raw JSON string chunks.
  List<String> accumulatedParts = <String>[];

  /// Previously decoded JSON object snapshot.
  Map<String, Object?> previousDict = <String, Object?>{};

  /// Last completed JSON string that was parsed.
  String previousCompleted = '';

  /// Whether the tracker should reset before the next chunk.
  bool needReset = false;

  List<String> _stack = <String>[];
  bool _inString = false;
  bool _escaped = false;
  bool _seenOpen = false;
  String? _currentPath;
  List<Object>? _parsedCurrentPath;
  String? _openStringPath;

  /// Processes a new [chunk] of JSON and returns detected [PartialArg] deltas.
  List<PartialArg> handleChunk(String chunk) {
    if (chunk.isEmpty) {
      return <PartialArg>[];
    }

    if (needReset) {
      accumulatedParts = <String>[];
      previousCompleted = '';
      previousDict = <String, Object?>{};
      needReset = false;
      _stack = <String>[];
      _inString = false;
      _escaped = false;
      _seenOpen = false;
      _currentPath = null;
      _parsedCurrentPath = null;
      _openStringPath = null;
    }

    if (_inString &&
        !_escaped &&
        _currentPath != null &&
        _parsedCurrentPath != null &&
        !chunk.contains('"') &&
        !chunk.contains(r'\')) {
      accumulatedParts.add(chunk);
      final (Object? existingVal, bool found) = _getValueByJsonPath(
        previousDict,
        _parsedCurrentPath!,
      );
      final String newVal =
          (found && existingVal is String ? existingVal : '') + chunk;
      _setValueByJsonPath(previousDict, _parsedCurrentPath!, newVal);
      return <PartialArg>[
        PartialArg(
          jsonPath: _currentPath,
          stringValue: chunk,
          willContinue: true,
        ),
      ];
    }

    accumulatedParts.add(chunk);
    _currentPath = null;
    _parsedCurrentPath = null;

    for (int i = 0; i < chunk.length; i += 1) {
      final String char = chunk[i];
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (char == r'\') {
          _escaped = true;
        } else if (char == '"') {
          _inString = false;
        }
      } else {
        if (char == '"') {
          _inString = true;
        } else if (char == '{' || char == '[') {
          _stack.add(char);
          _seenOpen = true;
        } else if (char == '}' || char == ']') {
          if (_stack.isNotEmpty &&
              ((char == '}' && _stack.last == '{') ||
                  (char == ']' && _stack.last == '['))) {
            _stack.removeLast();
          }
        }
      }
    }

    if (_seenOpen && _stack.isEmpty && !_inString) {
      needReset = true;
    }

    final String completed = _completeJson();
    if (completed.isEmpty) {
      return <PartialArg>[];
    }

    if (completed == previousCompleted) {
      if (!_inString && _openStringPath != null) {
        final String closedPath = _openStringPath!;
        _openStringPath = null;
        return <PartialArg>[
          PartialArg(
            jsonPath: closedPath,
            stringValue: '',
            willContinue: false,
          ),
        ];
      }
      return <PartialArg>[];
    }
    previousCompleted = completed;

    if (_hugeIntLiteralRe.hasMatch(completed)) {
      return <PartialArg>[];
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(completed);
    } on StackOverflowError {
      return <PartialArg>[];
    } catch (_) {
      return <PartialArg>[];
    }

    if (decoded is! Map) {
      return <PartialArg>[];
    }
    final Map<String, Object?> currentDict = decoded.map(
      (Object? k, Object? v) => MapEntry('$k', v),
    );

    final List<PartialArg> diffs;
    try {
      diffs = _getDiff(previousDict, currentDict);
    } on _TrackerRecursionError {
      return <PartialArg>[];
    } on StackOverflowError {
      return <PartialArg>[];
    }
    previousDict = currentDict;

    if (_openStringPath != null &&
        !diffs.any((PartialArg d) => d.jsonPath == _openStringPath)) {
      diffs.insert(
        0,
        PartialArg(
          jsonPath: _openStringPath,
          stringValue: '',
          willContinue: false,
        ),
      );
      _openStringPath = null;
    }

    if (_inString) {
      for (int i = diffs.length - 1; i >= 0; i -= 1) {
        final PartialArg d = diffs[i];
        if (d.stringValue != null && d.jsonPath != null) {
          _currentPath = d.jsonPath;
          _parsedCurrentPath = _parseTrackerJsonPath(d.jsonPath!);
          _openStringPath = d.jsonPath;
          d.willContinue = true;
          break;
        }
      }
    } else {
      _currentPath = null;
      _parsedCurrentPath = null;
      _openStringPath = null;
    }

    return diffs;
  }

  String _completeJson() {
    if (!_seenOpen) {
      return '';
    }

    if (_inString) {
      if (_escaped) {
        return '';
      }
      final String prefix = accumulatedParts.join();
      final int escapeStart = prefix.length - 6;
      if (escapeStart >= 0 &&
          _jsonHighSurrogateEscapeRe.hasMatch(prefix.substring(escapeStart))) {
        int i = escapeStart - 1;
        while (i >= 0 && prefix[i] == r'\') {
          i -= 1;
        }
        if ((escapeStart - 1 - i).isEven) {
          return '';
        }
      }
      final String suffix =
          '"${_stack.reversed.map((String op) => op == '{' ? '}' : ']').join()}';
      return prefix + suffix;
    }

    String lastNonWs = '';
    int lastPartIdx = -1;
    int lastCharIdx = -1;
    for (int i = accumulatedParts.length - 1; i >= 0; i -= 1) {
      final String part = accumulatedParts[i];
      final String stripped = part.trimRight();
      if (stripped.isNotEmpty) {
        lastNonWs = stripped[stripped.length - 1];
        lastPartIdx = i;
        lastCharIdx = stripped.length - 1;
        break;
      }
    }

    if (lastNonWs.isEmpty) {
      return '';
    }

    final int codeUnit = lastNonWs.codeUnitAt(0);
    final bool isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    if (lastNonWs == ':' || isDigit) {
      return '';
    } else if ((lastNonWs == '{' && _stack.length > 1) || lastNonWs == '[') {
      return '';
    } else if (lastNonWs == ',') {
      final String prefix =
          accumulatedParts.sublist(0, lastPartIdx).join() +
          accumulatedParts[lastPartIdx].substring(0, lastCharIdx);
      final String suffix = _stack.reversed
          .map((String op) => op == '{' ? '}' : ']')
          .join();
      return prefix + suffix;
    } else {
      final String suffix = _stack.reversed
          .map((String op) => op == '{' ? '}' : ']')
          .join();
      return accumulatedParts.join() + suffix;
    }
  }

  List<PartialArg> _getDiff(
    Object? prev,
    Object? curr, [
    String path = r'$',
    int depth = 0,
  ]) {
    if (depth > _maxTrackerRecursionDepth) {
      throw const _TrackerRecursionError();
    }
    final List<PartialArg> diffs = <PartialArg>[];
    if (curr is Map && prev is Map) {
      for (final MapEntry<Object?, Object?> entry in curr.entries) {
        final String key = '${entry.key}';
        final String currPath = _appendJsonPathKey(path, key);
        if (!prev.containsKey(key)) {
          diffs.addAll(_getDiffNewValue(currPath, entry.value, depth + 1));
        } else {
          diffs.addAll(_getDiff(prev[key], entry.value, currPath, depth + 1));
        }
      }
    } else if (curr is List && prev is List) {
      for (int i = 0; i < curr.length; i += 1) {
        final String currPath = '$path[$i]';
        if (i >= prev.length) {
          diffs.addAll(_getDiffNewValue(currPath, curr[i], depth + 1));
        } else {
          diffs.addAll(_getDiff(prev[i], curr[i], currPath, depth + 1));
        }
      }
    } else if (prev != curr) {
      if (curr is String && prev is String) {
        if (curr.startsWith(prev)) {
          final String delta = curr.substring(prev.length);
          if (delta.isNotEmpty) {
            diffs.add(
              PartialArg(
                jsonPath: path,
                stringValue: delta,
                willContinue: false,
              ),
            );
          }
        } else {
          diffs.add(
            PartialArg(jsonPath: path, stringValue: curr, willContinue: false),
          );
        }
      } else {
        diffs.addAll(_getDiffNewValue(path, curr, depth + 1));
      }
    }
    return diffs;
  }

  List<PartialArg> _getDiffNewValue(
    String path,
    Object? val, [
    int depth = 0,
  ]) {
    if (depth > _maxTrackerRecursionDepth) {
      throw const _TrackerRecursionError();
    }
    final List<PartialArg> diffs = <PartialArg>[];
    if (val is Map && val.isNotEmpty) {
      for (final MapEntry<Object?, Object?> entry in val.entries) {
        diffs.addAll(
          _getDiffNewValue(
            _appendJsonPathKey(path, '${entry.key}'),
            entry.value,
            depth + 1,
          ),
        );
      }
    } else if (val is List && val.isNotEmpty) {
      for (int i = 0; i < val.length; i += 1) {
        diffs.addAll(_getDiffNewValue('$path[$i]', val[i], depth + 1));
      }
    } else {
      diffs.add(_createPartialArg(path, val));
    }
    return diffs;
  }

  PartialArg _createPartialArg(String path, Object? val) {
    if (val is String) {
      return PartialArg(jsonPath: path, stringValue: val, willContinue: false);
    } else if (val is num) {
      if (!val.toDouble().isFinite) {
        return PartialArg(jsonPath: path, willContinue: false);
      }
      return PartialArg(jsonPath: path, numberValue: val, willContinue: false);
    } else if (val is BigInt) {
      final double asDouble = val.toDouble();
      if (!asDouble.isFinite) {
        return PartialArg(jsonPath: path, willContinue: false);
      }
      return PartialArg(
        jsonPath: path,
        numberValue: asDouble,
        willContinue: false,
      );
    } else if (val is bool) {
      return PartialArg(jsonPath: path, boolValue: val, willContinue: false);
    } else if (val == null) {
      return PartialArg(
        jsonPath: path,
        nullValue: 'NULL_VALUE',
        willContinue: false,
      );
    }
    return PartialArg(jsonPath: path, willContinue: false);
  }
}

const int _maxTrackerRecursionDepth = 500;

class _TrackerRecursionError implements Exception {
  const _TrackerRecursionError();
}

String _appendJsonPathKey(String basePath, String key) {
  if (_simpleJsonKeyRe.hasMatch(key)) {
    return '$basePath.$key';
  }
  final String escaped = key
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return "$basePath['$escaped']";
}

List<Object> _parseTrackerJsonPath(String jsonPath) {
  final List<String> rawParts = _jsonPathParts(jsonPath);
  final List<Object> parsed = <Object>[];
  final RegExp arrayIndexRe = RegExp(r'^([^\[\]]+)\[(\d+)\]$');
  for (final String part in rawParts) {
    final Match? match = arrayIndexRe.firstMatch(part);
    if (match != null) {
      parsed.add(match.group(1)!);
      parsed.add(int.parse(match.group(2)!));
    } else {
      parsed.add(part);
    }
  }
  return parsed;
}

(Object?, bool) _getValueByJsonPath(
  Map<String, Object?> root,
  List<Object> path,
) {
  Object? current = root;
  for (final Object segment in path) {
    if (segment is String && current is Map) {
      if (!current.containsKey(segment)) {
        return (null, false);
      }
      current = current[segment];
    } else if (segment is int && current is List) {
      if (segment < 0 || segment >= current.length) {
        return (null, false);
      }
      current = current[segment];
    } else {
      return (null, false);
    }
  }
  return (current, true);
}

void _setValueByJsonPath(
  Map<String, Object?> root,
  List<Object> path,
  Object? value,
) {
  if (path.isEmpty) {
    return;
  }
  Object? current = root;
  for (int i = 0; i < path.length - 1; i += 1) {
    final Object segment = path[i];
    if (segment is String && current is Map) {
      current = current[segment];
    } else if (segment is int && current is List) {
      current = current[segment];
    } else {
      return;
    }
  }
  final Object last = path.last;
  if (last is String && current is Map) {
    current[last] = value;
  } else if (last is int && current is List && last < current.length) {
    current[last] = value;
  }
}
