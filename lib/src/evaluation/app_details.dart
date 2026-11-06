/// Shared evaluation models and utility helpers.
library;

import 'dart:developer' as developer;

import '../models/llm_request.dart';
import 'common.dart';

const Set<String> _validToolKeys = <String>{
  'function_declarations',
  'functionDeclarations',
  'google_search',
  'googleSearch',
  'google_search_retrieval',
  'googleSearchRetrieval',
  'url_context',
  'urlContext',
  'code_execution',
  'codeExecution',
  'google_maps',
  'googleMaps',
  'enterprise_web_search',
  'enterpriseWebSearch',
  'retrieval',
  'computer_use',
  'computerUse',
};

const Set<String> _validFunctionDeclarationKeys = <String>{
  'name',
  'description',
  'parameters',
  'parameters_json_schema',
  'parametersJsonSchema',
  'response',
  'response_json_schema',
  'responseJsonSchema',
  'behavior',
};

/// JSON-serializable [ToolDeclaration] with value equality for evaluation metadata.
class EvalToolDeclaration extends ToolDeclaration {
  /// Creates a serializable tool declaration.
  EvalToolDeclaration({
    super.functionDeclarations,
    super.googleSearch,
    super.googleSearchRetrieval,
    super.urlContext,
    super.codeExecution,
    super.googleMaps,
    super.enterpriseWebSearch,
    super.retrieval,
    super.computerUse,
  });

  /// Creates an [EvalToolDeclaration] from an existing [ToolDeclaration].
  factory EvalToolDeclaration.fromToolDeclaration(ToolDeclaration tool) {
    if (tool is EvalToolDeclaration) {
      return tool;
    }
    return EvalToolDeclaration(
      functionDeclarations: tool.functionDeclarations
          .map((FunctionDeclaration d) => d.copyWith())
          .toList(),
      googleSearch: tool.googleSearch,
      googleSearchRetrieval: tool.googleSearchRetrieval,
      urlContext: tool.urlContext,
      codeExecution: tool.codeExecution,
      googleMaps: tool.googleMaps,
      enterpriseWebSearch: tool.enterpriseWebSearch,
      retrieval: tool.retrieval,
      computerUse: tool.computerUse,
    );
  }

  /// Serializes this tool declaration to a JSON map.
  Map<String, Object?> toJson() => serializeToolDeclarationToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ToolDeclaration) {
      return false;
    }
    return _deepEquals(
      serializeToolDeclarationToJson(this),
      serializeToolDeclarationToJson(other),
    );
  }

  @override
  int get hashCode =>
      Object.hashAll(serializeToolDeclarationToJson(this).entries.map(
        (MapEntry<String, Object?> e) => Object.hash(e.key, e.value.toString()),
      ));
}

