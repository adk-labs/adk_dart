/// Custom Gemini LLM implementation for conformance replay testing.
library;

import 'package:adk_dart/src/flows/llm_flows/_fencing.dart';
import 'package:adk_dart/src/models/google_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';

import '../plugins/conformance_recordings_schema.dart';
import '../plugins/conformance_replay_plugin.dart';

export '../plugins/conformance_replay_plugin.dart' show ReplayVerificationError;

/// Normalizes a JSON schema type string to uppercase (`'string'` -> `'STRING'`).
Object? normalizeType(Object? value) {
  if (value is String) {
    return value.toUpperCase();
  }
  return value;
}

/// Resolves `$ref` pointers against `$defs` (or `definitions`) inside a JSON
/// schema map and removes the definitions block once resolved.
Map<String, Object?> resolveRefs(
  Map<String, Object?> schema, [
  Map<String, Object?>? defs,
]) {
  final Map<String, Object?> copy = asConformanceObjectMap(
    normalizeConformanceJsonValue(schema),
  );
  final Map<String, Object?> effectiveDefs = <String, Object?>{
    ...?defs,
    if (copy[r'$defs'] is Map) ...asConformanceObjectMap(copy[r'$defs']),
    if (copy['definitions'] is Map)
      ...asConformanceObjectMap(copy['definitions']),
  };
  copy.remove(r'$defs');
  copy.remove('definitions');

  final Object? ref = copy[r'$ref'];
  if (ref is String) {
    const String prefixDefs = r'#/$defs/';
    const String prefixDefinitions = '#/definitions/';
    String? defName;
    if (ref.startsWith(prefixDefs)) {
      defName = ref.substring(prefixDefs.length);
    } else if (ref.startsWith(prefixDefinitions)) {
      defName = ref.substring(prefixDefinitions.length);
    }
    if (defName != null && effectiveDefs[defName] is Map) {
      final Map<String, Object?> resolved = resolveRefs(
        asConformanceObjectMap(effectiveDefs[defName]),
        effectiveDefs,
      );
      final Map<String, Object?> merged = <String, Object?>{...resolved};
      for (final MapEntry<String, Object?> entry in copy.entries) {
        if (entry.key != r'$ref') {
          merged[entry.key] = entry.value;
        }
      }
      return merged;
    }
  }

  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in copy.entries) {
    final Object? value = entry.value;
    if (value is Map) {
      result[entry.key] = resolveRefs(
        asConformanceObjectMap(value),
        effectiveDefs,
      );
    } else if (value is List) {
      result[entry.key] = value
          .map(
            (Object? item) => item is Map
                ? resolveRefs(asConformanceObjectMap(item), effectiveDefs)
                : item,
          )
          .toList();
    } else {
      result[entry.key] = value;
    }
  }
  return result;
}

/// Normalizes a JSON schema dictionary by resolving `$ref` entries, uppercasing
/// `type` strings, and converting `anyOf` with a `NULL` branch into `nullable: true`.
Map<String, Object?> normalizeSchemaDict(Map<String, Object?> schema) {
  final Map<String, Object?> resolved = resolveRefs(schema);
  return _normalizeSchemaNode(resolved);
}

Map<String, Object?> _normalizeSchemaNode(Map<String, Object?> node) {
  final Map<String, Object?> copy = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in node.entries) {
    final String key = entry.key;
    final Object? value = entry.value;
    if (key == 'type') {
      copy[key] = normalizeType(value);
    } else if (key == 'properties' && value is Map) {
      final Map<String, Object?> props = <String, Object?>{};
      for (final MapEntry<String, Object?> prop
          in asConformanceObjectMap(value).entries) {
        props[prop.key] = prop.value is Map
            ? _normalizeSchemaNode(asConformanceObjectMap(prop.value))
            : prop.value;
      }
      copy[key] = props;
    } else if (key == 'items' && value is Map) {
      copy[key] = _normalizeSchemaNode(asConformanceObjectMap(value));
    } else if ((key == 'anyOf' || key == 'any_of') && value is List) {
      final List<Map<String, Object?>> branches = value
          .whereType<Map>()
          .map(
            (Map item) => _normalizeSchemaNode(asConformanceObjectMap(item)),
          )
          .toList();
      final List<Map<String, Object?>> nonNullBranches = branches
          .where((Map<String, Object?> b) => b['type'] != 'NULL')
          .toList();
      final bool hasNullBranch = branches.length != nonNullBranches.length;
      if (hasNullBranch && nonNullBranches.length == 1) {
        copy.addAll(nonNullBranches.first);
        copy['nullable'] = true;
      } else {
        copy[key] = branches;
      }
    } else if (value is Map) {
      copy[key] = _normalizeSchemaNode(asConformanceObjectMap(value));
    } else if (value is List) {
      copy[key] = value
          .map(
            (Object? item) => item is Map
                ? _normalizeSchemaNode(asConformanceObjectMap(item))
                : item,
          )
          .toList();
    } else {
      copy[key] = value;
    }
  }
  return copy;
}

