part of 'lite_llm.dart';

bool _partHasPayload(Part part) {
  if (part.text != null && part.text!.isNotEmpty) {
    return true;
  }
  if (part.inlineData != null && part.inlineData!.data.isNotEmpty) {
    return true;
  }
  if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
    return true;
  }
  if (part.functionResponse != null) {
    return true;
  }
  return false;
}

void _appendFallbackUserContentIfMissing(LlmRequest request) {
  for (int i = request.contents.length - 1; i >= 0; i -= 1) {
    final Content content = request.contents[i];
    if (content.role != 'user') {
      continue;
    }
    if (content.parts.any(_partHasPayload)) {
      return;
    }
    content.parts.add(Part.text(_systemInstructionFallbackText));
    return;
  }

  request.contents.add(Content.userText(_systemInstructionFallbackText));
}

String? _finishReasonToErrorMessage(String finishReason) {
  if (finishReason == 'STOP') {
    return null;
  }
  if (finishReason == 'MAX_TOKENS') {
    return 'Maximum tokens reached';
  }
  return 'Finished with $finishReason';
}

bool _malformedArgsOutrankProvider({
  required String? responseFinishReason,
  required String? providerFinishReason,
}) {
  return responseFinishReason == 'MALFORMED_FUNCTION_CALL' &&
      (providerFinishReason == null ||
          providerFinishReason == 'STOP' ||
          providerFinishReason == 'OTHER');
}

void _applyProviderFinishReason(
  LlmResponse llmResponse,
  String? providerFinishReason,
) {
  final String? malformedArgsMessage =
      llmResponse.finishReason == 'MALFORMED_FUNCTION_CALL'
      ? llmResponse.errorMessage
      : null;
  llmResponse.finishReason = providerFinishReason;
  if (providerFinishReason == null || providerFinishReason == 'STOP') {
    llmResponse.errorCode = null;
    llmResponse.errorMessage = null;
    return;
  }
  llmResponse.errorCode = providerFinishReason;
  llmResponse.errorMessage = _finishReasonToErrorMessage(providerFinishReason);
  if (malformedArgsMessage != null && malformedArgsMessage.isNotEmpty) {
    llmResponse.errorMessage =
        '${llmResponse.errorMessage}. $malformedArgsMessage';
  }
}

void _stampFinishReason(
  LlmResponse llmResponse,
  String? finishReason, {
  bool defaultToOtherWhenNull = false,
}) {
  final String? mappedFinishReason = finishReason == null
      ? (defaultToOtherWhenNull ? 'OTHER' : null)
      : LiteLlm.mapFinishReason(finishReason);
  if (mappedFinishReason == null ||
      _malformedArgsOutrankProvider(
        responseFinishReason: llmResponse.finishReason,
        providerFinishReason: mappedFinishReason,
      )) {
    return;
  }
  _applyProviderFinishReason(llmResponse, mappedFinishReason);
  if (finishReason == _streamEndedWithoutFinishReason) {
    llmResponse.errorMessage = _truncatedStreamErrorMessage;
  }
}

Object? _reasoningTokens(Map<String, Object?> usage) {
  final Map<String, Object?> details = _asMap(
    usage['completion_tokens_details'],
  );
  return details['reasoning_tokens'] ?? details['reasoningTokens'];
}

int? _asNullableInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
  }
  return null;
}

