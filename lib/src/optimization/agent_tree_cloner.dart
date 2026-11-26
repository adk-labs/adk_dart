/// Clones an ADK agent hierarchy with dotted parameter overrides applied.
library;

import '../agents/base_agent.dart';
import '../agents/langgraph_agent.dart';
import '../agents/llm_agent.dart';
import '../agents/loop_agent.dart';
import '../agents/remote_a2a_agent.dart';
import '../integrations/openai/openai.dart';
import '../models/anthropic_llm.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../planners/built_in_planner.dart';
import '../tools/agent_tool.dart';

typedef _ChildParams = Map<String, Map<String, Object?>>;

const Map<String, String> _baseFieldAliases = <String, String>{
  'parent_agent': 'parentAgent',
  'sub_agents': 'subAgents',
  'before_agent_callback': 'beforeAgentCallback',
  'after_agent_callback': 'afterAgentCallback',
};

const Set<String> _llmFields = <String>{
  ...BaseAgent.baseCloneUpdateFields,
  'model',
  'instruction',
  'globalInstruction',
  'staticInstruction',
  'tools',
  'generateContentConfig',
  'disallowTransferToParent',
  'disallowTransferToPeers',
  'mode',
  'includeContents',
  'inputSchema',
  'outputSchema',
  'outputKey',
  'planner',
  'codeExecutor',
  'beforeModelCallback',
  'afterModelCallback',
  'onModelErrorCallback',
  'beforeToolCallback',
  'afterToolCallback',
  'onToolErrorCallback',
  'parallelWorker',
  'maxParallelWorkers',
};

const Map<String, String> _llmFieldAliases = <String, String>{
  ..._baseFieldAliases,
  'global_instruction': 'globalInstruction',
  'static_instruction': 'staticInstruction',
  'generate_content_config': 'generateContentConfig',
  'disallow_transfer_to_parent': 'disallowTransferToParent',
  'disallow_transfer_to_peers': 'disallowTransferToPeers',
  'include_contents': 'includeContents',
  'input_schema': 'inputSchema',
  'output_schema': 'outputSchema',
  'output_key': 'outputKey',
  'code_executor': 'codeExecutor',
  'before_model_callback': 'beforeModelCallback',
  'after_model_callback': 'afterModelCallback',
  'on_model_error_callback': 'onModelErrorCallback',
  'before_tool_callback': 'beforeToolCallback',
  'after_tool_callback': 'afterToolCallback',
  'on_tool_error_callback': 'onToolErrorCallback',
  'parallel_worker': 'parallelWorker',
  'max_parallel_workers': 'maxParallelWorkers',
};

const Set<String> _loopFields = <String>{
  ...BaseAgent.baseCloneUpdateFields,
  'maxIterations',
};

const Map<String, String> _loopFieldAliases = <String, String>{
  ..._baseFieldAliases,
  'max_iterations': 'maxIterations',
};

const Set<String> _langGraphFields = <String>{
  ...BaseAgent.baseCloneUpdateFields,
  'invokeGraph',
  'instruction',
  'hasCheckpointer',
  'hasExistingGraphState',
};

const Map<String, String> _langGraphFieldAliases = <String, String>{
  ..._baseFieldAliases,
  'invoke_graph': 'invokeGraph',
  'has_checkpointer': 'hasCheckpointer',
  'has_existing_graph_state': 'hasExistingGraphState',
};

const Set<String> _remoteA2aFields = <String>{
  ...BaseAgent.baseCloneUpdateFields,
  'agentCard',
  'httpClient',
  'timeout',
  'genaiPartConverter',
  'a2aPartConverter',
  'a2aClientFactory',
  'a2aRequestMetaProvider',
  'fullHistoryWhenStateless',
  'config',
  'mode',
  'outputSchema',
};

const Map<String, String> _remoteA2aFieldAliases = <String, String>{
  ..._baseFieldAliases,
  'agent_card': 'agentCard',
  'http_client': 'httpClient',
  'genai_part_converter': 'genaiPartConverter',
  'a2a_part_converter': 'a2aPartConverter',
  'a2a_client_factory': 'a2aClientFactory',
  'a2a_request_meta_provider': 'a2aRequestMetaProvider',
  'full_history_when_stateless': 'fullHistoryWhenStateless',
  'output_schema': 'outputSchema',
};

const Map<String, String> _generateContentConfigFieldMap = <String, String>{
  'tools': 'tools',
  'system_instruction': 'systemInstruction',
  'systemInstruction': 'systemInstruction',
  'temperature': 'temperature',
  'top_p': 'topP',
  'topP': 'topP',
  'top_k': 'topK',
  'topK': 'topK',
  'max_output_tokens': 'maxOutputTokens',
  'maxOutputTokens': 'maxOutputTokens',
  'stop_sequences': 'stopSequences',
  'stopSequences': 'stopSequences',
  'frequency_penalty': 'frequencyPenalty',
  'frequencyPenalty': 'frequencyPenalty',
  'presence_penalty': 'presencePenalty',
  'presencePenalty': 'presencePenalty',
  'seed': 'seed',
  'candidate_count': 'candidateCount',
  'candidateCount': 'candidateCount',
  'response_logprobs': 'responseLogprobs',
  'responseLogprobs': 'responseLogprobs',
  'logprobs': 'logprobs',
  'thinking_config': 'thinkingConfig',
  'thinkingConfig': 'thinkingConfig',
  'response_schema': 'responseSchema',
  'responseSchema': 'responseSchema',
  'response_json_schema': 'responseJsonSchema',
  'responseJsonSchema': 'responseJsonSchema',
  'response_mime_type': 'responseMimeType',
  'responseMimeType': 'responseMimeType',
  'response_modalities': 'responseModalities',
  'responseModalities': 'responseModalities',
  'speech_config': 'speechConfig',
  'speechConfig': 'speechConfig',
  'tool_config': 'toolConfig',
  'toolConfig': 'toolConfig',
  'automatic_function_calling': 'automaticFunctionCalling',
  'automaticFunctionCalling': 'automaticFunctionCalling',
  'cached_content': 'cachedContent',
  'cachedContent': 'cachedContent',
  'http_options': 'httpOptions',
  'httpOptions': 'httpOptions',
  'labels': 'labels',
  'safety_settings': 'safetySettings',
  'safetySettings': 'safetySettings',
  'should_return_http_response': 'shouldReturnHttpResponse',
  'shouldReturnHttpResponse': 'shouldReturnHttpResponse',
  'routing_config': 'routingConfig',
  'routingConfig': 'routingConfig',
  'model_selection_config': 'modelSelectionConfig',
  'modelSelectionConfig': 'modelSelectionConfig',
  'media_resolution': 'mediaResolution',
  'mediaResolution': 'mediaResolution',
  'audio_timestamp': 'audioTimestamp',
  'audioTimestamp': 'audioTimestamp',
  'image_config': 'imageConfig',
  'imageConfig': 'imageConfig',
  'model_armor_config': 'modelArmorConfig',
  'modelArmorConfig': 'modelArmorConfig',
  'service_tier': 'serviceTier',
  'serviceTier': 'serviceTier',
  'audio_transcription_config': 'audioTranscriptionConfig',
  'audioTranscriptionConfig': 'audioTranscriptionConfig',
  'continuation_token': 'continuationToken',
  'continuationToken': 'continuationToken',
  'automatic_continuation': 'automaticContinuation',
  'automaticContinuation': 'automaticContinuation',
  'generation_output_config': 'generationOutputConfig',
  'generationOutputConfig': 'generationOutputConfig',
  'enable_enhanced_civic_answers': 'enableEnhancedCivicAnswers',
  'enableEnhancedCivicAnswers': 'enableEnhancedCivicAnswers',
  'store': 'store',
  'enable_affective_dialog': 'enableAffectiveDialog',
  'enableAffectiveDialog': 'enableAffectiveDialog',
};

