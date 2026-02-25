import 'dart:convert';

import '../types/content.dart';
import 'gemini_rest_api_client.dart';
import 'llm_request.dart';
import 'llm_response.dart';

Map<String, Object?>? convertPartToInteractionContent(Part part) {
  if (part.text != null) {
    return <String, Object?>{
      'type': 'text',
      'text': part.text,
      if (part.thought) 'thought': true,
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.functionCall != null) {
    final Map<String, Object?> arguments = Map<String, Object?>.from(
      part.functionCall!.args,
    );
    if (part.functionCall!.partialArgs != null) {
      arguments['partial_args'] = part.functionCall!.partialArgs
          ?.map(
            (Map<String, Object?> value) => Map<String, Object?>.from(value),
          )
          .toList(growable: false);
    }
    if (part.functionCall!.willContinue != null) {
      arguments['will_continue'] = part.functionCall!.willContinue;
    }
    return <String, Object?>{
      'type': 'function_call',
      'id': part.functionCall!.id ?? '',
      'name': part.functionCall!.name,
      'arguments': arguments,
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.functionResponse != null) {
    final Object response = part.functionResponse!.response;
    return <String, Object?>{
      'type': 'function_result',
      'name': part.functionResponse!.name,
      'call_id': part.functionResponse!.id ?? '',
      'result': response,
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.inlineData != null) {
    return <String, Object?>{
      'type': _contentTypeFromMimeType(part.inlineData!.mimeType),
      'mime_type': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.fileData != null) {
    final String mimeType = part.fileData!.mimeType ?? '';
    return <String, Object?>{
      'type': _contentTypeFromMimeType(mimeType),
      'uri': part.fileData!.fileUri,
      'mime_type': mimeType,
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.codeExecutionResult != null) {
    final Map<String, Object?> resultMap = _asMap(part.codeExecutionResult);
    final String output =
        _stringValue(resultMap['output']) ??
        _stringValue(resultMap['result']) ??
        '${part.codeExecutionResult}';
    final String? outcome = _stringValue(resultMap['outcome']);
    final bool isError =
        outcome == 'OUTCOME_FAILED' || outcome == 'OUTCOME_DEADLINE_EXCEEDED';
    return <String, Object?>{
      'type': 'code_execution_result',
      'call_id': '',
      'result': output,
      'is_error': isError,
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.executableCode != null) {
    final Map<String, Object?> codeMap = _asMap(part.executableCode);
    return <String, Object?>{
      'type': 'code_execution_call',
      'id': '',
      'arguments': <String, Object?>{
        'code': _stringValue(codeMap['code']) ?? '${part.executableCode}',
        'language': _stringValue(codeMap['language']) ?? 'PYTHON',
      },
      if (part.thoughtSignature != null)
        'thought_signature': base64Encode(part.thoughtSignature!),
    };
  }
  if (part.thought) {
    return <String, Object?>{
      'type': 'thought',
      if (part.thoughtSignature != null)
        'signature': base64Encode(part.thoughtSignature!),
    };
  }
  return null;
}

Map<String, Object?> convertContentToTurn(Content content) {
  final List<Map<String, Object?>> converted = content.parts
      .map(convertPartToInteractionContent)
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  return <String, Object?>{
    'role': content.role ?? 'user',
    'content': converted,
  };
}

List<Map<String, Object?>> convertContentsToTurns(List<Content> contents) {
  return contents
      .map(convertContentToTurn)
      .where((Map<String, Object?> turn) {
        final Object? content = turn['content'];
        return content is List && content.isNotEmpty;
      })
      .toList(growable: false);
}

List<Map<String, Object?>> convertToolsConfigToInteractionsFormat(
  GenerateContentConfig config,
) {
  final List<ToolDeclaration>? tools = config.tools;
  if (tools == null || tools.isEmpty) {
    return const <Map<String, Object?>>[];
  }

  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  for (final ToolDeclaration tool in tools) {
    for (final FunctionDeclaration function in tool.functionDeclarations) {
      output.add(<String, Object?>{
        'type': 'function',
        'name': function.name,
        if (function.description.isNotEmpty)
          'description': function.description,
        if (function.parameters.isNotEmpty) 'parameters': function.parameters,
      });
    }
    if (tool.googleSearch != null || tool.googleSearchRetrieval != null) {
      output.add(<String, Object?>{'type': 'google_search'});
    }
    if (tool.codeExecution != null) {
      output.add(<String, Object?>{'type': 'code_execution'});
    }
    if (tool.urlContext != null) {
      output.add(<String, Object?>{'type': 'url_context'});
    }
    if (tool.computerUse != null) {
      output.add(<String, Object?>{'type': 'computer_use'});
    }
  }
  return output;
}

Map<String, Object?> buildGenerationConfig(GenerateContentConfig config) {
  final Map<String, Object?> generationConfig = <String, Object?>{};
  if (config.temperature != null) {
    generationConfig['temperature'] = config.temperature;
  }
  if (config.topP != null) {
    generationConfig['top_p'] = config.topP;
  }
  if (config.topK != null) {
    generationConfig['top_k'] = config.topK;
  }
  if (config.maxOutputTokens != null) {
    generationConfig['max_output_tokens'] = config.maxOutputTokens;
  }
  if (config.stopSequences.isNotEmpty) {
    generationConfig['stop_sequences'] = List<String>.from(
      config.stopSequences,
    );
  }
  if (config.presencePenalty != null) {
    generationConfig['presence_penalty'] = config.presencePenalty;
  }
  if (config.frequencyPenalty != null) {
    generationConfig['frequency_penalty'] = config.frequencyPenalty;
  }
  return generationConfig;
}

String? extractSystemInstruction(GenerateContentConfig config) {
  final String? systemInstruction = config.systemInstruction;
  if (systemInstruction == null || systemInstruction.isEmpty) {
    return null;
  }
  return systemInstruction;
}

List<Content> getLatestUserContents(List<Content> contents) {
  if (contents.isEmpty) {
    return const <Content>[];
  }

  final List<Content> latestUserContents = <Content>[];
  for (int index = contents.length - 1; index >= 0; index -= 1) {
    final Content content = contents[index];
    if (content.role == 'user') {
      latestUserContents.insert(0, content);
      continue;
    }
    break;
  }

  bool hasFunctionResult = false;
  for (final Content content in latestUserContents) {
    for (final Part part in content.parts) {
      if (part.functionResponse != null) {
        hasFunctionResult = true;
        break;
      }
    }
    if (hasFunctionResult) {
      break;
    }
  }

  if (!hasFunctionResult || latestUserContents.length == contents.length) {
    return latestUserContents;
  }

  final int userStartIndex = contents.length - latestUserContents.length;
  if (userStartIndex <= 0) {
    return latestUserContents;
  }

  final Content preceding = contents[userStartIndex - 1];
  if (preceding.role != 'model') {
    return latestUserContents;
  }
  final bool hasFunctionCall = preceding.parts.any(
    (Part part) => part.functionCall != null,
  );
  if (!hasFunctionCall) {
    return latestUserContents;
  }
  return <Content>[preceding, ...latestUserContents];
}

LlmResponse convertInteractionToLlmResponse(
  Map<String, Object?> interaction, {
  String? fallbackModelVersion,
}) {
  final String status = _stringValue(interaction['status']) ?? '';
  final String? interactionId =
      _stringValue(interaction['id']) ??
      _stringValue(interaction['interaction_id']) ??
      _stringValue(interaction['interactionId']);
  final String? modelVersion =
      _stringValue(interaction['model']) ?? fallbackModelVersion;

  if (status == 'failed') {
    final Map<String, Object?> error = _asMap(interaction['error']);
    return LlmResponse(
      modelVersion: modelVersion,
      errorCode: _stringValue(error['code']) ?? 'UNKNOWN_ERROR',
      errorMessage: _stringValue(error['message']) ?? 'Unknown error.',
      interactionId: interactionId,
      turnComplete: true,
    );
  }

  final List<Object?> outputsRaw = _asList(interaction['outputs']);
  final List<Part> parts = outputsRaw
      .map(_asMap)
      .map(convertInteractionOutputToPart)
      .whereType<Part>()
      .toList(growable: false);

  final Map<String, Object?> usage = _asMap(interaction['usage']);
  Object? usageMetadata;
  if (usage.isNotEmpty) {
    final int inputTokens = _intValue(usage['total_input_tokens']) ?? 0;
    final int outputTokens = _intValue(usage['total_output_tokens']) ?? 0;
    usageMetadata = <String, Object?>{
      'promptTokenCount': inputTokens,
      'candidatesTokenCount': outputTokens,
      'totalTokenCount': inputTokens + outputTokens,
    };
  }

  final bool turnComplete =
      status == 'completed' || status == 'requires_action';
  final String? finishReason = turnComplete ? 'STOP' : null;

  return LlmResponse(
    modelVersion: modelVersion,
    content: parts.isEmpty ? null : Content(role: 'model', parts: parts),
    usageMetadata: usageMetadata,
    finishReason: finishReason,
    turnComplete: turnComplete,
    interactionId: interactionId,
  );
}

Part? convertInteractionOutputToPart(Map<String, Object?> output) {
  final String? outputType = _stringValue(output['type']);
  if (outputType == null || outputType.isEmpty) {
    return null;
  }

  if (outputType == 'text') {
    return Part.text(_stringValue(output['text']) ?? '');
  }
  if (outputType == 'function_call') {
    final List<int>? thoughtSignature = _decodeThoughtSignature(
      output['thought_signature'],
    );
    return Part.fromFunctionCall(
      id: _stringValue(output['id']),
      name: _stringValue(output['name']) ?? '',
      args: _asMap(output['arguments']),
      thoughtSignature: thoughtSignature,
    );
  }
  if (outputType == 'function_result') {
    final Object? rawResult = output['result'];
    final JsonMap response = _coerceFunctionResult(rawResult);
    return Part.fromFunctionResponse(
      name: _stringValue(output['name']) ?? '',
      id: _stringValue(output['call_id']),
      response: response,
    );
  }
  if (outputType == 'image' ||
      outputType == 'audio' ||
      outputType == 'video' ||
      outputType == 'document') {
    final String mimeType = _stringValue(output['mime_type']) ?? '';
    final List<int>? bytes = _decodeBytes(output['data']);
    if (bytes != null) {
      return Part.fromInlineData(mimeType: mimeType, data: bytes);
    }
    final String? uri = _stringValue(output['uri']);
    if (uri != null && uri.isNotEmpty) {
      return Part.fromFileData(fileUri: uri, mimeType: mimeType);
    }
    return null;
  }
  if (outputType == 'code_execution_result') {
    final String result = _stringValue(output['result']) ?? '';
    final bool isError = output['is_error'] == true;
    return Part(
      codeExecutionResult: <String, Object?>{
        'output': result,
        'outcome': isError ? 'OUTCOME_FAILED' : 'OUTCOME_OK',
      },
    );
  }
  if (outputType == 'code_execution_call') {
    final Map<String, Object?> args = _asMap(output['arguments']);
    return Part(
      executableCode: <String, Object?>{
        'code': _stringValue(args['code']) ?? '',
        'language': _stringValue(args['language']) ?? 'PYTHON',
      },
    );
  }
  if (outputType == 'google_search_result') {
    final List<Object?> rows = _asList(output['result']);
    final List<String> lines = rows.map((Object? value) => '$value').toList();
    if (lines.isEmpty) {
      return null;
    }
    return Part.text(lines.join('\n'));
  }
  return null;
}

LlmResponse? convertInteractionEventToLlmResponse(
  Map<String, Object?> event,
  List<Part> aggregatedParts, {
  required String? interactionId,
  String? fallbackModelVersion,
}) {
  final String? eventType = _stringValue(
    event['event_type'] ?? event['eventType'],
  );

  if (eventType == null || eventType.isEmpty) {
    if (_looksLikeInteraction(event)) {
      return convertInteractionToLlmResponse(
        event,
        fallbackModelVersion: fallbackModelVersion,
      );
    }
    final Map<String, Object?> interaction = _asMap(event['interaction']);
    if (interaction.isNotEmpty) {
      return convertInteractionToLlmResponse(
        interaction,
        fallbackModelVersion: fallbackModelVersion,
      );
    }
    return null;
  }

  if (eventType == 'content.delta') {
    final Map<String, Object?> delta = _asMap(event['delta']);
    if (delta.isEmpty) {
      return null;
    }
    final String? deltaType = _stringValue(delta['type']);
    if (deltaType == 'text') {
      final String text = _stringValue(delta['text']) ?? '';
      if (text.isEmpty) {
        return null;
      }
      final Part part = Part.text(text);
      aggregatedParts.add(part.copyWith());
      return LlmResponse(
        modelVersion: fallbackModelVersion,
        content: Content(role: 'model', parts: <Part>[part]),
        partial: true,
        turnComplete: false,
        interactionId: interactionId,
      );
    }
    if (deltaType == 'function_call') {
      final Part? part = convertInteractionOutputToPart(delta);
      if (part != null) {
        aggregatedParts.add(part.copyWith());
      }
      // Interaction ID can arrive later, so only include in final aggregate.
      return null;
    }
    if (deltaType == 'image' ||
        deltaType == 'audio' ||
        deltaType == 'video' ||
        deltaType == 'document') {
      final Part? part = convertInteractionOutputToPart(delta);
      if (part == null) {
        return null;
      }
      aggregatedParts.add(part.copyWith());
      return LlmResponse(
        modelVersion: fallbackModelVersion,
        content: Content(role: 'model', parts: <Part>[part]),
        partial: false,
        turnComplete: false,
        interactionId: interactionId,
      );
    }
    return null;
  }

  if (eventType == 'content.stop') {
    if (aggregatedParts.isEmpty) {
      return null;
    }
    return LlmResponse(
      modelVersion: fallbackModelVersion,
      content: Content(
        role: 'model',
        parts: aggregatedParts.map((Part part) => part.copyWith()).toList(),
      ),
      partial: false,
      turnComplete: false,
      interactionId: interactionId,
    );
  }

  if (eventType == 'interaction' || eventType == 'interaction.complete') {
    final Map<String, Object?> interaction = _asMap(event['interaction']);
    if (interaction.isNotEmpty) {
      return convertInteractionToLlmResponse(
        interaction,
        fallbackModelVersion: fallbackModelVersion,
      );
    }
    return convertInteractionToLlmResponse(
      event,
      fallbackModelVersion: fallbackModelVersion,
    );
  }

  if (eventType == 'interaction.status_update') {
    final String status = _stringValue(event['status']) ?? '';
    if (status == 'completed' || status == 'requires_action') {
      return LlmResponse(
        modelVersion: fallbackModelVersion,
        content: aggregatedParts.isEmpty
            ? null
            : Content(
                role: 'model',
                parts: aggregatedParts
                    .map((Part part) => part.copyWith())
                    .toList(growable: false),
              ),
        partial: false,
        turnComplete: true,
        finishReason: 'STOP',
        interactionId: interactionId,
      );
    }
    if (status == 'failed') {
      final Map<String, Object?> error = _asMap(event['error']);
      return LlmResponse(
        modelVersion: fallbackModelVersion,
        errorCode: _stringValue(error['code']) ?? 'UNKNOWN_ERROR',
        errorMessage: _stringValue(error['message']) ?? 'Unknown error.',
        turnComplete: true,
        interactionId: interactionId,
      );
    }
    return null;
  }

  if (eventType == 'error') {
    return LlmResponse(
      modelVersion: fallbackModelVersion,
      errorCode: _stringValue(event['code']) ?? 'UNKNOWN_ERROR',
      errorMessage: _stringValue(event['message']) ?? 'Unknown error.',
      turnComplete: true,
      interactionId: interactionId,
    );
  }

  return null;
}

Stream<LlmResponse> generateContentViaInteractions({
  required LlmRequest llmRequest,
  required bool stream,
  Stream<LlmResponse> Function(LlmRequest request, {required bool stream})?
  invoker,
  GeminiRestTransport? restTransport,
  String? apiKey,
  String? baseUrl,
  String apiVersion = 'v1beta',
  Map<String, String>? headers,
  HttpRetryOptions? retryOptions,
}) async* {
  if (invoker != null) {
    yield* invoker(llmRequest, stream: stream);
    return;
  }
  if (restTransport == null) {
    throw ArgumentError(
      'restTransport is required when interactions invoker is not provided.',
    );
  }
  if (apiKey == null || apiKey.isEmpty) {
    throw ArgumentError(
      'apiKey is required when interactions invoker is not provided.',
    );
  }
  final String? model = llmRequest.model;
  if (model == null || model.isEmpty) {
    throw ArgumentError('llmRequest.model must be set for interactions API.');
  }

  List<Content> contents = llmRequest.contents;
  if ((llmRequest.previousInteractionId ?? '').isNotEmpty &&
      contents.isNotEmpty) {
    contents = getLatestUserContents(contents);
  }

  final List<Map<String, Object?>> inputTurns = convertContentsToTurns(
    contents,
  );
  final List<Map<String, Object?>> interactionTools =
      convertToolsConfigToInteractionsFormat(llmRequest.config);
  final String? systemInstruction = extractSystemInstruction(llmRequest.config);
  final Map<String, Object?> generationConfig = buildGenerationConfig(
    llmRequest.config,
  );

  final Map<String, Object?> payload = <String, Object?>{
    'model': model,
    'input': inputTurns,
    'stream': stream,
    if (systemInstruction != null) 'system_instruction': systemInstruction,
    if (interactionTools.isNotEmpty) 'tools': interactionTools,
    if (generationConfig.isNotEmpty) 'generation_config': generationConfig,
    if ((llmRequest.previousInteractionId ?? '').isNotEmpty)
      'previous_interaction_id': llmRequest.previousInteractionId,
  };

  if (stream) {
    final List<Part> aggregatedParts = <Part>[];
    String? currentInteractionId;
    bool emittedTerminal = false;
    await for (final Map<String, Object?> event
        in restTransport.streamCreateInteraction(
          apiKey: apiKey,
          payload: payload,
          baseUrl: baseUrl,
          apiVersion: apiVersion,
          headers: headers,
          retryOptions: retryOptions,
        )) {
      currentInteractionId ??=
          _stringValue(event['id']) ??
          _stringValue(event['interaction_id']) ??
          _stringValue(event['interactionId']) ??
          _stringValue(_asMap(event['interaction'])['id']);

      final LlmResponse? response = convertInteractionEventToLlmResponse(
        event,
        aggregatedParts,
        interactionId: currentInteractionId,
        fallbackModelVersion: model,
      );
      if (response == null) {
        continue;
      }
      response.interactionId ??= currentInteractionId;
      currentInteractionId ??= response.interactionId;
      emittedTerminal = emittedTerminal || response.turnComplete == true;
      yield response;
    }

    if (!emittedTerminal && aggregatedParts.isNotEmpty) {
      yield LlmResponse(
        modelVersion: model,
        content: Content(
          role: 'model',
          parts: aggregatedParts
              .map((Part part) => part.copyWith())
              .toList(growable: false),
        ),
        partial: false,
        turnComplete: true,
        finishReason: 'STOP',
        interactionId: currentInteractionId,
      );
    }
    return;
  }

  final Map<String, Object?> interaction = await restTransport
      .createInteraction(
        apiKey: apiKey,
        payload: payload,
        baseUrl: baseUrl,
        apiVersion: apiVersion,
        headers: headers,
        retryOptions: retryOptions,
      );
  yield convertInteractionToLlmResponse(
    interaction,
    fallbackModelVersion: model,
  );
}

String _contentTypeFromMimeType(String? mimeType) {
  final String value = (mimeType ?? '').toLowerCase();
  if (value.startsWith('image/')) {
    return 'image';
  }
  if (value.startsWith('audio/')) {
    return 'audio';
  }
  if (value.startsWith('video/')) {
    return 'video';
  }
  return 'document';
}

bool _looksLikeInteraction(Map<String, Object?> value) {
  return value.containsKey('status') || value.containsKey('outputs');
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return const <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  if (text.isEmpty) {
    return null;
  }
  return text;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

List<int>? _decodeBytes(Object? value) {
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    final List<int> bytes = <int>[];
    for (final Object? item in value) {
      if (item is num) {
        bytes.add(item.toInt());
      }
    }
    return bytes.isEmpty ? null : bytes;
  }
  if (value is String && value.isNotEmpty) {
    try {
      return base64Decode(value);
    } catch (_) {
      return utf8.encode(value);
    }
  }
  return null;
}

List<int>? _decodeThoughtSignature(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    final List<int> bytes = <int>[];
    for (final Object? item in value) {
      if (item is num) {
        bytes.add(item.toInt());
      }
    }
    return bytes.isEmpty ? null : bytes;
  }
  final String? encoded = _stringValue(value);
  if (encoded == null || encoded.isEmpty) {
    return null;
  }
  try {
    return base64Decode(encoded);
  } catch (_) {
    try {
      return base64Url.decode(base64Url.normalize(encoded));
    } catch (_) {
      return null;
    }
  }
}

JsonMap _coerceFunctionResult(Object? value) {
  if (value is JsonMap) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  if (value is String) {
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? item) => MapEntry('$key', item),
        );
      }
    } catch (_) {
      return <String, dynamic>{'result': value};
    }
    return <String, dynamic>{'result': value};
  }
  if (value == null) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{'result': value};
}