int? _extractCachedTokens(Map<String, Object?> usage) {
  for (final String key in const <String>[
    'cache_read_input_tokens',
    'cacheReadInputTokens',
  ]) {
    final int? value = _asNullableInt(usage[key]);
    if (value != null) {
      return value;
    }
  }
  final Map<String, Object?> details = _asMap(
    usage['prompt_tokens_details'] ?? usage['promptTokensDetails'],
  );
  for (final String key in const <String>[
    'cached_tokens',
    'cachedTokens',
    'cache_read_input_tokens',
    'cacheReadInputTokens',
  ]) {
    final int? value = _asNullableInt(details[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _extractCacheCreationTokens(Map<String, Object?> usage) {
  for (final String key in const <String>[
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
    'cache_write_input_tokens',
    'cacheWriteInputTokens',
  ]) {
    final int? value = _asNullableInt(usage[key]);
    if (value != null) {
      return value;
    }
  }
  final Map<String, Object?> details = _asMap(
    usage['prompt_tokens_details'] ?? usage['promptTokensDetails'],
  );
  for (final String key in const <String>[
    'cache_creation_tokens',
    'cacheCreationTokens',
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
  ]) {
    final int? value = _asNullableInt(details[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

List<Part> _extractReasoningParts(Object? raw, {Set<String>? reasoningTexts}) {
  final Set<String> seen = reasoningTexts ?? <String>{};
  final List<Part> parts = <Part>[];

  if (_isThinkingBlocksFormat(raw)) {
    for (final Object? item in raw as List<Object?>) {
      final Map<String, Object?> block = _asMap(item);
      if ('${block['type'] ?? ''}' == 'redacted') {
        continue;
      }
      final String text = '${block['thinking'] ?? ''}'.trim();
      final Object? signature = block['signature'];
      final bool hasSignature = signature != null && '$signature'.isNotEmpty;
      // Anthropic streams a signature in a final chunk with empty text.
      // Preserve signature-only blocks so the signature survives aggregation;
      // blocks with neither text nor signature are still skipped. Only apply
      // text-based dedup to non-empty text so distinct signature-only blocks
      // are not collapsed by an empty-string collision.
      if (text.isEmpty && !hasSignature) {
        continue;
      }
      if (text.isNotEmpty && !seen.add(text)) {
        continue;
      }
      parts.add(
        Part.text(text, thought: true).copyWith(
          thoughtSignature: hasSignature ? utf8.encode('$signature') : null,
        ),
      );
    }
    return parts;
  }

  void addThought(Object? value) {
    if (value is! String) {
      return;
    }
    final String text = value.trim();
    if (text.isEmpty || !seen.add(text)) {
      return;
    }
    parts.add(Part.text(text, thought: true));
  }

  if (raw is String) {
    addThought(raw);
    return parts;
  }
  if (raw is List) {
    for (final Object? item in raw) {
      if (item is Map) {
        addThought(item['text']);
        addThought(item['content']);
      } else {
        addThought(item);
      }
    }
    return parts;
  }
  if (raw is Map) {
    addThought(raw['text']);
    addThought(raw['content']);
  }
  return parts;
}

/// Aggregates fragmented streaming thought parts into clean individual parts.
///
/// During streaming, Anthropic splits a thinking block across many deltas:
/// text-only chunks followed by a signature-only chunk at `block_stop`. This
/// helper joins the text chunks and attaches the signature, producing clean
/// individual thought parts for session history and outbound requests.
List<Part> _aggregateStreamingThoughtParts(Iterable<Part> thoughtParts) {
  final List<Part> partsList = thoughtParts.toList(growable: false);
  if (partsList.isEmpty) {
    return const <Part>[];
  }
  final List<Part> aggregated = <Part>[];
  final List<String> currentTexts = <String>[];
  for (final Part part in partsList) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      currentTexts.add(text);
    }
    if (part.thoughtSignature != null) {
      aggregated.add(
        Part.text(
          currentTexts.join(),
          thought: true,
        ).copyWith(thoughtSignature: part.thoughtSignature),
      );
      currentTexts.clear();
    }
  }
  if (currentTexts.isNotEmpty) {
    aggregated.add(Part.text(currentTexts.join(), thought: true));
  }
  return aggregated;
}

/// Merges reasoning text fragments into a single provider payload.
///
/// Streaming providers such as vLLM can emit reasoning as token-sized chunks.
/// ADK stores those chunks as consecutive thought parts, so inserting
/// separators here would change the model's original reasoning text.
String _mergeReasoningTexts(Iterable<Part> reasoningParts) {
  final StringBuffer buffer = StringBuffer();
  for (final Part part in reasoningParts) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      buffer.write(text);
      continue;
    }
    final InlineData? inlineData = part.inlineData;
    if (inlineData != null &&
        inlineData.data.isNotEmpty &&
        inlineData.mimeType.startsWith('text/')) {
      buffer.write(utf8.decode(inlineData.data, allowMalformed: true));
    }
  }
  return buffer.toString();
}

bool _isThinkingBlocksFormat(Object? value) {
  if (value is! List || value.isEmpty) {
    return false;
  }
  final Object? first = value.first;
  return first is Map && first.containsKey('signature');
}

bool _isAnthropicModel(String model) {
  final String lower = model.toLowerCase();
  if (lower.startsWith('anthropic/')) {
    return true;
  }
  if (lower.startsWith('bedrock/')) {
    final String modelPart = lower.split('/').skip(1).join('/');
    return modelPart.contains('anthropic') || modelPart.contains('claude');
  }
  if (lower.startsWith('vertex_ai/')) {
    final String modelPart = lower.split('/').skip(1).join('/');
    return modelPart.contains('claude');
  }
  return false;
}

bool _isGemma4Model(String model, {String? baseUrl}) {
  final String lower = model.toLowerCase();
  if (!lower.contains('gemma-4') && !lower.contains('gemma4')) {
    return false;
  }
  final String provider = LiteLlm.getProviderFromModel(model);
  if (provider == 'openai' ||
      provider == 'azure' ||
      provider == 'lm_studio' ||
      provider == 'vertex_ai') {
    return false;
  }
  if (baseUrl != null && baseUrl.isNotEmpty) {
    return false;
  }
  return true;
}

String _toolResponseRoleForModel(String model, {String? baseUrl}) {
  return _isGemma4Model(model, baseUrl: baseUrl) ? 'tool_responses' : 'tool';
}

const String _missingToolResultContent =
    '{"error": "Tool execution was interrupted before a result was returned."}';

List<Map<String, Object?>> _ensureToolResults(
  List<Map<String, Object?>> messages, {
  String model = '',
  String? baseUrl,
}) {
  if (messages.isEmpty) {
    return messages;
  }
  final String toolRole = _toolResponseRoleForModel(model, baseUrl: baseUrl);
  final List<Map<String, Object?>> repaired = <Map<String, Object?>>[];
  int i = 0;
  while (i < messages.length) {
    final Map<String, Object?> msg = messages[i];
    repaired.add(msg);
    final Object? rawToolCalls = msg['tool_calls'];
    if (msg['role'] != 'assistant' ||
        rawToolCalls is! List ||
        rawToolCalls.isEmpty) {
      i += 1;
      continue;
    }

    int j = i + 1;
    final Set<String> answeredIds = <String>{};
    while (j < messages.length) {
      final Object? nextRole = messages[j]['role'];
      if (nextRole != 'tool' && nextRole != 'tool_responses') {
        break;
      }
      final Object? callId = messages[j]['tool_call_id'];
      if (callId is String && callId.isNotEmpty) {
        answeredIds.add(callId);
      }
      repaired.add(messages[j]);
      j += 1;
    }

    if (j < messages.length || answeredIds.isNotEmpty) {
      for (final Object? tc in rawToolCalls) {
        final Map<String, Object?> tcMap = _asMap(tc);
        final String? tcId = tcMap['id'] == null ? null : '${tcMap['id']}';
        if (tcId != null && tcId.isNotEmpty && !answeredIds.contains(tcId)) {
          repaired.add(<String, Object?>{
            'role': toolRole,
            'tool_call_id': tcId,
            'content': _missingToolResultContent,
          });
        }
      }
    }
    i = j;
  }
  return repaired;
}

List<Map<String, Object?>> _contentToMessages(
  Content content, {
  String model = '',
  String? baseUrl,
}) {
  final String role = content.role == 'model' ? 'assistant' : '${content.role}';
  final String toolRole = _toolResponseRoleForModel(model, baseUrl: baseUrl);
  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolResponses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
  final List<Part> reasoningParts = <Part>[];

  for (final Part part in content.parts) {
    if (part.functionResponse != null) {
      toolResponses.add(<String, Object?>{
        'role': toolRole,
        'tool_call_id': part.functionResponse!.id,
        'content': jsonEncode(part.functionResponse!.response),
      });
      continue;
    }
    if (part.functionCall != null) {
      final Map<String, Object?> toolCall = <String, Object?>{
        'id': part.functionCall!.id ?? 'call_${part.functionCall!.name}',
        'type': 'function',
        'function': <String, Object?>{
          'name': part.functionCall!.name,
          'arguments': jsonEncode(part.functionCall!.args),
        },
      };
      final String? thoughtSignature = _encodeThoughtSignature(
        part.thoughtSignature,
      );
      if (thoughtSignature != null) {
        toolCall['provider_specific_fields'] = <String, Object?>{
          'thought_signature': thoughtSignature,
        };
        toolCall['extra_content'] = <String, Object?>{
          'google': <String, Object?>{'thought_signature': thoughtSignature},
        };
      }
      toolCalls.add(toolCall);
      continue;
    }
    if (part.thought &&
        ((part.text != null && part.text!.isNotEmpty) ||
            part.thoughtSignature != null)) {
      // Collect thought parts that carry text or a signature. Streaming emits
      // signature-only thought parts (empty text) that must be preserved so
      // the signature survives aggregation for Anthropic outbound requests.
      reasoningParts.add(part);
      continue;
    }
    if (part.text != null && part.text!.isNotEmpty) {
      parts.add(<String, Object?>{'type': 'text', 'text': part.text});
      continue;
    }
    if (part.inlineData != null) {
      final String mimeType = part.inlineData!.mimeType;
      final String encodedData = base64Encode(part.inlineData!.data);
      if (_isAudioMimeType(mimeType)) {
        parts.add(<String, Object?>{
          'type': 'input_audio',
          'input_audio': <String, Object?>{
            'data': encodedData,
            'format': _audioFormatFromMimeType(mimeType),
          },
        });
      } else {
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:$mimeType;base64,$encodedData',
          },
        });
      }
    } else if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
      final String mimeType = part.fileData!.mimeType ?? '';
      if (mimeType.isEmpty || mimeType == 'application/octet-stream') {
        final String typeLabel = mimeType.isEmpty ? '(unknown)' : mimeType;
        final String redactedFileUri = redactFileUriForLog(
          part.fileData!.fileUri,
          displayName: part.fileData!.displayName,
        );
        throw ArgumentError(
          "Cannot process file_uri '$redactedFileUri': MIME type "
          "'$typeLabel' is not supported. Please set a specific MIME "
          "type on `file_data.mime_type`.",
        );
      }
      final String provider = LiteLlm.getProviderFromModel(model);
      if (_isAudioMimeType(mimeType) &&
          (provider == 'openai' || provider == 'azure')) {
        parts.add(<String, Object?>{
          'type': 'text',
          'text': '[File reference: "${part.fileData!.fileUri}"]',
        });
      } else {
        parts.add(<String, Object?>{
          'type': 'file_url',
          'file_url': <String, Object?>{'url': part.fileData!.fileUri},
        });
      }
    }
  }

  if (toolResponses.isNotEmpty) {
    return toolResponses;
  }

  final Map<String, Object?> message = <String, Object?>{'role': role};
  if (_isAnthropicModel(model) && reasoningParts.isNotEmpty) {
    // Streaming splits one Anthropic thinking block across many deltas:
    // text-only chunks followed by a signature-only chunk at block_stop.
    // Aggregate them back into one thinking block for outbound.
    final List<Part> aggregatedParts = _aggregateStreamingThoughtParts(
      reasoningParts,
    );
    final List<Map<String, Object?>> thinkingBlocks = aggregatedParts
        .where(
          (Part part) =>
              part.thoughtSignature != null &&
              part.text != null &&
              part.text!.isNotEmpty,
        )
        .map(
          (Part part) => <String, Object?>{
            'type': 'thinking',
            'thinking': part.text!,
            'signature': utf8.decode(part.thoughtSignature!),
          },
        )
        .toList(growable: false);
    if (thinkingBlocks.isNotEmpty) {
      message['thinking_blocks'] = thinkingBlocks;
    } else {
      final String reasoningText = _mergeReasoningTexts(reasoningParts);
      if (reasoningText.isNotEmpty) {
        message['reasoning_content'] = reasoningText;
      }
    }
  } else if (reasoningParts.isNotEmpty) {
    final String reasoningText = _mergeReasoningTexts(reasoningParts);
    if (reasoningText.isNotEmpty) {
      message['reasoning_content'] = reasoningText;
    }
  }
  if (toolCalls.isNotEmpty) {
    message['tool_calls'] = toolCalls;
    if (parts.isEmpty) {
      message['content'] = null;
    }
  }
  if (parts.isNotEmpty) {
    if (role == 'assistant') {
      final List<String> textBlocks = <String>[
        for (final Map<String, Object?> block in parts)
          if (block['type'] == 'text' && block['text'] is String)
            block['text'] as String,
      ];
      if (textBlocks.isNotEmpty && textBlocks.length == parts.length) {
        message['content'] = textBlocks.join('\n');
      } else if (parts.length == 1 && parts.first['type'] == 'text') {
        message['content'] = parts.first['text'];
      } else {
        message['content'] = parts;
      }
    } else if (parts.length == 1 && parts.first['type'] == 'text') {
      message['content'] = parts.first['text'];
    } else {
      message['content'] = parts;
    }
  }
  output.add(message);
  return output;
}