const Map<String, String> _httpOptionsFieldMap = <String, String>{
  'retry_options': 'retryOptions',
  'retryOptions': 'retryOptions',
  'headers': 'headers',
  'api_version': 'apiVersion',
  'apiVersion': 'apiVersion',
};

const Map<String, String> _httpRetryOptionsFieldMap = <String, String>{
  'attempts': 'attempts',
  'initial_delay': 'initialDelay',
  'initialDelay': 'initialDelay',
  'max_delay': 'maxDelay',
  'maxDelay': 'maxDelay',
  'exp_base': 'expBase',
  'expBase': 'expBase',
  'http_status_codes': 'httpStatusCodes',
  'httpStatusCodes': 'httpStatusCodes',
};

const Map<String, String> _toolConfigFieldMap = <String, String>{
  'function_calling_config': 'functionCallingConfig',
  'functionCallingConfig': 'functionCallingConfig',
};

const Map<String, String> _functionCallingConfigFieldMap = <String, String>{
  'mode': 'mode',
  'allowed_function_names': 'allowedFunctionNames',
  'allowedFunctionNames': 'allowedFunctionNames',
};

const Map<String, String> _automaticFunctionCallingFieldMap = <String, String>{
  'disable': 'disable',
  'maximum_remote_calls': 'maximumRemoteCalls',
  'maximumRemoteCalls': 'maximumRemoteCalls',
};

const Map<String, String> _thinkingConfigAliasMap = <String, String>{
  'include_thoughts': 'include_thoughts',
  'includeThoughts': 'include_thoughts',
  'thinking_budget': 'thinking_budget',
  'thinkingBudget': 'thinking_budget',
  'thinking_level': 'thinking_level',
  'thinkingLevel': 'thinking_level',
};

(Set<String>, Map<String, String>) _agentFieldSpec(BaseAgent agent) {
  if (agent is LlmAgent) {
    return (_llmFields, _llmFieldAliases);
  }
  if (agent is LoopAgent) {
    return (_loopFields, _loopFieldAliases);
  }
  if (agent is LangGraphAgent) {
    return (_langGraphFields, _langGraphFieldAliases);
  }
  if (agent is RemoteA2aAgent) {
    return (_remoteA2aFields, _remoteA2aFieldAliases);
  }
  return (BaseAgent.baseCloneUpdateFields, _baseFieldAliases);
}

bool _isAutoBuiltModeTool(AgentTool tool) {
  final BaseAgent wrapped = tool.agent;
  String? wrappedMode;
  if (wrapped is LlmAgent) {
    wrappedMode = wrapped.mode;
  } else if (wrapped is RemoteA2aAgent) {
    wrappedMode = wrapped.mode;
  }
  if (tool is SingleTurnAgentTool) {
    return wrappedMode == 'single_turn';
  }
  if (tool is TaskAgentTool) {
    return wrappedMode == 'task';
  }
  return false;
}

Map<String, Object?> _copyMapping(Map<Object?, Object?> mapping) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in mapping.entries)
      '${entry.key}': entry.value is Map
          ? _copyMapping(entry.value as Map<Object?, Object?>)
          : entry.value,
  };
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _deepCopyValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final Object? item in value) _deepCopyValue(item)];
  }
  if (value is HttpOptions) {
    return value.copyWith();
  }
  if (value is HttpRetryOptions) {
    return value.copyWith();
  }
  if (value is LlmToolConfig) {
    return value.copyWith();
  }
  if (value is FunctionCallingConfig) {
    return value.copyWith();
  }
  if (value is AutomaticFunctionCallingConfig) {
    return value.copyWith();
  }
  if (value is ToolDeclaration) {
    return value.copyWith();
  }
  if (value is FunctionDeclaration) {
    return value.copyWith();
  }
  return value;
}

(String, String, String) _partitionDotted(String input) {
  final int dot = input.indexOf('.');
  if (dot < 0) {
    return (input, '', '');
  }
  return (input.substring(0, dot), '.', input.substring(dot + 1));
}

String _formatSortedNames(Iterable<String> names) {
  final List<String> sorted = names.toList()..sort();
  if (sorted.isEmpty) {
    return 'none';
  }
  return "[${sorted.map((String n) => "'$n'").join(', ')}]";
}

