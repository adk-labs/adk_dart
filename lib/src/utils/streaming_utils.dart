import '../features/_feature_registry.dart';
import '../models/llm_response.dart';
import '../types/content.dart';

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
  String? _finishReason;

  String? _currentFcName;
  Map<String, Object?> _currentFcArgs = <String, Object?>{};
  String? _currentFcId;
  List<int>? _currentFcThoughtSignature;

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
    final String path = jsonPath.startsWith(r'$.')
        ? jsonPath.substring(2)
        : jsonPath;
    if (path.isEmpty) {
      return null;
    }

    Object? current = _currentFcArgs;
    for (final String part in path.split('.')) {
      if (current is! Map<String, Object?> || !current.containsKey(part)) {
        return null;
      }
      current = current[part];
    }
    return current;
  }

  void _setValueByJsonPath(String jsonPath, Object? value) {
    final String path = jsonPath.startsWith(r'$.')
        ? jsonPath.substring(2)
        : jsonPath;
    if (path.isEmpty) {
      return;
    }

    final List<String> pathParts = path.split('.');
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

    if (_isStreamingFunctionCall(functionCall)) {
      _processStreamingFunctionCall(functionCall, part);
      return;
    }

    if (functionCall.name.isEmpty) {
      return;
    }

    _flushTextBufferToSequence();
    _partsSequence.add(part.copyWith());
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

    if (isFeatureEnabled(FeatureName.progressiveSseStreaming)) {
      final List<Part> parts = response.content?.parts ?? const <Part>[];
      for (final Part part in parts) {
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

    final List<Part> parts = response.content?.parts ?? const <Part>[];
    if (parts.isNotEmpty && parts.first.text != null) {
      final Part first = parts.first;
      final String text = first.text ?? '';
      if (first.thought) {
        _thoughtText += text;
        if (first.thoughtSignature != null) {
          if (_thoughtTextSignature == null) {
            _thoughtTextSignature = List<int>.from(first.thoughtSignature!);
          } else if (!_sameThoughtSignature(
            _thoughtTextSignature,
            first.thoughtSignature,
          )) {
            _thoughtTextSignature = null;
          }
        }
      } else {
        _text += text;
        if (first.thoughtSignature != null) {
          if (_textThoughtSignature == null) {
            _textThoughtSignature = List<int>.from(first.thoughtSignature!);
          } else if (!_sameThoughtSignature(
            _textThoughtSignature,
            first.thoughtSignature,
          )) {
            _textThoughtSignature = null;
          }
        }
      }
      yield response.copyWith(partial: true);
      return;
    }

    final bool hasBufferedText = _thoughtText.isNotEmpty || _text.isNotEmpty;
    final bool hasInlineDataFirst =
        parts.isNotEmpty && parts.first.inlineData != null;
    if (hasBufferedText &&
        (parts.isEmpty || response.content == null || !hasInlineDataFirst)) {
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
      yield LlmResponse(
        modelVersion: response.modelVersion ?? _modelVersion,
        content: Content(parts: mergedParts),
        usageMetadata: response.usageMetadata,
        citationMetadata: response.citationMetadata,
        groundingMetadata: response.groundingMetadata,
        avgLogprobs: response.avgLogprobs,
        logprobsResult: response.logprobsResult,
        cacheMetadata: response.cacheMetadata,
        interactionId: response.interactionId,
      );
      _thoughtText = '';
      _text = '';
      _thoughtTextSignature = null;
      _textThoughtSignature = null;
    }
    yield response;
  }

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

    final String? finishReason = _response!.finishReason;
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