/// Normalizes tool declarations and response schemas inside a serialized
/// `GenerateContentConfig` map so older and newer schema representations match.
Map<String, Object?> normalizeToolConfig(Map<String, Object?> configDict) {
  final Map<String, Object?> copy = asConformanceObjectMap(
    normalizeConformanceJsonValue(configDict),
  );
  if (copy['tools'] is List) {
    copy['tools'] = asConformanceObjectList(copy['tools']).map((Object? tool) {
      if (tool is! Map) {
        return tool;
      }
      final Map<String, Object?> toolMap = asConformanceObjectMap(tool);
      if (toolMap['function_declarations'] is List) {
        toolMap['function_declarations'] =
            asConformanceObjectList(toolMap['function_declarations']).map((
              Object? decl,
            ) {
              if (decl is! Map) {
                return decl;
              }
              final Map<String, Object?> declMap = asConformanceObjectMap(decl);
              if (declMap['parameters_json_schema'] is Map &&
                  declMap['parameters'] == null) {
                declMap['parameters'] = normalizeSchemaDict(
                  asConformanceObjectMap(declMap['parameters_json_schema']),
                );
                declMap.remove('parameters_json_schema');
              } else if (declMap['parameters'] is Map) {
                declMap['parameters'] = normalizeSchemaDict(
                  asConformanceObjectMap(declMap['parameters']),
                );
              }
              if (declMap['response_json_schema'] is Map &&
                  declMap['response'] == null) {
                declMap['response'] = normalizeSchemaDict(
                  asConformanceObjectMap(declMap['response_json_schema']),
                );
                declMap.remove('response_json_schema');
              } else if (declMap['response'] is Map) {
                declMap['response'] = normalizeSchemaDict(
                  asConformanceObjectMap(declMap['response']),
                );
              }
              return declMap;
            }).toList();
      }
      return toolMap;
    }).toList();
  }
  if (copy['response_json_schema'] is Map && copy['response_schema'] == null) {
    copy['response_schema'] = normalizeSchemaDict(
      asConformanceObjectMap(copy['response_json_schema']),
    );
    copy.remove('response_json_schema');
  } else if (copy['response_schema'] is Map) {
    copy['response_schema'] = normalizeSchemaDict(
      asConformanceObjectMap(copy['response_schema']),
    );
  }
  return copy;
}

final RegExp _legacyRelayedTextPattern = RegExp(
  r'^\[([A-Za-z0-9_.-]+)\] said:\s*([\s\S]*)$',
);

/// Normalizes relayed agent text so legacy `For context:` + `[agent] said:`
/// preambles and modern fenced `<<<BEGIN_QUOTED_CONTENT>>>` blocks compare equal.
String? normalizeRelayedAgentText(String? text) {
  if (text == null) {
    return null;
  }
  final String trimmed = text.trim();
  if (trimmed == 'For context:') {
    return otherAgentContextPreamble;
  }
  if (trimmed.contains(quotedContentBegin) &&
      trimmed.contains(quotedContentEnd)) {
    return text;
  }
  final RegExpMatch? match = _legacyRelayedTextPattern.firstMatch(trimmed);
  if (match != null) {
    final String author = match.group(1)!;
    final String body = match.group(2) ?? '';
    return '[$author] said:\n$quotedContentBegin\n$body\n$quotedContentEnd';
  }
  return text;
}

/// Normalizes relayed agent text parts inside a serialized `Content` dictionary.
Map<String, Object?> normalizeRelayedAgentContent(
  Map<String, Object?> contentDict,
) {
  final Map<String, Object?> copy = asConformanceObjectMap(
    normalizeConformanceJsonValue(contentDict),
  );
  if (copy['role'] != 'user' || copy['parts'] is! List) {
    return copy;
  }
  final List<Map<String, Object?>> parts =
      asConformanceObjectList(copy['parts'])
          .map((Object? item) => asConformanceObjectMap(item))
          .toList();
  if (parts.isEmpty) {
    return copy;
  }
  final String? firstText = parts.first['text'] as String?;
  final bool isRelayedContext =
      firstText != null &&
      (firstText.trim() == 'For context:' ||
          firstText.trim() == otherAgentContextPreamble);
  if (!isRelayedContext) {
    return copy;
  }
  for (int i = 0; i < parts.length; i++) {
    final String? partText = parts[i]['text'] as String?;
    if (partText != null) {
      parts[i] = <String, Object?>{
        ...parts[i],
        'text': normalizeRelayedAgentText(partText),
      };
    }
  }
  copy['parts'] = parts;
  return copy;
}