(Map<String, Object?>, _ChildParams, _ChildParams) _partitionAgentParams(
  BaseAgent agent,
  Map<String, Object?> flatParams,
) {
  final (Set<String> fields, Map<String, String> aliases) = _agentFieldSpec(
    agent,
  );
  final Object? rawSubsObj = flatParams.containsKey('sub_agents')
      ? flatParams['sub_agents']
      : (flatParams.containsKey('subAgents')
            ? flatParams['subAgents']
            : agent.subAgents);
  final List<Object?> rawSubs = rawSubsObj is List
      ? rawSubsObj
      : const <Object?>[];
  final Map<String, BaseAgent> subChildren = <String, BaseAgent>{
    for (final Object? child in rawSubs)
      if (child is BaseAgent) child.name: child,
  };
  final Set<BaseAgent> subIds = Set<BaseAgent>.identity()
    ..addAll(subChildren.values);

  final Object? rawToolsObj = flatParams.containsKey('tools')
      ? flatParams['tools']
      : (agent is LlmAgent ? agent.tools : null);
  final List<Object?> rawTools = rawToolsObj is List
      ? rawToolsObj
      : const <Object?>[];
  final Map<String, BaseAgent> toolChildren = <String, BaseAgent>{};
  for (final Object? tool in rawTools) {
    if (tool is AgentTool && !subIds.contains(tool.agent)) {
      toolChildren[tool.agent.name] = tool.agent;
    }
  }

  final Map<String, Object?> direct = <String, Object?>{};
  final _ChildParams subParams = <String, Map<String, Object?>>{};
  final _ChildParams toolParams = <String, Map<String, Object?>>{};

  for (final MapEntry<String, Object?> entry in flatParams.entries) {
    final String key = entry.key;
    final Object? value = entry.value;
    if (key.startsWith('sub_agents.')) {
      final (String childName, String _, String rest) = _partitionDotted(
        key.substring('sub_agents.'.length),
      );
      if (!subChildren.containsKey(childName)) {
        throw ArgumentError(
          "Parameter '$key': agent '${agent.name}' has no sub-agent named "
          "'$childName'. Sub-agents: ${_formatSortedNames(subChildren.keys)}.",
        );
      }
      if (rest.isEmpty) {
        throw ArgumentError(
          "Parameter '$key' names sub-agent '$childName' but no field.",
        );
      }
      (subParams[childName] ??= <String, Object?>{})[rest] = value;
    } else if (key.startsWith('tools.')) {
      final (String childName, String _, String rest) = _partitionDotted(
        key.substring('tools.'.length),
      );
      if (!toolChildren.containsKey(childName)) {
        final String hint =
            subChildren.containsKey(childName) && rest.isNotEmpty
            ? " ('$childName' is in sub_agents; use 'sub_agents.$childName.$rest'.)"
            : '';
        throw ArgumentError(
          "Parameter '$key': agent '${agent.name}' has no AgentTool agent "
          "named '$childName'.$hint AgentTools: "
          '${_formatSortedNames(toolChildren.keys)}.',
        );
      }
      if (rest.isEmpty) {
        throw ArgumentError(
          "Parameter '$key' names AgentTool '$childName' but no field.",
        );
      }
      (toolParams[childName] ??= <String, Object?>{})[rest] = value;
    } else if (key.startsWith('generate_content_config.')) {
      if (!fields.contains('generateContentConfig')) {
        throw ArgumentError(
          "Parameter '$key': ${agent.runtimeType} ('${agent.name}') has no "
          'generate_content_config field.',
        );
      }
      if (key.substring('generate_content_config.'.length).isEmpty) {
        throw ArgumentError("Parameter '$key' names no config field.");
      }
      direct[key] = value;
    } else if (key.contains('.')) {
      final (String head, String _, String _) = _partitionDotted(key);
      final String resolvedHead = aliases[head] ?? head;
      if (fields.contains(resolvedHead)) {
        throw ArgumentError(
          "Parameter '$key' sets a field inside '$head'; only "
          "'generate_content_config.<field>', 'sub_agents.<Name>.<field>', "
          "and 'tools.<Name>.<field>' support dotted paths.",
        );
      }
      throw ArgumentError(
        "Parameter '$key' is not valid on '${agent.name}'. Prefix child "
        "agents with 'sub_agents.' or 'tools.' and generation settings with "
        "'generate_content_config.'.",
      );
    } else {
      final String canonicalKey = aliases[key] ?? key;
      if (!fields.contains(canonicalKey)) {
        throw ArgumentError(
          "Parameter '$key' is not a field of ${agent.runtimeType} "
          "('${agent.name}'); use 'generate_content_config.$key' for "
          'generation settings.',
        );
      }
      if (direct.containsKey(canonicalKey)) {
        throw ArgumentError(
          "Duplicate override for '$key' via both field name and alias.",
        );
      }
      direct[canonicalKey] = value;
    }
  }

  return (direct, subParams, toolParams);
}

Map<String, Object?> _expandDottedMapping(Map<String, Object?> flatParams) {
  final Map<String, Object?> nested = <String, Object?>{};
  final Set<String> leafPaths = <String>{};
  final List<String> sortedKeys = flatParams.keys.toList()
    ..sort((String a, String b) {
      final int dotsA = '.'.allMatches(a).length;
      final int dotsB = '.'.allMatches(b).length;
      if (dotsA != dotsB) {
        return dotsA.compareTo(dotsB);
      }
      return a.compareTo(b);
    });

  for (final String key in sortedKeys) {
    Map<String, Object?> cursor = nested;
    final List<String> parts = key.split('.');
    for (int depth = 0; depth < parts.length - 1; depth += 1) {
      final String prefix = parts.sublist(0, depth + 1).join('.');
      if (leafPaths.contains(prefix)) {
        throw ArgumentError(
          "Parameter 'generate_content_config.$key' sets a field inside "
          "'generate_content_config.$prefix', which the grid also sets as a "
          'whole.',
        );
      }
      final Object? existing = cursor[parts[depth]];
      if (existing is Map<String, Object?>) {
        cursor = existing;
      } else {
        final Map<String, Object?> next = <String, Object?>{};
        cursor[parts[depth]] = next;
        cursor = next;
      }
    }
    final Object? value = flatParams[key];
    cursor[parts.last] = value is Map
        ? _copyMapping(value as Map<Object?, Object?>)
        : value;
    leafPaths.add(key);
  }
  return nested;
}

Object? _mergeNestedMap(
  Object? current,
  Object? override,
  String prefix, {
  Map<String, String>? keyAliases,
}) {
  if (override is! Map) {
    return _deepCopyValue(override);
  }
  final Map<String, Object?> merged = current is Map
      ? _copyMapping(current as Map<Object?, Object?>)
      : <String, Object?>{};
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String canonicalKey = keyAliases?[rawKey] ?? rawKey;
    if (!seen.add(canonicalKey)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.$prefix$canonicalKey' "
        'via both field name and alias.',
      );
    }
    merged[canonicalKey] = _mergeNestedMap(
      merged[canonicalKey],
      entry.value,
      '$prefix$canonicalKey.',
    );
  }
  return merged;
}

double? _asDouble(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError("Invalid numeric value for '$fieldPath': $value");
}

int? _asInt(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw ArgumentError("Invalid integer value for '$fieldPath': $value");
}

bool? _asBool(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw ArgumentError("Invalid boolean value for '$fieldPath': $value");
}

String? _asString(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw ArgumentError("Invalid string value for '$fieldPath': $value");
}

List<String>? _asStringList(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return <String>[
      for (final Object? item in value)
        item is String
            ? item
            : throw ArgumentError(
                "Invalid string list element in '$fieldPath': $item",
              ),
    ];
  }
  throw ArgumentError("Invalid list value for '$fieldPath': $value");
}

List<int>? _asIntList(Object? value, String fieldPath) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return <int>[
      for (final Object? item in value)
        item is int
            ? item
            : throw ArgumentError(
                "Invalid int list element in '$fieldPath': $item",
              ),
    ];
  }
  throw ArgumentError("Invalid list value for '$fieldPath': $value");
}

Map<String, String> _asStringMap(Object? value, String fieldPath) {
  if (value == null) {
    return <String, String>{};
  }
  if (value is Map) {
    return <String, String>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': entry.value is String
            ? entry.value as String
            : throw ArgumentError(
                "Invalid string map value for '$fieldPath.${entry.key}': "
                '${entry.value}',
              ),
    };
  }
  throw ArgumentError("Invalid map value for '$fieldPath': $value");
}

FunctionCallingConfigMode _asFunctionCallingMode(
  Object? value,
  String fieldPath,
) {
  if (value is FunctionCallingConfigMode) {
    return value;
  }
  if (value is String) {
    final String normalized = value.trim().toUpperCase();
    switch (normalized) {
      case 'AUTO':
        return FunctionCallingConfigMode.auto;
      case 'ANY':
        return FunctionCallingConfigMode.any;
      case 'NONE':
        return FunctionCallingConfigMode.none;
      case 'MODE_UNSPECIFIED':
      case 'MODEUNSPECIFIED':
        return FunctionCallingConfigMode.modeUnspecified;
    }
  }
  throw ArgumentError(
    "Invalid FunctionCallingConfigMode for '$fieldPath': $value",
  );
}