bool _isAudioMimeType(String mimeType) {
  return mimeType.trim().toLowerCase().startsWith('audio/');
}

String _audioFormatFromMimeType(String mimeType) {
  final String normalized = mimeType.split(';').first.trim().toLowerCase();
  final String subtype = normalized.contains('/')
      ? normalized.split('/').last
      : normalized;
  switch (subtype) {
    case 'mpeg':
    case 'mp3':
      return 'mp3';
    case 'wav':
    case 'wave':
    case 'x-wav':
    case 'vnd.wave':
      return 'wav';
    default:
      return subtype.startsWith('x-') ? subtype.substring(2) : subtype;
  }
}

final RegExp _markdownCodeBlockPattern = RegExp(
  r'^\s*```(?:json)?\s*(.*?)\s*```\s*$',
  dotAll: true,
);

String _quoteUnquotedJsonObjectKeys(String rawArguments) {
  final StringBuffer result = StringBuffer();
  bool inString = false;
  String quoteChar = '';
  bool escaped = false;
  bool expectingKey = false;
  final int length = rawArguments.length;
  int i = 0;

  while (i < length) {
    final String ch = rawArguments[i];
    if (inString) {
      result.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quoteChar) {
        inString = false;
      }
      i += 1;
      continue;
    }

    if (ch == '"' || ch == "'") {
      inString = true;
      quoteChar = ch;
      expectingKey = false;
      result.write(ch);
      i += 1;
      continue;
    }

    if (ch == '{' || ch == ',') {
      expectingKey = true;
      result.write(ch);
      i += 1;
      continue;
    }

    if (expectingKey) {
      if (ch.trim().isEmpty) {
        result.write(ch);
        i += 1;
        continue;
      }
      if (ch == '}') {
        expectingKey = false;
        result.write(ch);
        i += 1;
        continue;
      }
      if (_isIdentifierStart(ch)) {
        int j = i + 1;
        while (j < length && _isIdentifierContinuation(rawArguments[j])) {
          j += 1;
        }
        int k = j;
        while (k < length && rawArguments[k].trim().isEmpty) {
          k += 1;
        }
        if (k < length && rawArguments[k] == ':') {
          final String key = rawArguments.substring(i, j);
          if (key != 'True' &&
              key != 'False' &&
              key != 'None' &&
              key != 'true' &&
              key != 'false' &&
              key != 'null') {
            result.write('"$key"');
            result.write(rawArguments.substring(j, k));
            result.write(':');
            expectingKey = false;
            i = k + 1;
            continue;
          }
        }
      }
      expectingKey = false;
    }

    result.write(ch);
    i += 1;
  }

  return result.toString();
}

