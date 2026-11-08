part of 'bigquery_agent_analytics_plugin.dart';

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
  for (final Part part in content.parts) {
    if (part.text != null) {
      String value = part.text!;
      if (maxLen != -1 && value.length > maxLen) {
        value = '${value.substring(0, maxLen)}...';
        truncated = true;
      }
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
    partData['uri'] = fileData.fileUri;
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
    final int byteLength = utf8.encode(text).length;
    final bool exceedsByteLimit = byteLength > 32 * 1024;
    final bool exceedsCharLimit = maxLength != -1 && text.length > maxLength;
    if (gcsUploadProvider != null && (exceedsByteLimit || exceedsCharLimit)) {
      final String path = _gcsOffloadPath(
        traceId: traceId,
        spanId: spanId,
        partIndex: index,
        extension: '.txt',
      );
      try {
        final String uri = await gcsUploadProvider(
          data: utf8.encode(text),
          contentType: 'text/plain',
          path: path,
        );
        partData['storage_mode'] = 'GCS_REFERENCE';
        partData['uri'] = uri;
        partData['mime_type'] = 'text/plain';
        partData['text'] = _truncateAndAddSuffix(text, 200, '... [OFFLOADED]');
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
    partData['text'] = _recursiveSmartTruncate(text, maxLength).value;
    return _recursiveSmartTruncate(partData, maxLength).value;
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
]) {
  final Set<int> visited = seen ?? <int>{};

  if (value == null || value is num || value is bool) {
    return _TruncateResult(value: value, isTruncated: false);
  }

  if (value is String) {
    if (maxLength != -1 && value.length > maxLength) {
      return _TruncateResult(
        value: '${value.substring(0, maxLength)}...[TRUNCATED]',
        isTruncated: true,
      );
    }
    return _TruncateResult(value: value, isTruncated: false);
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
        final _TruncateResult child = _recursiveSmartTruncate(
          entry.value,
          maxLength,
          visited,
        );
        converted['${entry.key}'] = child.value;
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    final String fallback = '$value';
    if (maxLength != -1 && fallback.length > maxLength) {
      return _TruncateResult(
        value: '${fallback.substring(0, maxLength)}...[TRUNCATED]',
        isTruncated: true,
      );
    }
    return _TruncateResult(value: fallback, isTruncated: false);
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