HttpRetryOptions? _mergeHttpRetryOptions(
  HttpRetryOptions? current,
  Object? override,
) {
  if (override == null) {
    return null;
  }
  if (override is HttpRetryOptions) {
    return override.copyWith();
  }
  if (override is! Map) {
    throw ArgumentError(
      'Invalid value for generate_content_config.http_options.retry_options: '
      '$override',
    );
  }
  final HttpRetryOptions base = current?.copyWith() ?? HttpRetryOptions();
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String? canonical = _httpRetryOptionsFieldMap[rawKey];
    if (canonical == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on HttpRetryOptions in "
        'generate_content_config.http_options.retry_options.',
      );
    }
    if (!seen.add(canonical)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.http_options."
        "retry_options.$canonical' via both field name and alias.",
      );
    }
    switch (canonical) {
      case 'attempts':
        base.attempts = _asInt(entry.value, 'http_options.retry_options.attempts');
      case 'initialDelay':
        base.initialDelay = _asDouble(
          entry.value,
          'http_options.retry_options.initial_delay',
        );
      case 'maxDelay':
        base.maxDelay = _asDouble(
          entry.value,
          'http_options.retry_options.max_delay',
        );
      case 'expBase':
        base.expBase = _asDouble(
          entry.value,
          'http_options.retry_options.exp_base',
        );
      case 'httpStatusCodes':
        base.httpStatusCodes =
            _asIntList(
              entry.value,
              'http_options.retry_options.http_status_codes',
            ) ??
            <int>[];
    }
  }
  return base;
}

HttpOptions? _mergeHttpOptions(HttpOptions? current, Object? override) {
  if (override == null) {
    return null;
  }
  if (override is HttpOptions) {
    return override.copyWith();
  }
  if (override is! Map) {
    throw ArgumentError(
      'Invalid value for generate_content_config.http_options: $override',
    );
  }
  final HttpOptions base = current?.copyWith() ?? HttpOptions();
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String? canonical = _httpOptionsFieldMap[rawKey];
    if (canonical == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on HttpOptions in "
        'generate_content_config.http_options.',
      );
    }
    if (!seen.add(canonical)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.http_options."
        "$canonical' via both field name and alias.",
      );
    }
    switch (canonical) {
      case 'retryOptions':
        base.retryOptions = _mergeHttpRetryOptions(
          base.retryOptions,
          entry.value,
        );
      case 'headers':
        final Object? merged = _mergeNestedMap(
          base.headers,
          entry.value,
          'http_options.headers.',
        );
        base.headers = _asStringMap(merged, 'http_options.headers');
      case 'apiVersion':
        base.apiVersion = _asString(entry.value, 'http_options.api_version');
    }
  }
  return base;
}

FunctionCallingConfig? _mergeFunctionCallingConfig(
  FunctionCallingConfig? current,
  Object? override,
) {
  if (override == null) {
    return null;
  }
  if (override is FunctionCallingConfig) {
    return override.copyWith();
  }
  if (override is! Map) {
    throw ArgumentError(
      'Invalid value for tool_config.function_calling_config: $override',
    );
  }
  final FunctionCallingConfig base =
      current?.copyWith() ?? FunctionCallingConfig();
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String? canonical = _functionCallingConfigFieldMap[rawKey];
    if (canonical == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on FunctionCallingConfig in "
        'generate_content_config.tool_config.function_calling_config.',
      );
    }
    if (!seen.add(canonical)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.tool_config."
        "function_calling_config.$canonical' via both field name and alias.",
      );
    }
    switch (canonical) {
      case 'mode':
        base.mode = _asFunctionCallingMode(
          entry.value,
          'tool_config.function_calling_config.mode',
        );
      case 'allowedFunctionNames':
        base.allowedFunctionNames =
            _asStringList(
              entry.value,
              'tool_config.function_calling_config.allowed_function_names',
            ) ??
            <String>[];
    }
  }
  return base;
}

LlmToolConfig? _mergeToolConfig(LlmToolConfig? current, Object? override) {
  if (override == null) {
    return null;
  }
  if (override is LlmToolConfig) {
    return override.copyWith();
  }
  if (override is! Map) {
    throw ArgumentError('Invalid value for tool_config: $override');
  }
  final LlmToolConfig base = current?.copyWith() ?? LlmToolConfig();
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String? canonical = _toolConfigFieldMap[rawKey];
    if (canonical == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on LlmToolConfig in "
        'generate_content_config.tool_config.',
      );
    }
    if (!seen.add(canonical)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.tool_config."
        "$canonical' via both field name and alias.",
      );
    }
    if (canonical == 'functionCallingConfig') {
      base.functionCallingConfig = _mergeFunctionCallingConfig(
        base.functionCallingConfig,
        entry.value,
      );
    }
  }
  return base;
}

AutomaticFunctionCallingConfig? _mergeAutomaticFunctionCalling(
  AutomaticFunctionCallingConfig? current,
  Object? override,
) {
  if (override == null) {
    return null;
  }
  if (override is AutomaticFunctionCallingConfig) {
    return override.copyWith();
  }
  if (override is! Map) {
    throw ArgumentError(
      'Invalid value for automatic_function_calling: $override',
    );
  }
  final AutomaticFunctionCallingConfig base =
      current?.copyWith() ?? AutomaticFunctionCallingConfig();
  final Set<String> seen = <String>{};
  for (final MapEntry<Object?, Object?> entry in override.entries) {
    final String rawKey = '${entry.key}';
    final String? canonical = _automaticFunctionCallingFieldMap[rawKey];
    if (canonical == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on AutomaticFunctionCallingConfig in "
        'generate_content_config.automatic_function_calling.',
      );
    }
    if (!seen.add(canonical)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config."
        "automatic_function_calling.$canonical' via both field name and alias.",
      );
    }
    switch (canonical) {
      case 'disable':
        base.disable =
            _asBool(entry.value, 'automatic_function_calling.disable') ?? false;
      case 'maximumRemoteCalls':
        base.maximumRemoteCalls = _asInt(
          entry.value,
          'automatic_function_calling.maximum_remote_calls',
        );
    }
  }
  return base;
}