bool _isIdentifierStart(String ch) {
  final int code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      ch == '_' ||
      ch == r'$';
}

bool _isIdentifierContinuation(String ch) {
  final int code = ch.codeUnitAt(0);
  return _isIdentifierStart(ch) ||
      (code >= 48 && code <= 57) ||
      ch == '-' ||
      ch == '.';
}

bool _hasOnlyStringKeys(Object? value) {
  final List<(Object?, int)> stack = <(Object?, int)>[(value, 0)];
  while (stack.isNotEmpty) {
    final (Object? item, int depth) = stack.removeLast();
    if (depth > _maxJsonDepth) {
      return false;
    }
    if (item is Map) {
      for (final Object? key in item.keys) {
        if (key is! String) {
          return false;
        }
      }
      for (final Object? child in item.values) {
        stack.add((child, depth + 1));
      }
    } else if (item is Iterable) {
      for (final Object? child in item) {
        stack.add((child, depth + 1));
      }
    }
  }
  return true;
}

/// Parses tool call [arguments] into a JSON-encodable object, throwing
/// [FormatException] when the arguments cannot be parsed or encoded.
Object? parseToolCallArguments(Object? arguments, {String? functionName}) {
  final Object? decoded = _decodeToolCallArguments(
    arguments,
    functionName: functionName,
  );
  try {
    jsonEncode(decoded);
  } on Object {
    throw const FormatException('Tool call arguments cannot be encoded as JSON');
  }
  if (!_hasOnlyStringKeys(decoded)) {
    throw const FormatException('Tool call argument keys must be strings');
  }
  return decoded;
}

Object? _decodeToolCallArguments(
  Object? arguments, {
  String? functionName,
}) {
  if (arguments == null || (arguments is String && arguments.isEmpty)) {
    return <String, dynamic>{};
  }
  if (arguments is! String) {
    return arguments;
  }
  if (_hugeIntLiteralPattern.hasMatch(arguments)) {
    throw const FormatException(
      "Tool call arguments exceed the decoder's limits",
    );
  }
  try {
    return jsonDecode(arguments);
  } on StackOverflowError {
    throw const FormatException(
      "Tool call arguments exceed the decoder's limits",
    );
  } on FormatException {
    final String cleaned;
    final RegExpMatch? fenceMatch = _markdownCodeBlockPattern.firstMatch(
      arguments.trim(),
    );
    if (fenceMatch != null) {
      cleaned = (fenceMatch.group(1) ?? '').trim();
      if (cleaned.isEmpty) {
        rethrow;
      }
    } else {
      cleaned = arguments.trim();
    }
    if (cleaned.isEmpty) {
      rethrow;
    }
    final String quotedKeys = _quoteUnquotedJsonObjectKeys(cleaned);
    for (final String candidate in <String>[
      if (fenceMatch != null) cleaned,
      quotedKeys,
      _normalizePythonLiteralJson(quotedKeys),
    ]) {
      try {
        return jsonDecode(candidate);
      } on StackOverflowError {
        throw const FormatException(
          "Tool call arguments exceed the decoder's limits",
        );
      } on FormatException {
        // Try next fallback candidate.
      }
    }
    rethrow;
  }
}

