/// Shared utility and helper APIs for ADK runtime behavior.
library;

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
    if (partialArg['string_value'] != null) {
      final String chunk = '${partialArg['string_value']}';
      final Object? existing = _getValueByJsonPath(jsonPath);
      if (existing is String) {
        return (existing + chunk, true);
      }
      return (chunk, true);
    }
    if (partialArg['number_value'] != null) {
      return (partialArg['number_value'], true);
    }
    if (partialArg['bool_value'] != null) {
      return (partialArg['bool_value'], true);
    }
    if (partialArg.containsKey('null_value')) {
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
      if (part.thoughtSignature != null) {
        if (_thoughtTextSignature == null) {
          _thoughtTextSignature = List<int>.from(part.thoughtSignature!);
        } else if (!_sameThoughtSignature(
          _thoughtTextSignature,
          part.thoughtSignature,
        )) {
          _thoughtTextSignature = null;
        }
      }
      return;
    }

    _text += text;
    if (part.thoughtSignature != null) {
      if (_textThoughtSignature == null) {
        _textThoughtSignature = List<int>.from(part.thoughtSignature!);
      } else if (!_sameThoughtSignature(
        _textThoughtSignature,
        part.thoughtSignature,
      )) {
        _textThoughtSignature = null;
      }
    }
  }

  bool _sameThoughtSignature(List<int>? left, List<int>? right) {
    if (left == null && right == null) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
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
              (part.thought != _currentTextIsThought ||
                  !_sameThoughtSignature(
                    part.thoughtSignature,
                    _currentTextThoughtSignature,
                  ))) {
            _flushTextBufferToSequence();
          }
          if (_currentTextBuffer.isEmpty) {
            _currentTextIsThought = part.thought;
            _currentTextThoughtSignature = part.thoughtSignature == null
                ? null
                : List<int>.from(part.thoughtSignature!);
          }
          _currentTextBuffer += part.text!;
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
    if (isFeatureEnabled(FeatureName.progressiveSseStreaming)) {
      if (_response == null) {
        return null;
      }
      _flushTextBufferToSequence();
      _flushFunctionCallToSequence();
      if (_partsSequence.isEmpty) {
        return null;
      }

      final String? finishReason = _finishReason ?? _response!.finishReason;
      final bool success = finishReason == null || finishReason == 'STOP';
      return LlmResponse(
        modelVersion: _response!.modelVersion ?? _modelVersion,
        content: Content(
          parts: _partsSequence
              .map((Part part) => part.copyWith())
              .toList(growable: false),
        ),
        citationMetadata: _citationMetadata,
        groundingMetadata: _groundingMetadata,
        avgLogprobs: _avgLogprobs,
        logprobsResult: _logprobsResult,
        cacheMetadata: _cacheMetadata,
        interactionId: _interactionId,
        errorCode: success ? null : finishReason,
        errorMessage: success ? null : _response!.errorMessage,
        usageMetadata: _usageMetadata,
        finishReason: finishReason,
        partial: false,
      );
    }

    final bool hasBufferedText = _text.isNotEmpty || _thoughtText.isNotEmpty;
    if (!hasBufferedText || _response == null) {
      return null;
    }

    final String? finishReason = _finishReason ?? _response!.finishReason;
    final bool success = finishReason == null || finishReason == 'STOP';
    return LlmResponse(
      modelVersion: _response!.modelVersion ?? _modelVersion,
      content: Content(
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
      ),
      citationMetadata: _citationMetadata,
      groundingMetadata: _groundingMetadata,
      avgLogprobs: _avgLogprobs,
      logprobsResult: _logprobsResult,
      cacheMetadata: _cacheMetadata,
      interactionId: _interactionId,
      errorCode: success ? null : finishReason,
      errorMessage: success ? null : _response!.errorMessage,
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
