import 'dart:convert';
import 'dart:developer' as developer;

import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../models/registry.dart';
import '../../tools/base_tool.dart';
import '../../types/content.dart';
import 'tool_connection_map.dart';

const String toolConnectionAnalysisPromptTemplate = '''
  You are an expert software architect analyzing a set of tools to understand
  stateful dependencies. Your task is to identify parameters that act as
  stateful identifiers (like IDs) and classify the tools that interact with
  them.

  **Definitions:**
  - A **"creating tool"** is a tool that creates a new resource or makes a
    significant state change to an existing one (e.g., creating, updating,
    canceling, or deleting). Tool names like `create_account`, `cancel_order`,
    or `update_price` are strong indicators. These tools are responsible for
    generating or modifying the state associated with an ID.
  - A **"consuming tool"** is a tool that uses a resource's ID to retrieve
    information without changing its state. Tool names like `get_user`,
    `list_events`, or `find_order` are strong indicators.

  **Your Goal:**
  Analyze the following tool schemas and identify the shared, stateful
  parameters (like `user_id`, `order_id`, etc.).

  For each stateful parameter you identify, classify the tools into
  `creating_tools` and `consuming_tools` based on the definitions above.

  **Example:** A `create_ticket` tool would be a `creating_tool` for
  `ticket_id`. A `get_ticket` tool would be a `consuming_tool` for
  `ticket_id`. A `list_tickets` tool that takes a `user_id` as input is a
  `consuming_tool` for `user_id`.

  **Analyze the following tool schemas:**
  {tool_schemas_json}

  **Output Format:**
  Generate a JSON object with a single key, "stateful_parameters", which is a
  list. Each item in the list must have these keys:
  - "parameter_name": The name of the shared parameter (e.g., "ticket_id").
  - "creating_tools": A list of tools that create or modify this parameter's
    state.
  - "consuming_tools": A list of tools that use this parameter as input for
    read-only operations.

  ONLY return the raw JSON object.
  Your response must start with '{' and end with '}'.
''';

class ToolConnectionAnalyzer {
  ToolConnectionAnalyzer({
    required this.llmName,
    GenerateContentConfig? llmConfig,
    BaseLlm? llm,
  }) : llmConfig = llmConfig ?? GenerateContentConfig(),
       _llm = llm ?? LLMRegistry.newLlm(llmName);

  final String llmName;
  final GenerateContentConfig llmConfig;
  final BaseLlm _llm;

  Future<ToolConnectionMap> analyze(List<BaseTool> tools) async {
    final List<Map<String, Object?>> toolSchemas = <Map<String, Object?>>[];
    for (final BaseTool tool in tools) {
      final FunctionDeclaration? declaration = tool.getDeclaration();
      if (declaration == null) {
        continue;
      }
      toolSchemas.add(<String, Object?>{
        'name': declaration.name,
        'description': declaration.description,
        'parameters': _normalizeValue(declaration.parameters),
      });
    }

    final String prompt = toolConnectionAnalysisPromptTemplate.replaceAll(
      '{tool_schemas_json}',
      const JsonEncoder.withIndent('  ').convert(toolSchemas),
    );

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
        throw const FormatException(
          'Tool connection analysis is not JSON map.',
        );
      }
      return ToolConnectionMap.fromJson(
        decoded.map(
          (Object? key, Object? value) =>
              MapEntry<String, Object?>('$key', value),
        ),
      );
    } catch (error) {
      developer.log(
        'Failed to parse tool connection analysis. Returning empty map. '
        'Error: $error\nLLM output: $responseText',
        name: 'adk_dart.agent_simulator',
      );
      return ToolConnectionMap(statefulParameters: const <StatefulParameter>[]);
    }
  }
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
