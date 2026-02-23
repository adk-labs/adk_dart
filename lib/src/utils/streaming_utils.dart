import '../features/_feature_registry.dart';
import '../models/llm_response.dart';
import '../types/content.dart';

class StreamingResponseAggregator {
  String _text = '';
  String _thoughtText = '';
  Object? _usageMetadata;
  Object? _citationMetadata;
  LlmResponse? _response;

  final List<Part> _partsSequence = <Part>[];
  String _currentTextBuffer = '';
  bool? _currentTextIsThought;
  String? _finishReason;

  String? _currentFcName;
  Map<String, Object?> _currentFcArgs = <String, Object?>{};
  String? _currentFcId;

  void _flushTextBufferToSequence() {
    if (_currentTextBuffer.isEmpty) {
      return;
    }
    _partsSequence.add(
      Part.text(_currentTextBuffer, thought: _currentTextIsThought ?? false),
    );
    _currentTextBuffer = '';
    _currentTextIsThought = null;
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
      ),
    );
    _currentFcName = null;
    _currentFcArgs = <String, Object?>{};
    _currentFcId = null;
  }

  void _processStreamingFunctionCall(FunctionCall functionCall) {
    if (functionCall.name.isNotEmpty) {
      _currentFcName = functionCall.name;
    }
    if (functionCall.id != null && functionCall.id!.isNotEmpty) {
      _currentFcId = functionCall.id;
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
      _processStreamingFunctionCall(functionCall);
      return;
    }

    if (functionCall.name.isEmpty) {
      return;
    }

    _flushTextBufferToSequence();
    _partsSequence.add(part.copyWith());
  }

  List<Map<String, Object?>> _partialArgs(FunctionCall functionCall) {
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
    return _partialArgs(functionCall).isNotEmpty || _willContinue(functionCall);
  }

  Stream<LlmResponse> processResponse(LlmResponse response) async* {
    _response = response;
    _usageMetadata = response.usageMetadata;
    if (response.citationMetadata != null) {
      _citationMetadata = response.citationMetadata;
    }
    if (response.finishReason != null) {
      _finishReason = response.finishReason;
    }

    if (isFeatureEnabled(FeatureName.progressiveSseStreaming)) {
      final List<Part> parts = response.content?.parts ?? const <Part>[];
      for (final Part part in parts) {
        if (part.text != null) {
          if (_currentTextBuffer.isNotEmpty &&
              part.thought != _currentTextIsThought) {
            _flushTextBufferToSequence();
          }
          if (_currentTextBuffer.isEmpty) {
            _currentTextIsThought = part.thought;
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
      } else {
        _text += text;
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
        if (_thoughtText.isNotEmpty) Part.text(_thoughtText, thought: true),
        if (_text.isNotEmpty) Part.text(_text),
      ];
      yield LlmResponse(
        content: Content(parts: mergedParts),
        usageMetadata: response.usageMetadata,
      );
      _thoughtText = '';
      _text = '';
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
        content: Content(
          parts: _partsSequence
              .map((Part part) => part.copyWith())
              .toList(growable: false),
        ),
        citationMetadata: _citationMetadata,
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
      content: Content(
        parts: <Part>[
          if (_thoughtText.isNotEmpty) Part.text(_thoughtText, thought: true),
          if (_text.isNotEmpty) Part.text(_text),
        ],
      ),
      citationMetadata: _citationMetadata,
      errorCode: success ? null : finishReason,
      errorMessage: success ? null : _response!.errorMessage,
      usageMetadata: _usageMetadata,
    );
  }
}