GenerateContentConfig _copyGenerateContentConfig(GenerateContentConfig config) {
  final List<ToolDeclaration>? copiedTools = config.tools
      ?.map((ToolDeclaration t) => t.copyWith())
      .toList();
  final List<String> copiedStop = List<String>.from(config.stopSequences);
  final List<String>? copiedModalities = config.responseModalities == null
      ? null
      : List<String>.from(config.responseModalities!);
  final LlmToolConfig? copiedToolConfig = config.toolConfig?.copyWith();
  final AutomaticFunctionCallingConfig? copiedAfc = config
      .automaticFunctionCalling
      ?.copyWith();
  final HttpOptions? copiedHttp = config.httpOptions?.copyWith();
  final Map<String, String> copiedLabels = Map<String, String>.from(
    config.labels,
  );
  final List<Object?>? copiedSafety = config.safetySettings == null
      ? null
      : _deepCopyValue(config.safetySettings) as List<Object?>;
  final Object? copiedThinking = _deepCopyValue(config.thinkingConfig);
  final Object? copiedResponseSchema = _deepCopyValue(config.responseSchema);
  final Object? copiedResponseJsonSchema = _deepCopyValue(
    config.responseJsonSchema,
  );
  final Object? copiedSpeech = _deepCopyValue(config.speechConfig);
  final Object? copiedRouting = _deepCopyValue(config.routingConfig);
  final Object? copiedModelSelection = _deepCopyValue(
    config.modelSelectionConfig,
  );
  final Object? copiedMediaRes = _deepCopyValue(config.mediaResolution);
  final Object? copiedImageConfig = _deepCopyValue(config.imageConfig);
  final Object? copiedModelArmor = _deepCopyValue(config.modelArmorConfig);
  final Object? copiedServiceTier = _deepCopyValue(config.serviceTier);
  final Object? copiedAudioTrans = _deepCopyValue(
    config.audioTranscriptionConfig,
  );
  final Object? copiedContToken = _deepCopyValue(config.continuationToken);
  final Object? copiedGenOutput = _deepCopyValue(config.generationOutputConfig);

  if (config is AnthropicGenerateContentConfig) {
    return AnthropicGenerateContentConfig(
        effort: config.effort,
        tools: copiedTools,
        systemInstruction: config.systemInstruction,
        temperature: config.temperature,
        topP: config.topP,
        topK: config.topK,
        maxOutputTokens: config.maxOutputTokens,
        stopSequences: copiedStop,
        frequencyPenalty: config.frequencyPenalty,
        presencePenalty: config.presencePenalty,
        seed: config.seed,
        candidateCount: config.candidateCount,
        responseLogprobs: config.responseLogprobs,
        logprobs: config.logprobs,
        thinkingConfig: copiedThinking,
        responseSchema: copiedResponseSchema,
        responseJsonSchema: copiedResponseJsonSchema,
        responseMimeType: config.responseMimeType,
        toolConfig: copiedToolConfig,
        automaticFunctionCalling: copiedAfc,
        cachedContent: config.cachedContent,
        httpOptions: copiedHttp,
        labels: copiedLabels,
      )
      ..responseModalities = copiedModalities
      ..speechConfig = copiedSpeech
      ..safetySettings = copiedSafety
      ..shouldReturnHttpResponse = config.shouldReturnHttpResponse
      ..routingConfig = copiedRouting
      ..modelSelectionConfig = copiedModelSelection
      ..mediaResolution = copiedMediaRes
      ..audioTimestamp = config.audioTimestamp
      ..imageConfig = copiedImageConfig
      ..modelArmorConfig = copiedModelArmor
      ..serviceTier = copiedServiceTier
      ..audioTranscriptionConfig = copiedAudioTrans
      ..continuationToken = copiedContToken
      ..automaticContinuation = config.automaticContinuation
      ..generationOutputConfig = copiedGenOutput
      ..enableEnhancedCivicAnswers = config.enableEnhancedCivicAnswers
      ..store = config.store
      ..enableAffectiveDialog = config.enableAffectiveDialog;
  }

  if (config is OpenAIGenerateContentConfig) {
    return OpenAIGenerateContentConfig(
        effort: config.effort,
        tools: copiedTools,
        systemInstruction: config.systemInstruction,
        temperature: config.temperature,
        topP: config.topP,
        topK: config.topK,
        maxOutputTokens: config.maxOutputTokens,
        stopSequences: copiedStop,
        frequencyPenalty: config.frequencyPenalty,
        presencePenalty: config.presencePenalty,
        seed: config.seed,
        candidateCount: config.candidateCount,
        responseLogprobs: config.responseLogprobs,
        logprobs: config.logprobs,
        thinkingConfig: copiedThinking,
        responseSchema: copiedResponseSchema,
        responseJsonSchema: copiedResponseJsonSchema,
        responseMimeType: config.responseMimeType,
        responseModalities: copiedModalities,
        speechConfig: copiedSpeech,
        toolConfig: copiedToolConfig,
        automaticFunctionCalling: copiedAfc,
        cachedContent: config.cachedContent,
        httpOptions: copiedHttp,
        labels: copiedLabels,
      )
      ..safetySettings = copiedSafety
      ..shouldReturnHttpResponse = config.shouldReturnHttpResponse
      ..routingConfig = copiedRouting
      ..modelSelectionConfig = copiedModelSelection
      ..mediaResolution = copiedMediaRes
      ..audioTimestamp = config.audioTimestamp
      ..imageConfig = copiedImageConfig
      ..modelArmorConfig = copiedModelArmor
      ..serviceTier = copiedServiceTier
      ..audioTranscriptionConfig = copiedAudioTrans
      ..continuationToken = copiedContToken
      ..automaticContinuation = config.automaticContinuation
      ..generationOutputConfig = copiedGenOutput
      ..enableEnhancedCivicAnswers = config.enableEnhancedCivicAnswers
      ..store = config.store
      ..enableAffectiveDialog = config.enableAffectiveDialog;
  }

  return GenerateContentConfig(
    tools: copiedTools,
    systemInstruction: config.systemInstruction,
    temperature: config.temperature,
    topP: config.topP,
    topK: config.topK,
    maxOutputTokens: config.maxOutputTokens,
    stopSequences: copiedStop,
    frequencyPenalty: config.frequencyPenalty,
    presencePenalty: config.presencePenalty,
    seed: config.seed,
    candidateCount: config.candidateCount,
    responseLogprobs: config.responseLogprobs,
    logprobs: config.logprobs,
    thinkingConfig: copiedThinking,
    responseSchema: copiedResponseSchema,
    responseJsonSchema: copiedResponseJsonSchema,
    responseMimeType: config.responseMimeType,
    responseModalities: copiedModalities,
    speechConfig: copiedSpeech,
    toolConfig: copiedToolConfig,
    automaticFunctionCalling: copiedAfc,
    cachedContent: config.cachedContent,
    httpOptions: copiedHttp,
    labels: copiedLabels,
    safetySettings: copiedSafety,
    shouldReturnHttpResponse: config.shouldReturnHttpResponse,
    routingConfig: copiedRouting,
    modelSelectionConfig: copiedModelSelection,
    mediaResolution: copiedMediaRes,
    audioTimestamp: config.audioTimestamp,
    imageConfig: copiedImageConfig,
    modelArmorConfig: copiedModelArmor,
    serviceTier: copiedServiceTier,
    audioTranscriptionConfig: copiedAudioTrans,
    continuationToken: copiedContToken,
    automaticContinuation: config.automaticContinuation,
    generationOutputConfig: copiedGenOutput,
    enableEnhancedCivicAnswers: config.enableEnhancedCivicAnswers,
    store: config.store,
    enableAffectiveDialog: config.enableAffectiveDialog,
  );
}

