import 'dart:convert';

import '../../../models/base_llm.dart';
import '../../../models/llm_request.dart';
import '../../../models/llm_response.dart';
import '../../../models/registry.dart';
import '../../../tools/base_tool.dart';
import '../../../types/content.dart';
import '../tool_connection_map.dart';
import 'base.dart';

const String toolSpecMockPromptTemplate = '''
You are a stateful tool simulator. Your task is to generate a realistic JSON response for a tool call, maintaining consistency based on a shared state.

{environment_data_snippet}

Here is the map of how tools connect via stateful parameters:
{tool_connection_map_json}

Here is the current state of all stateful parameters:
{state_store_json}

You are now simulating the following tool call:
Tool Name: {tool_name}
Tool Description: {tool_description}
Tool Schema: {tool_schema_json}
Tool Arguments: {tool_arguments_json}

Your instructions:
1. Analyze the tool call. Is it a "creating" or "consuming" tool based on the connection map?
2. If it's a "consuming" tool, check the provided arguments against the state store. If an ID is provided that does not exist in the state, return a realistic error (e.g., a 404 Not Found error). Otherwise, use the data from the state and the provided environment data to generate the response.
3. If it's a "creating" tool, generate a new, unique ID for the stateful parameter (e.g., a random string for a ticket_id). Include this new ID in your response. The simulator updates the state from this response.
4. Leverage the provided environment data (if any) to make your response more realistic and consistent with the simulated environment.
5. Generate a convincing, valid JSON object that mocks the tool's response. The response must be only the JSON object, without any additional text or formatting.
6. The response must start with '{' and end with '}'.
''';

Object? _findValueByKey(Object? data, String targetKey) {
  if (data is Map) {
    if (data.containsKey(targetKey)) {
      return data[targetKey];
    }
    for (final MapEntry<Object?, Object?> entry in data.entries) {
      final Object? result = _findValueByKey(entry.value, targetKey);
      if (result != null) {
        return result;
      }
    }
  } else if (data is List) {
    for (final Object? item in data) {
      final Object? result = _findValueByKey(item, targetKey);
      if (result != null) {
        return result;
      }
    }
  }
  return null;
}

class ToolSpecMockStrategy extends BaseMockStrategy {
  ToolSpecMockStrategy({
    required this.llmName,
    required this.llmConfig,
    BaseLlm? llm,
  }) : _llm = llm ?? LLMRegistry.newLlm(llmName);

  final String llmName;
  final GenerateContentConfig llmConfig;
  final BaseLlm _llm;

  @override
  Future<Map<String, Object?>> mock(
    BaseTool tool,
    Map<String, Object?> args,
    Object toolContext,
    ToolConnectionMap? toolConnectionMap,
    Map<String, Object?> stateStore, {
    String? environmentData,
  }) async {
    final FunctionDeclaration? declaration = tool.getDeclaration();
    if (declaration == null) {
      return <String, Object?>{
        'status': 'error',
        'error_message': 'Could not get tool declaration.',
      };
    }

    final String toolConnectionMapJson = toolConnectionMap == null
        ? "''"
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(toolConnectionMap.toJson());
    final String stateStoreJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(_normalizeValue(stateStore));
    final String toolSchemaJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(_declarationToJson(declaration));
    final String toolArgumentsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(_normalizeValue(args));

    String environmentDataSnippet = '';
    if (environmentData != null && environmentData.isNotEmpty) {
      environmentDataSnippet =
          '''
Here is relevant environment data (e.g., database snippet, context information):
<environment_data>
$environmentData
</environment_data>
Use this information to generate more realistic responses.
''';
    }

    final String prompt = toolSpecMockPromptTemplate
        .replaceAll('{environment_data_snippet}', environmentDataSnippet)
        .replaceAll('{tool_connection_map_json}', toolConnectionMapJson)
        .replaceAll('{state_store_json}', stateStoreJson)
        .replaceAll('{tool_name}', tool.name)
        .replaceAll('{tool_description}', tool.description)
        .replaceAll('{tool_schema_json}', toolSchemaJson)
        .replaceAll('{tool_arguments_json}', toolArgumentsJson);

    final LlmRequest request = LlmRequest(
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text(prompt)]),
      ],
      model: llmName,
      config: llmConfig.copyWith(responseMimeType: 'application/json'),
    );

    String responseText = '';
    await for (final LlmResponse llmResponse in _llm.generateContent(
      request,
      stream: true,
    )) {
      final Content? generatedContent = llmResponse.content;
      if (generatedContent == null || generatedContent.parts.isEmpty) {
        continue;
      }
      for (final Part part in generatedContent.parts) {
        if (part.text != null) {
          responseText += part.text!;
        }
      }
    }

    try {
      String cleanJsonText = responseText.replaceFirst(
        RegExp(r'^```[a-zA-Z]*\n'),
        '',
      );
      cleanJsonText = cleanJsonText.replaceFirst(RegExp(r'\n```$'), '');
      final Object? decoded = jsonDecode(cleanJsonText.trim());
      if (decoded is! Map) {
        throw const FormatException('Mock response must be a JSON object.');
      }

      final Map<String, Object?> mockResponse = _toStringObjectMap(decoded);
      if (toolConnectionMap != null) {
        final Set<String> allCreatingTools = <String>{};
        for (final StatefulParameter parameter
            in toolConnectionMap.statefulParameters) {
          allCreatingTools.addAll(parameter.creatingTools);
        }

        if (allCreatingTools.contains(tool.name)) {
          for (final StatefulParameter parameter
              in toolConnectionMap.statefulParameters) {
            if (!parameter.creatingTools.contains(tool.name)) {
              continue;
            }
            final Object? parameterValue = _findValueByKey(
              mockResponse,
              parameter.parameterName,
            );
            if (parameterValue == null) {
              continue;
            }

            final Object? currentBucket = stateStore[parameter.parameterName];
            Map<String, Object?> bucket;
            if (currentBucket is Map) {
              bucket = currentBucket.map(
                (Object? key, Object? value) =>
                    MapEntry<String, Object?>('$key', value),
              );
            } else {
              bucket = <String, Object?>{};
            }
            bucket['$parameterValue'] = mockResponse;
            stateStore[parameter.parameterName] = bucket;
          }
        }
      }

      return mockResponse;
    } catch (_) {
      return <String, Object?>{
        'status': 'error',
        'error_message': 'Failed to generate valid JSON mock response.',
        'llm_output': responseText,
      };
    }
  }
}

Map<String, Object?> _declarationToJson(FunctionDeclaration declaration) {
  return <String, Object?>{
    'name': declaration.name,
    'description': declaration.description,
    'parameters': _normalizeValue(declaration.parameters),
  };
}

Map<String, Object?> _toStringObjectMap(Map value) {
  return value.map((Object? key, Object? value) {
    return MapEntry<String, Object?>('$key', _normalizeValue(value));
  });
}

Object? _normalizeValue(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? value) {
      return MapEntry<String, Object?>('$key', _normalizeValue(value));
    });
  }
  if (value is List) {
    return value.map(_normalizeValue).toList(growable: false);
  }
  if (value is num || value is bool || value is String || value == null) {
    return value;
  }
  return '$value';
}