/// Custom [Gemini] model implementation that replays recorded [LlmResponse]
/// messages during conformance replay runs after verifying the [LlmRequest].
class ConformanceTestGemini extends Gemini {
  /// Creates a [ConformanceTestGemini] model.
  ConformanceTestGemini({
    required this.config,
    super.model,
    super.speechConfig,
    super.retryOptions,
  });

  /// Replay configuration dictionary containing `recordings`, `agent_name`,
  /// `user_message_index`, and optional `current_Node` / replay cursors.
  final Map<String, Object?> config;

  final Map<String, int> _agentReplayIndices = <String, int>{};

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final ConformanceRecordings recordings = _extractRecordings();
    final String agentName = '${config['agent_name'] ?? ''}'.trim();
    final int userMessageIndex = _extractUserMessageIndex();
    final String key = '$agentName:$userMessageIndex';
    final int callIndex = _agentReplayIndices[key] ?? 0;

    final List<ConformanceRecording> matching = recordings.recordings.where((
      ConformanceRecording rec,
    ) {
      if (rec.llmRecording == null) {
        return false;
      }
      if (rec.userMessageIndex != userMessageIndex) {
        return false;
      }
      if (agentName.isNotEmpty && rec.agentName != agentName) {
        return false;
      }
      return true;
    }).toList();

    if (callIndex >= matching.length) {
      throw ReplayVerificationError(
        'No recorded LLM interaction found for agent "$agentName" '
        'at user_message_index=$userMessageIndex (call index $callIndex, '
        'available=${matching.length}).',
      );
    }

    final ConformanceLlmRecording llmRecording =
        matching[callIndex].llmRecording!;
    _agentReplayIndices[key] = callIndex + 1;

    _verifyLlmRequest(request, llmRecording.llmRequest, agentName: agentName);

    for (final ConformanceJson responseJson in llmRecording.llmResponses) {
      yield deserializeLlmResponse(responseJson);
    }
  }

  ConformanceRecordings _extractRecordings() {
    final Object? raw = config['recordings'];
    if (raw is ConformanceRecordings) {
      return raw;
    }
    if (raw is Map) {
      return ConformanceRecordings.fromJson(asConformanceObjectMap(raw));
    }
    return ConformanceRecordings();
  }

  int _extractUserMessageIndex() {
    final Object? raw = config['user_message_index'];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse('${raw ?? 0}') ?? 0;
  }

  void _verifyLlmRequest(
    LlmRequest actualRequest,
    ConformanceJson recordedRequestJson, {
    required String agentName,
  }) {
    final ConformanceJson normalizedActual = _prepareRequestForComparison(
      serializeLlmRequest(actualRequest),
    );
    final ConformanceJson normalizedRecorded = _prepareRequestForComparison(
      recordedRequestJson,
    );

    final String actualSig = stableJsonSignature(normalizedActual);
    final String recordedSig = stableJsonSignature(normalizedRecorded);
    if (actualSig != recordedSig) {
      throw ReplayVerificationError(
        'LLM request mismatch for agent "$agentName".\n'
        'Expected: $recordedSig\n'
        'Actual:   $actualSig',
      );
    }
  }

  ConformanceJson _prepareRequestForComparison(ConformanceJson rawRequest) {
    final ConformanceJson canonical = canonicalizeSerializedLlmRequest(
      rawRequest,
    );
    canonical.remove('live_connect_config');
    if (canonical['config'] is Map) {
      final Map<String, Object?> cfg = normalizeToolConfig(
        asConformanceObjectMap(canonical['config']),
      );
      cfg.remove('http_options');
      cfg.remove('labels');
      canonical['config'] = cfg;
    }
    if (canonical['contents'] is List) {
      canonical['contents'] = asConformanceObjectList(canonical['contents'])
          .map(
            (Object? c) => c is Map
                ? normalizeRelayedAgentContent(asConformanceObjectMap(c))
                : c,
          )
          .toList();
    }
    return canonical;
  }
}