GenerateContentConfig _buildConfigFromSeedAndMerged({
  required GenerateContentConfig? base,
  required Map<String, Object?> canonicalUpdates,
  required bool preserveBaseFields,
}) {
  final GenerateContentConfig working = preserveBaseFields && base != null
      ? _copyGenerateContentConfig(base)
      : GenerateContentConfig();

  for (final MapEntry<String, Object?> entry in canonicalUpdates.entries) {
    final String key = entry.key;
    final Object? value = entry.value;
    switch (key) {
      case 'tools':
        if (value == null) {
          working.tools = null;
        } else if (value is List) {
          working.tools = <ToolDeclaration>[
            for (final Object? item in value)
              item is ToolDeclaration
                  ? item.copyWith()
                  : throw ArgumentError("Invalid 'tools' element: $item"),
          ];
        } else {
          throw ArgumentError("Invalid 'tools' value: $value");
        }
      case 'systemInstruction':
        working.systemInstruction = _asString(value, key);
      case 'temperature':
        working.temperature = _asDouble(value, key);
      case 'topP':
        working.topP = _asDouble(value, key);
      case 'topK':
        working.topK = _asInt(value, key);
      case 'maxOutputTokens':
        working.maxOutputTokens = _asInt(value, key);
      case 'stopSequences':
        working.stopSequences = _asStringList(value, key) ?? <String>[];
      case 'frequencyPenalty':
        working.frequencyPenalty = _asDouble(value, key);
      case 'presencePenalty':
        working.presencePenalty = _asDouble(value, key);
      case 'seed':
        working.seed = _asInt(value, key);
      case 'candidateCount':
        working.candidateCount = _asInt(value, key);
      case 'responseLogprobs':
        working.responseLogprobs = _asBool(value, key);
      case 'logprobs':
        working.logprobs = _asInt(value, key);
      case 'thinkingConfig':
        working.thinkingConfig = _deepCopyValue(value);
      case 'responseSchema':
        working.responseSchema = _deepCopyValue(value);
      case 'responseJsonSchema':
        working.responseJsonSchema = _deepCopyValue(value);
      case 'responseMimeType':
        working.responseMimeType = _asString(value, key);
      case 'responseModalities':
        working.responseModalities = _asStringList(value, key);
      case 'speechConfig':
        working.speechConfig = _deepCopyValue(value);
      case 'toolConfig':
        working.toolConfig = value as LlmToolConfig?;
      case 'automaticFunctionCalling':
        working.automaticFunctionCalling =
            value as AutomaticFunctionCallingConfig?;
      case 'cachedContent':
        working.cachedContent = _asString(value, key);
      case 'httpOptions':
        working.httpOptions = value as HttpOptions?;
      case 'labels':
        working.labels = _asStringMap(value, key);
      case 'safetySettings':
        working.safetySettings = value == null
            ? null
            : _deepCopyValue(value) as List<Object?>;
      case 'shouldReturnHttpResponse':
        working.shouldReturnHttpResponse = _asBool(value, key);
      case 'routingConfig':
        working.routingConfig = _deepCopyValue(value);
      case 'modelSelectionConfig':
        working.modelSelectionConfig = _deepCopyValue(value);
      case 'mediaResolution':
        working.mediaResolution = _deepCopyValue(value);
      case 'audioTimestamp':
        working.audioTimestamp = _asBool(value, key);
      case 'imageConfig':
        working.imageConfig = _deepCopyValue(value);
      case 'modelArmorConfig':
        working.modelArmorConfig = _deepCopyValue(value);
      case 'serviceTier':
        working.serviceTier = _deepCopyValue(value);
      case 'audioTranscriptionConfig':
        working.audioTranscriptionConfig = _deepCopyValue(value);
      case 'continuationToken':
        working.continuationToken = _deepCopyValue(value);
      case 'automaticContinuation':
        working.automaticContinuation = _asBool(value, key);
      case 'generationOutputConfig':
        working.generationOutputConfig = _deepCopyValue(value);
      case 'enableEnhancedCivicAnswers':
        working.enableEnhancedCivicAnswers = _asBool(value, key);
      case 'store':
        working.store = _asBool(value, key);
      case 'enableAffectiveDialog':
        working.enableAffectiveDialog = _asBool(value, key);
      case 'effort':
        // Applied when constructing subclass below.
        break;
    }
  }

  if (base is AnthropicGenerateContentConfig) {
    final String? effort = canonicalUpdates.containsKey('effort')
        ? _asString(canonicalUpdates['effort'], 'effort')
        : (preserveBaseFields ? base.effort : null);
    return AnthropicGenerateContentConfig(
        effort: effort,
        tools: working.tools,
        systemInstruction: working.systemInstruction,
        temperature: working.temperature,
        topP: working.topP,
        topK: working.topK,
        maxOutputTokens: working.maxOutputTokens,
        stopSequences: working.stopSequences,
        frequencyPenalty: working.frequencyPenalty,
        presencePenalty: working.presencePenalty,
        seed: working.seed,
        candidateCount: working.candidateCount,
        responseLogprobs: working.responseLogprobs,
        logprobs: working.logprobs,
        thinkingConfig: working.thinkingConfig,
        responseSchema: working.responseSchema,
        responseJsonSchema: working.responseJsonSchema,
        responseMimeType: working.responseMimeType,
        toolConfig: working.toolConfig,
        automaticFunctionCalling: working.automaticFunctionCalling,
        cachedContent: working.cachedContent,
        httpOptions: working.httpOptions,
        labels: working.labels,
      )
      ..responseModalities = working.responseModalities
      ..speechConfig = working.speechConfig
      ..safetySettings = working.safetySettings
      ..shouldReturnHttpResponse = working.shouldReturnHttpResponse
      ..routingConfig = working.routingConfig
      ..modelSelectionConfig = working.modelSelectionConfig
      ..mediaResolution = working.mediaResolution
      ..audioTimestamp = working.audioTimestamp
      ..imageConfig = working.imageConfig
      ..modelArmorConfig = working.modelArmorConfig
      ..serviceTier = working.serviceTier
      ..audioTranscriptionConfig = working.audioTranscriptionConfig
      ..continuationToken = working.continuationToken
      ..automaticContinuation = working.automaticContinuation
      ..generationOutputConfig = working.generationOutputConfig
      ..enableEnhancedCivicAnswers = working.enableEnhancedCivicAnswers
      ..store = working.store
      ..enableAffectiveDialog = working.enableAffectiveDialog;
  }

  if (base is OpenAIGenerateContentConfig) {
    final String? effort = canonicalUpdates.containsKey('effort')
        ? _asString(canonicalUpdates['effort'], 'effort')
        : (preserveBaseFields ? base.effort : null);
    return OpenAIGenerateContentConfig(
        effort: effort,
        tools: working.tools,
        systemInstruction: working.systemInstruction,
        temperature: working.temperature,
        topP: working.topP,
        topK: working.topK,
        maxOutputTokens: working.maxOutputTokens,
        stopSequences: working.stopSequences,
        frequencyPenalty: working.frequencyPenalty,
        presencePenalty: working.presencePenalty,
        seed: working.seed,
        candidateCount: working.candidateCount,
        responseLogprobs: working.responseLogprobs,
        logprobs: working.logprobs,
        thinkingConfig: working.thinkingConfig,
        responseSchema: working.responseSchema,
        responseJsonSchema: working.responseJsonSchema,
        responseMimeType: working.responseMimeType,
        responseModalities: working.responseModalities,
        speechConfig: working.speechConfig,
        toolConfig: working.toolConfig,
        automaticFunctionCalling: working.automaticFunctionCalling,
        cachedContent: working.cachedContent,
        httpOptions: working.httpOptions,
        labels: working.labels,
      )
      ..safetySettings = working.safetySettings
      ..shouldReturnHttpResponse = working.shouldReturnHttpResponse
      ..routingConfig = working.routingConfig
      ..modelSelectionConfig = working.modelSelectionConfig
      ..mediaResolution = working.mediaResolution
      ..audioTimestamp = working.audioTimestamp
      ..imageConfig = working.imageConfig
      ..modelArmorConfig = working.modelArmorConfig
      ..serviceTier = working.serviceTier
      ..audioTranscriptionConfig = working.audioTranscriptionConfig
      ..continuationToken = working.continuationToken
      ..automaticContinuation = working.automaticContinuation
      ..generationOutputConfig = working.generationOutputConfig
      ..enableEnhancedCivicAnswers = working.enableEnhancedCivicAnswers
      ..store = working.store
      ..enableAffectiveDialog = working.enableAffectiveDialog;
  }

  return working;
}