Map<String, dynamic>? _tryParseToolCallArguments(
  Object? rawArgs,
  String toolName,
) {
  try {
    final Object? parsed = parseToolCallArguments(
      rawArgs,
      functionName: toolName,
    );
    if (parsed is Map) {
      return parsed.map((Object? k, Object? v) => MapEntry('$k', v));
    }
    return null;
  } on Object {
    return null;
  }
}

String _normalizePythonLiteralJson(String input) {
  final StringBuffer out = StringBuffer();
  bool inDouble = false;
  bool inSingle = false;
  bool escaped = false;
  for (int i = 0; i < input.length; i += 1) {
    final String ch = input[i];
    if (inDouble) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (inSingle) {
      if (escaped) {
        if (ch == "'") {
          out.write("'");
        } else {
          out.write(r'\');
          out.write(ch);
        }
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == "'") {
        out.write('"');
        inSingle = false;
      } else if (ch == '"') {
        out.write(r'\"');
      } else {
        out.write(ch);
      }
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      out.write(ch);
      continue;
    }
    if (ch == "'") {
      inSingle = true;
      out.write('"');
      continue;
    }
    out.write(ch);
  }
  String normalized = out.toString();
  normalized = normalized.replaceAllMapped(
    RegExp(r'(?<=[:,\[\s])(True|False|None)(?=[,}\]\s])'),
    (Match m) {
      switch (m.group(1)) {
        case 'True':
          return 'true';
        case 'False':
          return 'false';
        default:
          return 'null';
      }
    },
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (Match m) => m.group(1)!,
  );
  return normalized;
}

Part? _tryParseFunctionCall(
  Map<String, Object?> callMap, {
  Map<int, List<int>>? pendingToolSignatures,
  int fallbackIndex = 0,
}) {
  final Map<String, Object?> function = _asMap(callMap['function']);
  final Object? rawName = function['name'];
  final String name = rawName is String ? rawName : '';
  final Map<String, dynamic>? parsedArgs = _tryParseToolCallArguments(
    function['arguments'],
    name,
  );
  if (parsedArgs == null) {
    return null;
  }
  final String? callId = callMap['id'] == null ? null : '${callMap['id']}';
  final int callIndex = callMap['index'] is num
      ? (callMap['index'] as num).toInt()
      : fallbackIndex;
  final List<int>? extractedSignature = _extractThoughtSignatureFromToolCall(
    callMap,
  );
  if (name.isEmpty &&
      (function['arguments'] == null || '${function['arguments']}'.isEmpty) &&
      extractedSignature != null &&
      pendingToolSignatures != null) {
    pendingToolSignatures[callIndex] = extractedSignature;
  }
  final List<int>? thoughtSignature =
      extractedSignature ?? pendingToolSignatures?.remove(callIndex);
  final Part part = Part.fromFunctionCall(
    name: name,
    args: parsedArgs,
    id: callId,
  );
  if (thoughtSignature == null) {
    return part;
  }
  return part.copyWith(thoughtSignature: thoughtSignature);
}

LlmResponse _parseStreamCompletionChunk(
  Map<String, Object?> response, {
  required Map<int, List<int>> pendingToolSignatures,
  bool parseInlineToolCalls = true,
  bool allowBareJson = true,
}) {
  final List<Object?> choices =
      (response['choices'] as List<Object?>?) ?? <Object?>[];
  if (choices.isEmpty) {
    return LiteLlm.parseCompletionResponse(
      response,
      parseInlineToolCalls: parseInlineToolCalls,
      allowBareJson: allowBareJson,
    );
  }
  final Map<String, Object?> first = _asMap(choices.first);
  final Map<String, Object?> message = _asMap(first['message']);
  final Map<String, Object?> delta = _asMap(first['delta']);
  final Map<String, Object?> effectiveMessage = message.isNotEmpty
      ? message
      : delta;
  final List<Object?> toolCalls =
      (effectiveMessage['tool_calls'] as List<Object?>?) ?? <Object?>[];
  if (toolCalls.isEmpty) {
    return LiteLlm.parseCompletionResponse(
      response,
      parseInlineToolCalls: parseInlineToolCalls,
      allowBareJson: allowBareJson,
    );
  }
  final List<Object?> filteredToolCalls = <Object?>[];
  for (int i = 0; i < toolCalls.length; i += 1) {
    final Map<String, Object?> callMap = _asMap(toolCalls[i]);
    final Map<String, Object?> fn = _asMap(callMap['function']);
    final String name = '${fn['name'] ?? ''}';
    final String args = '${fn['arguments'] ?? ''}';
    final int idx = callMap['index'] is num
        ? (callMap['index'] as num).toInt()
        : i;
    final List<int>? sig = _extractThoughtSignatureFromToolCall(callMap);
    if (name.isEmpty && args.isEmpty) {
      if (sig != null) {
        pendingToolSignatures[idx] = sig;
      }
      continue;
    }
    if (sig == null && pendingToolSignatures.containsKey(idx)) {
      final String encoded = base64Encode(pendingToolSignatures.remove(idx)!);
      filteredToolCalls.add(<String, Object?>{
        ...callMap,
        'provider_specific_fields': <String, Object?>{
          ..._asMap(callMap['provider_specific_fields']),
          'thought_signature': encoded,
        },
      });
    } else {
      if (sig != null) {
        pendingToolSignatures.remove(idx);
      }
      filteredToolCalls.add(callMap);
    }
  }
  final Map<String, Object?> patchedMessage = <String, Object?>{
    ...effectiveMessage,
    'tool_calls': filteredToolCalls,
  };
  final Map<String, Object?> patchedFirst = <String, Object?>{
    ...first,
    if (message.isNotEmpty) 'message': patchedMessage else 'delta': patchedMessage,
  };
  return LiteLlm.parseCompletionResponse(
    <String, Object?>{
      ...response,
      'choices': <Object?>[patchedFirst],
    },
    parseInlineToolCalls: false,
    allowBareJson: false,
  );
}

const int _anthropicMinThinkingBudgetTokens = 1024;
const Map<String, int> _anthropicEffortBudgets = <String, int>{
  'minimal': _anthropicMinThinkingBudgetTokens,
  'low': 1024,
  'medium': 2048,
  'high': 4096,
};
const List<String> _claude46Substrings = <String>[
  'opus-4-6',
  'opus_4_6',
  'opus-4.6',
  'opus_4.6',
  'sonnet-4-6',
  'sonnet_4_6',
  'sonnet-4.6',
  'sonnet_4.6',
];
const List<String> _claude47Substrings = <String>[
  'opus-4-7',
  'opus_4_7',
  'opus-4.7',
  'opus_4.7',
];
const Map<String, int> _geminiMinThinkingBudgets = <String, int>{
  'gemini-2.5-pro': 128,
  'gemini-2.5-flash-lite': 512,
};

Map<String, Object?>? _thinkingConfigToMap(Object? rawConfig) {
  if (rawConfig == null) {
    return null;
  }
  if (rawConfig is Map) {
    return rawConfig.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  final dynamic dyn = rawConfig;
  try {
    final Object? json = dyn.toJson();
    if (json is Map) {
      return json.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
  } catch (_) {}
  final Map<String, Object?> result = <String, Object?>{};
  try {
    final Object? includeThoughts = dyn.includeThoughts;
    if (includeThoughts != null) {
      result['include_thoughts'] = includeThoughts;
    }
  } catch (_) {}
  try {
    final Object? thinkingBudget = dyn.thinkingBudget;
    if (thinkingBudget != null) {
      result['thinking_budget'] = thinkingBudget;
    }
  } catch (_) {}
  try {
    final Object? thinkingLevel = dyn.thinkingLevel;
    if (thinkingLevel != null) {
      result['thinking_level'] = thinkingLevel;
    }
  } catch (_) {}
  return result.isEmpty ? null : result;
}

bool _shouldFilterThoughts(Object? rawThinkingConfig) {
  final Map<String, Object?>? map = _thinkingConfigToMap(rawThinkingConfig);
  if (map == null) {
    return false;
  }
  final Object? includeThoughts =
      map['include_thoughts'] ?? map['includeThoughts'];
  return includeThoughts == false;
}

void _filterThoughtParts(LlmResponse response) {
  final Content? content = response.content;
  if (content == null || content.parts.isEmpty) {
    return;
  }
  final bool hasToolCalls = content.parts.any(
    (Part part) => part.functionCall != null,
  );
  content.parts = <Part>[
    for (final Part part in content.parts)
      if (!part.thought || (hasToolCalls && part.thoughtSignature != null))
        part,
  ];
}

void _dropParamsRejectedByAnthropicThinking(Map<String, Object?> params) {
  final Object? thinking = params['thinking'];
  final Object? reasoningEffort = params['reasoning_effort'];
  final bool thinkingEnabled =
      (reasoningEffort != null && reasoningEffort != 'none') ||
      (thinking is Map &&
          (thinking['type'] == 'enabled' || thinking['type'] == 'adaptive'));
  if (!thinkingEnabled) {
    return;
  }
  if (params['temperature'] != 1 && params['temperature'] != 1.0) {
    params.remove('temperature');
  }
  params.remove('top_k');
  final Object? topP = params['top_p'];
  if (topP is num && topP < 0.95) {
    params.remove('top_p');
  }
}

void _applyThinkingConfigToPayload(
  Map<String, Object?> payload,
  Object? rawThinkingConfig, {
  required String model,
}) {
  final Map<String, Object?>? config = _thinkingConfigToMap(rawThinkingConfig);
  if (config == null || config.isEmpty) {
    return;
  }
  final String lowerModel = model.toLowerCase();
  final bool isAnthropic =
      _isAnthropicModel(model) || lowerModel.contains('claude');
  final bool isClaude47 =
      isAnthropic && _claude47Substrings.any(lowerModel.contains);
  final bool isAdaptiveAnthropic =
      isAnthropic &&
      (isClaude47 || _claude46Substrings.any(lowerModel.contains));
  final bool isGemini = lowerModel.contains('gemini-');
  final bool isGemini3OrNewer = isGemini && lowerModel.contains('gemini-3');
  final int? effectiveMaxTokens =
      (payload['max_completion_tokens'] as int?) ??
      (payload['max_tokens'] as int?);

  final Object? rawLevel =
      config['thinking_level'] ?? config['thinkingLevel'];
  final String? levelStr = rawLevel == null
      ? null
      : '$rawLevel'.split('.').last;
  final Object? rawBudget =
      config['thinking_budget'] ?? config['thinkingBudget'];
  final int? thinkingBudget = rawBudget is num ? rawBudget.toInt() : null;
  final Object? includeThoughts =
      config['include_thoughts'] ?? config['includeThoughts'];

  if (levelStr != null &&
      levelStr.isNotEmpty &&
      levelStr.toUpperCase() != 'THINKING_LEVEL_UNSPECIFIED' &&
      levelStr.toLowerCase() != 'unspecified') {
    final String effort = levelStr.toLowerCase();
    if (isAnthropic && !isAdaptiveAnthropic) {
      final int? effortBudget = _anthropicEffortBudgets[effort];
      if (effectiveMaxTokens != null &&
          effectiveMaxTokens <= _anthropicMinThinkingBudgetTokens) {
        // Skip thinking when max_tokens cannot fit the minimum budget.
      } else if (effort == 'minimal' ||
          (effectiveMaxTokens != null &&
              effortBudget != null &&
              effectiveMaxTokens <= effortBudget)) {
        final int budget =
            (effectiveMaxTokens != null && effortBudget != null)
            ? (effortBudget < effectiveMaxTokens - 1
                  ? effortBudget
                  : effectiveMaxTokens - 1)
            : _anthropicMinThinkingBudgetTokens;
        payload['thinking'] = <String, Object?>{
          'type': 'enabled',
          'budget_tokens': budget,
        };
      } else {
        payload['reasoning_effort'] = effort;
      }
    } else {
      payload['reasoning_effort'] = effort;
    }
  } else if (thinkingBudget == 0) {
    if (!isGemini3OrNewer && (isAnthropic || isGemini)) {
      if (isGemini) {
        if (!lowerModel.contains('gemini-2.5-pro')) {
          payload['thinking'] = <String, Object?>{
            'type': 'enabled',
            'budget_tokens': 0,
          };
        }
      } else {
        payload['thinking'] = <String, Object?>{'type': 'disabled'};
      }
    } else if (isGemini3OrNewer) {
      payload['reasoning_effort'] = 'none';
    }
  } else if (thinkingBudget != null && thinkingBudget > 0) {
    if (!isGemini3OrNewer && !isClaude47 && (isAnthropic || isGemini)) {
      int minBudget = 0;
      if (isAnthropic) {
        minBudget = _anthropicMinThinkingBudgetTokens;
      } else if (isGemini) {
        for (final MapEntry<String, int> entry
            in _geminiMinThinkingBudgets.entries) {
          if (lowerModel.contains(entry.key)) {
            minBudget = entry.value;
            break;
          }
        }
      }
      final int rawBudgetVal =
          thinkingBudget < minBudget ? minBudget : thinkingBudget;
      int? budgetVal = rawBudgetVal;
      if (isAnthropic && effectiveMaxTokens != null) {
        budgetVal = effectiveMaxTokens > _anthropicMinThinkingBudgetTokens
            ? (rawBudgetVal < effectiveMaxTokens - 1
                  ? rawBudgetVal
                  : effectiveMaxTokens - 1)
            : null;
      }
      if (budgetVal != null) {
        payload['thinking'] = <String, Object?>{
          'type': 'enabled',
          'budget_tokens': budgetVal,
        };
      }
    } else {
      if (thinkingBudget <= 1024) {
        payload['reasoning_effort'] = 'low';
      } else if (thinkingBudget <= 2048) {
        payload['reasoning_effort'] = 'medium';
      } else {
        payload['reasoning_effort'] = 'high';
      }
    }
  }

  if (!payload.containsKey('thinking') &&
      !payload.containsKey('reasoning_effort') &&
      (levelStr == null ||
          levelStr.isEmpty ||
          levelStr.toUpperCase() == 'THINKING_LEVEL_UNSPECIFIED' ||
          levelStr.toLowerCase() == 'unspecified') &&
      (thinkingBudget == null || thinkingBudget < 0)) {
    if (includeThoughts == true && !isGemini3OrNewer) {
      if (isAnthropic) {
        if (isClaude47) {
          payload['thinking'] = <String, Object?>{'type': 'adaptive'};
        } else if (effectiveMaxTokens == null ||
            effectiveMaxTokens > _anthropicMinThinkingBudgetTokens) {
          payload['thinking'] = <String, Object?>{
            'type': 'enabled',
            'budget_tokens': _anthropicMinThinkingBudgetTokens,
          };
        }
      } else if (isGemini) {
        payload['thinking'] = <String, Object?>{'type': 'enabled'};
      }
    } else if (includeThoughts == false && isGemini) {
      payload['thinking'] = <String, Object?>{'type': 'disabled'};
    }
  }

  if (isAnthropic) {
    _dropParamsRejectedByAnthropicThinking(payload);
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, Object?> _toLiteLlmResponseFormat(
  Map<String, Object?> responseSchema,
  String model,
) {
  final String? schemaType = responseSchema['type'] is String
      ? '${responseSchema['type']}'.toLowerCase()
      : null;
  if (schemaType == 'json_object' || schemaType == 'json_schema') {
    return responseSchema;
  }

  if (_isLiteLlmGeminiModel(model)) {
    return <String, Object?>{
      'type': 'json_object',
      'response_schema': responseSchema,
    };
  }

  lowercaseSchemaTypes(responseSchema);
  enforceStrictOpenAiSchema(responseSchema);
  final String schemaName =
      responseSchema['title'] is String &&
          (responseSchema['title'] as String).isNotEmpty
      ? responseSchema['title'] as String
      : 'response';
  return <String, Object?>{
    'type': 'json_schema',
    'json_schema': <String, Object?>{
      'name': schemaName,
      'strict': true,
      'schema': responseSchema,
    },
  };
}

bool _isLiteLlmGeminiModel(String model) {
  final String normalized = model.toLowerCase();
  return normalized.startsWith('gemini/gemini-') ||
      normalized.startsWith('vertex_ai/gemini-');
}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  return _deepCopyJsonValue(source) as Map<String, Object?>;
}

Object? _deepCopyJsonValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> copied = <String, Object?>{};
    value.forEach((Object? key, Object? nested) {
      copied['$key'] = _deepCopyJsonValue(nested);
    });
    return copied;
  }
  if (value is List) {
    return value
        .map((Object? item) => _deepCopyJsonValue(item))
        .toList(growable: false);
  }
  return value;
}

Map<String, Object?>? _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

String? _encodeThoughtSignature(List<int>? thoughtSignature) {
  if (thoughtSignature == null || thoughtSignature.isEmpty) {
    return null;
  }
  return base64Encode(thoughtSignature);
}

List<int>? _extractThoughtSignatureFromToolCall(Map<String, Object?> toolCall) {
  final Map<String, Object?> extraContent = _asMap(toolCall['extra_content']);
  final Map<String, Object?> googleExtra = _asMap(extraContent['google']);
  final List<int>? fromExtra = _decodeThoughtSignature(
    googleExtra['thought_signature'],
  );
  if (fromExtra != null) {
    return fromExtra;
  }

  final Map<String, Object?> providerFields = _asMap(
    toolCall['provider_specific_fields'],
  );
  final List<int>? fromProvider = _decodeThoughtSignature(
    providerFields['thought_signature'],
  );
  if (fromProvider != null) {
    return fromProvider;
  }

  final Map<String, Object?> function = _asMap(toolCall['function']);
  final Map<String, Object?> functionProviderFields = _asMap(
    function['provider_specific_fields'],
  );
  final List<int>? fromFunctionProvider = _decodeThoughtSignature(
    functionProviderFields['thought_signature'],
  );
  if (fromFunctionProvider != null) {
    return fromFunctionProvider;
  }

  final String? toolCallId = toolCall['id'] == null
      ? null
      : '${toolCall['id']}';
  if (toolCallId != null && toolCallId.contains(_thoughtSignatureSeparator)) {
    final List<String> parts = toolCallId.split(_thoughtSignatureSeparator);
    if (parts.length >= 2) {
      return _decodeThoughtSignature(
        parts.sublist(1).join(_thoughtSignatureSeparator),
      );
    }
  }

  return null;
}

List<int>? _decodeThoughtSignature(Object? value) {
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
  if (value is! String || value.isEmpty) {
    return null;
  }
  try {
    return base64Decode(value);
  } catch (_) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      return null;
    }
  }
}