/// Serializes a [ToolDeclaration] into a JSON-compatible map.
Map<String, Object?> serializeToolDeclarationToJson(ToolDeclaration tool) {
  return <String, Object?>{
    if (tool.functionDeclarations.isNotEmpty)
      'function_declarations': tool.functionDeclarations
          .map(
            (FunctionDeclaration d) => <String, Object?>{
              'name': d.name,
              if (d.description.isNotEmpty) 'description': d.description,
              if (d.parameters.isNotEmpty)
                'parameters': Map<String, Object?>.from(d.parameters),
            },
          )
          .toList(),
    if (tool.googleSearch != null) 'google_search': tool.googleSearch,
    if (tool.googleSearchRetrieval != null)
      'google_search_retrieval': tool.googleSearchRetrieval,
    if (tool.urlContext != null) 'url_context': tool.urlContext,
    if (tool.codeExecution != null) 'code_execution': tool.codeExecution,
    if (tool.googleMaps != null) 'google_maps': tool.googleMaps,
    if (tool.enterpriseWebSearch != null)
      'enterprise_web_search': tool.enterpriseWebSearch,
    if (tool.retrieval != null) 'retrieval': tool.retrieval,
    if (tool.computerUse != null) 'computer_use': tool.computerUse,
  };
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

List<Object?> _restoreToolsFromJson(List<Object?>? tools) {
  if (tools == null) {
    return <Object?>[];
  }
  final List<Object?> restored = <Object?>[];
  for (final Object? tool in tools) {
    if (tool is ToolDeclaration) {
      restored.add(EvalToolDeclaration.fromToolDeclaration(tool));
      continue;
    }
    if (tool is Map) {
      try {
        restored.add(_parseToolDeclarationFromMap(tool));
        continue;
      } on FormatException catch (e) {
        developer.log(
          'Keeping tool declaration as a dict: $e',
          name: 'adk_dart.evaluation',
        );
      }
    }
    restored.add(tool);
  }
  return restored;
}

EvalToolDeclaration _parseToolDeclarationFromMap(Map<Object?, Object?> raw) {
  final Map<String, Object?> map = raw.map(
    (Object? k, Object? v) => MapEntry('$k', v),
  );
  for (final String key in map.keys) {
    if (!_validToolKeys.contains(key)) {
      throw FormatException('Unexpected Tool field: $key');
    }
  }

  final Object? rawFnDecls =
      map['function_declarations'] ?? map['functionDeclarations'];
  final List<FunctionDeclaration> fnDeclarations = <FunctionDeclaration>[];
  if (rawFnDecls != null) {
    if (rawFnDecls is! List) {
      throw const FormatException('function_declarations must be a list');
    }
    for (final Object? item in rawFnDecls) {
      if (item is FunctionDeclaration) {
        fnDeclarations.add(item.copyWith());
        continue;
      }
      if (item is! Map) {
        throw const FormatException('function_declaration item must be a map');
      }
      final Map<String, Object?> fnMap = item.map(
        (Object? k, Object? v) => MapEntry('$k', v),
      );
      for (final String key in fnMap.keys) {
        if (!_validFunctionDeclarationKeys.contains(key)) {
          throw FormatException('Unexpected FunctionDeclaration field: $key');
        }
      }
      final Object? name = fnMap['name'];
      if (name is! String || name.isEmpty) {
        throw const FormatException('FunctionDeclaration.name is required');
      }
      final Object? description = fnMap['description'];
      if (description != null && description is! String) {
        throw const FormatException(
          'FunctionDeclaration.description must be a String',
        );
      }
      final Object? parameters =
          fnMap['parameters'] ??
          fnMap['parameters_json_schema'] ??
          fnMap['parametersJsonSchema'];
      if (parameters != null && parameters is! Map) {
        throw const FormatException(
          'FunctionDeclaration.parameters must be a Map',
        );
      }
      fnDeclarations.add(
        FunctionDeclaration(
          name: name,
          description: (description as String?) ?? '',
          parameters: parameters is Map
              ? parameters.map((Object? k, Object? v) => MapEntry('$k', v))
              : <String, dynamic>{},
        ),
      );
    }
  }

  return EvalToolDeclaration(
    functionDeclarations: fnDeclarations,
    googleSearch: map['google_search'] ?? map['googleSearch'],
    googleSearchRetrieval:
        map['google_search_retrieval'] ?? map['googleSearchRetrieval'],
    urlContext: map['url_context'] ?? map['urlContext'],
    codeExecution: map['code_execution'] ?? map['codeExecution'],
    googleMaps: map['google_maps'] ?? map['googleMaps'],
    enterpriseWebSearch:
        map['enterprise_web_search'] ?? map['enterpriseWebSearch'],
    retrieval: map['retrieval'],
    computerUse: map['computer_use'] ?? map['computerUse'],
  );
}

/// Per-agent metadata captured during one invocation.
class AgentDetails {
  /// Creates agent detail metadata.
  AgentDetails({
    required this.name,
    this.instructions = '',
    List<Object?>? toolDeclarations,
  }) : toolDeclarations = _restoreToolsFromJson(toolDeclarations);

  /// Agent name.
  final String name;

  /// System/developer instructions applied to the agent.
  final String instructions;

  /// Tool declarations available to the agent.
  final List<Object?> toolDeclarations;

  /// Decodes agent details from JSON.
  factory AgentDetails.fromJson(EvalJson json) {
    return AgentDetails(
      name: asNullableString(json['name']) ?? '',
      instructions: asNullableString(json['instructions']) ?? '',
      toolDeclarations: asObjectList(
        json['toolDeclarations'] ?? json['tool_declarations'],
      ),
    );
  }

  /// Encodes agent details for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'name': name,
      'instructions': instructions,
      'tool_declarations': toolDeclarations
          .map(
            (Object? t) =>
                t is ToolDeclaration ? serializeToolDeclarationToJson(t) : t,
          )
          .toList(),
    };
  }
}

/// Invocation-scoped metadata for all participating agents.
class AppDetails {
  /// Creates app details.
  AppDetails({Map<String, AgentDetails>? agentDetails})
    : agentDetails = agentDetails ?? <String, AgentDetails>{};

  /// Agent metadata keyed by agent name.
  final Map<String, AgentDetails> agentDetails;

  /// Decodes app details from JSON.
  factory AppDetails.fromJson(EvalJson json) {
    final EvalJson agentsJson = asEvalJson(
      json['agentDetails'] ?? json['agent_details'],
    );
    return AppDetails(
      agentDetails: agentsJson.map((String key, Object? value) {
        return MapEntry(key, AgentDetails.fromJson(asEvalJson(value)));
      }),
    );
  }

  /// Returns instructions configured for [agentName].
  String getDeveloperInstructions(String agentName) {
    final AgentDetails? details = agentDetails[agentName];
    if (details == null) {
      throw ArgumentError('`$agentName` not found in the agentic system.');
    }
    return details.instructions;
  }

  /// Returns serialized tool declarations keyed by agent name.
  Map<String, List<Object?>> getToolsByAgentName() {
    return agentDetails.map((String key, AgentDetails value) {
      return MapEntry(key, List<Object?>.from(value.toolDeclarations));
    });
  }

  /// Encodes app details for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'agent_details': agentDetails.map((String key, AgentDetails value) {
        return MapEntry(key, value.toJson());
      }),
    };
  }
}