String? _resolveConfigFieldName(
  String rawKey,
  GenerateContentConfig? base,
) {
  final String? mapped = _generateContentConfigFieldMap[rawKey];
  if (mapped != null) {
    return mapped;
  }
  if ((base is AnthropicGenerateContentConfig ||
          base is OpenAIGenerateContentConfig) &&
      rawKey == 'effort') {
    return 'effort';
  }
  return null;
}

Map<String, Object?> _resolveAndMergeConfigUpdates({
  required Map<String, Object?> rawUpdates,
  required GenerateContentConfig? base,
  required Object? plannerThinkingConfig,
  required bool mergeWithCurrent,
}) {
  final Map<String, Object?> resolved = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in rawUpdates.entries) {
    final String rawKey = entry.key;
    final String? key = _resolveConfigFieldName(rawKey, base);
    if (key == null) {
      throw ArgumentError(
        "Unknown field '$rawKey' on GenerateContentConfig.",
      );
    }
    if (resolved.containsKey(key)) {
      throw ArgumentError(
        "Duplicate override for 'generate_content_config.$key' via both "
        'field name and alias.',
      );
    }
    final Object? value = entry.value;
    if (key == 'httpOptions') {
      resolved[key] = _mergeHttpOptions(
        mergeWithCurrent ? base?.httpOptions : null,
        value,
      );
    } else if (key == 'toolConfig') {
      resolved[key] = _mergeToolConfig(
        mergeWithCurrent ? base?.toolConfig : null,
        value,
      );
    } else if (key == 'automaticFunctionCalling') {
      resolved[key] = _mergeAutomaticFunctionCalling(
        mergeWithCurrent ? base?.automaticFunctionCalling : null,
        value,
      );
    } else if (key == 'labels') {
      final Object? merged = _mergeNestedMap(
        mergeWithCurrent ? base?.labels : null,
        value,
        'labels.',
      );
      resolved[key] = _asStringMap(merged, 'labels');
    } else if (key == 'thinkingConfig') {
      Object? current = mergeWithCurrent ? base?.thinkingConfig : null;
      if (current == null && mergeWithCurrent) {
        current = plannerThinkingConfig;
      }
      if (current is Map && value is Map) {
        final Map<String, Object?> normalizedCurrent = <String, Object?>{
          for (final MapEntry<Object?, Object?> item in current.entries)
            (_thinkingConfigAliasMap['${item.key}'] ?? '${item.key}'):
                _deepCopyValue(item.value),
        };
        resolved[key] = _mergeNestedMap(
          normalizedCurrent,
          value,
          'thinking_config.',
          keyAliases: _thinkingConfigAliasMap,
        );
      } else if (value is Map) {
        resolved[key] = _mergeNestedMap(
          null,
          value,
          'thinking_config.',
          keyAliases: _thinkingConfigAliasMap,
        );
      } else {
        resolved[key] = _deepCopyValue(value);
      }
    } else {
      Object? current;
      if (mergeWithCurrent && base != null) {
        switch (key) {
          case 'responseSchema':
            current = base.responseSchema;
          case 'responseJsonSchema':
            current = base.responseJsonSchema;
          case 'speechConfig':
            current = base.speechConfig;
          case 'routingConfig':
            current = base.routingConfig;
          case 'modelSelectionConfig':
            current = base.modelSelectionConfig;
          case 'mediaResolution':
            current = base.mediaResolution;
          case 'imageConfig':
            current = base.imageConfig;
          case 'modelArmorConfig':
            current = base.modelArmorConfig;
          case 'serviceTier':
            current = base.serviceTier;
          case 'audioTranscriptionConfig':
            current = base.audioTranscriptionConfig;
          case 'continuationToken':
            current = base.continuationToken;
          case 'generationOutputConfig':
            current = base.generationOutputConfig;
        }
      }
      if (value is Map) {
        resolved[key] = _mergeNestedMap(current, value, '$key.');
      } else {
        resolved[key] = _deepCopyValue(value);
      }
    }
  }
  return resolved;
}

void _validateAgentConfig(BaseAgent agent, GenerateContentConfig? config) {
  if (config == null || agent is! LlmAgent) {
    return;
  }
  if (config.tools != null && config.tools!.isNotEmpty) {
    throw ArgumentError(
      'All tools must be set via LlmAgent.tools. Move your tools to the '
      'LlmAgent(tools=[...]) parameter.',
    );
  }
  if (config.systemInstruction != null &&
      config.systemInstruction!.isNotEmpty) {
    throw ArgumentError(
      'System instruction must be set via LlmAgent.instruction. Move your '
      'instruction to LlmAgent(instruction="...").',
    );
  }
  if (config.responseSchema != null) {
    throw ArgumentError(
      'Response schema must be set via LlmAgent.outputSchema. Move your '
      'schema to LlmAgent(output_schema=...).',
    );
  }
}

void _syncBuiltinPlanner(
  BaseAgent agent,
  Map<String, Object?> updateDict,
  GenerateContentConfig? finalConfig,
) {
  if (agent is! LlmAgent) {
    return;
  }
  final Object? planner = agent.planner;
  if (updateDict.containsKey('planner') || planner is! BuiltInPlanner) {
    return;
  }
  final Object? thinking = finalConfig?.thinkingConfig;
  updateDict['planner'] = thinking == null
      ? null
      : BuiltInPlanner(thinkingConfig: _deepCopyValue(thinking)!);
}