/// Returns a privacy-preserving identifier for logs and error messages.
String redactFileUriForLog(String fileUri, {String? displayName}) {
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  if (fileUri.startsWith('assistant-')) {
    return 'assistant-<redacted>';
  }
  final RegExp openAiPrefixRegex =
      RegExp(r'^(file|cfile|batch|model|vs|asst)-[A-Za-z0-9]+');
  if (openAiPrefixRegex.hasMatch(fileUri)) {
    final String prefix = fileUri.split('-').first;
    return '$prefix-<redacted>';
  }
  final Uri? parsed = Uri.tryParse(fileUri);
  if (parsed == null || !parsed.hasScheme) {
    return '<unknown>';
  }
  final List<String> segments =
      parsed.pathSegments.where((String s) => s.isNotEmpty).toList();
  final String tail = segments.isNotEmpty ? segments.last : '';
  if (tail.isNotEmpty) {
    return '${parsed.scheme}://<redacted>/$tail';
  }
  return '${parsed.scheme}://<redacted>';
}

const String _dsTcallsBegin = '\u003c\uff5ctool\u2581calls\u2581begin\uff5c\u003e';
const String _dsTcallsEnd = '\u003c\uff5ctool\u2581calls\u2581end\uff5c\u003e';
const String _dsTcallBegin = '\u003c\uff5ctool\u2581call\u2581begin\uff5c\u003e';
const String _dsTcallEnd = '\u003c\uff5ctool\u2581call\u2581end\uff5c\u003e';
const String _dsTsep = '\u003c\uff5ctool\u2581sep\uff5c\u003e';

final RegExp _dsToolCallRe = RegExp(
  '${RegExp.escape(_dsTcallBegin)}function${RegExp.escape(_dsTsep)}'
  r'([^\n\r]+?)\s*?\n(.*?)'
  '${RegExp.escape(_dsTcallEnd)}',
  dotAll: true,
);

const String _toolCallOpen = '<tool_call>';
const String _toolCallClose = '</tool_call>';

final RegExp _fenceOpenRe = RegExp(
  r' {0,3}(`{3,}(?=[^`\n]*$)|~{3,})',
  multiLine: true,
);
final RegExp _fenceCloseRe = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[ \t]*\r?$',
  multiLine: true,
);

const Map<String, String> _callBlockEnds = <String, String>{
  _toolCallOpen: _toolCallClose,
  _dsTcallsBegin: _dsTcallsEnd,
  _dsTcallBegin: _dsTcallEnd,
};

final String _callBlockPattern = _callBlockEnds.keys
    .map(RegExp.escape)
    .join('|');
final RegExp _callBlockRe = RegExp(_callBlockPattern);
final RegExp _codeScanRe = RegExp('$_callBlockPattern|<think>|`+|~{3,}');
final RegExp _inlineCodeScanRe = RegExp('$_callBlockPattern|`+');
final RegExp _paragraphEndRe = RegExp(
  r'\n(?=[ \t]*\r?(?:\n|$)| {0,3}(?:```|~~~))',
);
final RegExp _codeIndentRe = RegExp(r' {4}| {0,3}\t');
final RegExp _atxHeadingRe = RegExp(r' {0,3}#{1,6}(?:[ \t]|\r?$)');
final RegExp _indentedCodeRe = RegExp(
  r'(?:\A|^(?:[ \t]*| {0,3}(?:#{1,6}(?:[ \t].*)?|`{3,}[ \t]*|~{3,}[ \t]*))'
  r'\r?\n)((?: {4}| {0,3}\t).*(?:\n(?:[ \t]*\r?$|(?: {4}| {0,3}\t).*))*)',
  multiLine: true,
);
final RegExp _leadingCallPrefixRe = RegExp(
  r'(?:<\|python_tag\|>|\[TOOL_CALLS\])?\s*',
);
final RegExp _thinkTagRe = RegExp(r'</?think>');
final RegExp _backtickRunRe = RegExp(r'`+');
final RegExp _tagPayloadFenceRe = RegExp(
  r'(`{3,}|~{3,})[ \t]*(?:json)?[ \t]*\r?\n',
  caseSensitive: false,
);
final RegExp _dsFenceArgsRe = RegExp(
  r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
);