void _applyGenerateContentConfig(
  BaseAgent agent,
  Map<String, Object?> updateDict,
) {
  if (agent is! LlmAgent) {
    return;
  }
  final Map<String, Object?> dotted = <String, Object?>{};
  for (final String key in updateDict.keys.toList()) {
    if (key.startsWith('generate_content_config.')) {
      dotted[key.substring('generate_content_config.'.length)] = updateDict
          .remove(key);
    }
  }
  final bool hasWhole = updateDict.containsKey('generateContentConfig');
  if (hasWhole && dotted.isNotEmpty) {
    throw ArgumentError(
      "Cannot set both 'generate_content_config' as a whole and "
      "'generate_content_config.${dotted.keys.first}' in the same grid.",
    );
  }

  final GenerateContentConfig? base = agent.generateContentConfig;
  if (hasWhole) {
    final Object? swept = updateDict['generateContentConfig'];
    final GenerateContentConfig? finalConfig;
    if (swept == null) {
      finalConfig = null;
    } else if (swept is GenerateContentConfig) {
      finalConfig = _copyGenerateContentConfig(swept);
    } else if (swept is Map) {
      final Map<String, Object?> copiedPayload = _copyMapping(
        swept as Map<Object?, Object?>,
      );
      final Map<String, Object?> resolved = _resolveAndMergeConfigUpdates(
        rawUpdates: copiedPayload,
        base: base,
        plannerThinkingConfig: null,
        mergeWithCurrent: false,
      );
      finalConfig = _buildConfigFromSeedAndMerged(
        base: base,
        canonicalUpdates: resolved,
        preserveBaseFields: false,
      );
    } else {
      throw ArgumentError(
        'Invalid generate_content_config value: $swept',
      );
    }
    _validateAgentConfig(agent, finalConfig);
    updateDict['generateContentConfig'] = finalConfig;
    _syncBuiltinPlanner(agent, updateDict, finalConfig);
    return;
  }

  if (dotted.isEmpty) {
    updateDict['generateContentConfig'] = base == null
        ? null
        : _copyGenerateContentConfig(base);
    return;
  }

  final Object? planner = agent.planner;
  final Object? plannerThinking = planner is BuiltInPlanner
      ? planner.thinkingConfig
      : null;
  final Map<String, Object?> expanded = _expandDottedMapping(dotted);
  final Map<String, Object?> merged = _resolveAndMergeConfigUpdates(
    rawUpdates: expanded,
    base: base,
    plannerThinkingConfig: plannerThinking,
    mergeWithCurrent: true,
  );
  final GenerateContentConfig finalConfig = _buildConfigFromSeedAndMerged(
    base: base,
    canonicalUpdates: merged,
    preserveBaseFields: true,
  );
  _validateAgentConfig(agent, finalConfig);
  updateDict['generateContentConfig'] = finalConfig;
  if (merged.containsKey('thinkingConfig')) {
    _syncBuiltinPlanner(agent, updateDict, finalConfig);
  }
}

AgentTool _copyAgentTool(AgentTool tool, BaseAgent clonedAgent) {
  final BaseAgent origAgent = tool.agent;
  final AgentTool copied;
  if (tool is SingleTurnAgentTool) {
    copied = SingleTurnAgentTool(
      agent: clonedAgent,
      skipSummarization: tool.skipSummarization,
      includePlugins: tool.includePlugins,
      propagateGroundingMetadata: tool.propagateGroundingMetadata,
    );
  } else if (tool is TaskAgentTool) {
    copied = TaskAgentTool(
      agent: clonedAgent,
      skipSummarization: tool.skipSummarization,
      includePlugins: tool.includePlugins,
      propagateGroundingMetadata: tool.propagateGroundingMetadata,
    );
  } else {
    copied = AgentTool(
      agent: clonedAgent,
      skipSummarization: tool.skipSummarization,
      includePlugins: tool.includePlugins,
      propagateGroundingMetadata: tool.propagateGroundingMetadata,
    );
  }
  if (tool.name != origAgent.name) {
    copied.name = tool.name;
  }
  if (tool.description != origAgent.description) {
    copied.description = tool.description;
  }
  copied.title = tool.title;
  copied.isLongRunning = tool.isLongRunning;
  copied.defersResponse = tool.defersResponse;
  copied.customMetadata = tool.customMetadata == null
      ? null
      : Map<String, dynamic>.from(tool.customMetadata!);
  copied.behavior = tool.behavior;
  copied.responseScheduling = tool.responseScheduling;
  return copied;
}

AgentTool _cloneAgentTool(AgentTool tool, Map<String, Object?> params) {
  final BaseAgent clonedChild = cloneAgentWithParams(tool.agent, params);
  // AgentTool runs its agent as a separate root, so it must have no parent.
  clonedChild.parentAgent = null;
  return _copyAgentTool(tool, clonedChild);
}

BaseLlm _cloneBaseLlmIfSupported(BaseLlm model) {
  try {
    final dynamic dynamicModel = model;
    final Object? copied = dynamicModel.clone();
    if (copied is BaseLlm) {
      return copied;
    }
  } on NoSuchMethodError catch (_) {
    // BaseLlm subclasses without clone() are preserved as-is.
  }
  return model;
}

/// Clones [agent] and its descendants with dotted [flatParams] overrides.
BaseAgent cloneAgentWithParams(
  BaseAgent agent,
  Map<String, Object?> flatParams,
) {
  final (
    Map<String, Object?> updateDict,
    _ChildParams subParams,
    _ChildParams toolParams,
  ) = _partitionAgentParams(agent, flatParams);

  if (agent is LlmAgent) {
    final Object? rawModel = updateDict.containsKey('model')
        ? updateDict['model']
        : agent.model;
    if (rawModel is BaseLlm) {
      updateDict['model'] = _cloneBaseLlmIfSupported(rawModel);
    }
  }

  // Clone children even when `subAgents` itself is swept: cloning re-parents
  // them, which must never touch the caller's agents or another candidate's.
  final List<BaseAgent> subAgents = updateDict.containsKey('subAgents')
      ? (updateDict['subAgents'] as List<BaseAgent>)
      : agent.subAgents;
  final Map<BaseAgent, BaseAgent> clonedSubs = Map<BaseAgent, BaseAgent>.identity();
  if (subAgents.isNotEmpty) {
    final List<BaseAgent> clonedList = <BaseAgent>[
      for (final BaseAgent child in subAgents)
        cloneAgentWithParams(
          child,
          subParams[child.name] ?? const <String, Object?>{},
        ),
    ];
    updateDict['subAgents'] = clonedList;
    for (int i = 0; i < subAgents.length; i += 1) {
      clonedSubs[subAgents[i]] = clonedList[i];
    }
  }

  if (agent is LlmAgent) {
    final List<Object> tools = updateDict.containsKey('tools')
        ? (updateDict['tools'] as List<Object>)
        : agent.tools;
    final bool hasCustomAgentTool = tools.any(
      (Object tool) =>
          tool is AgentTool &&
          !(clonedSubs.containsKey(tool.agent) && _isAutoBuiltModeTool(tool)),
    );
    if (hasCustomAgentTool) {
      final List<Object> newTools = <Object>[];
      for (final Object tool in tools) {
        if (tool is! AgentTool) {
          newTools.add(tool);
        } else if (clonedSubs.containsKey(tool.agent)) {
          if (_isAutoBuiltModeTool(tool)) {
            // Keep auto-built mode tool reference so LlmAgent.clone strips it
            // via _constructedModeTools and rebuilds it for the cloned child.
            newTools.add(tool);
          } else {
            newTools.add(_copyAgentTool(tool, clonedSubs[tool.agent]!));
          }
        } else {
          newTools.add(
            _cloneAgentTool(
              tool,
              toolParams[tool.agent.name] ?? const <String, Object?>{},
            ),
          );
        }
      }
      updateDict['tools'] = newTools;
    }

    _applyGenerateContentConfig(agent, updateDict);
    final Object? planner = updateDict.containsKey('planner')
        ? updateDict['planner']
        : agent.planner;
    if (planner is BuiltInPlanner) {
      updateDict['planner'] = BuiltInPlanner(
        thinkingConfig: _deepCopyValue(planner.thinkingConfig)!,
      );
    }
  }

  return agent.clone(update: updateDict);
}
