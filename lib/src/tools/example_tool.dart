/// Few-shot example injection tool for prompt conditioning.
library;

import '../examples/example.dart';
import '../examples/example_util.dart' as example_util;
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

/// Configuration model for [ExampleTool].
class ExampleToolConfig extends BaseToolConfig {
  /// Creates an example-tool configuration.
  ExampleToolConfig({required this.examples, super.extras});

  /// Example dataset used to build prompt instructions.
  final Object examples;
}

/// Tool that injects few-shot examples into model instructions.
class ExampleTool extends BaseTool {
  /// Creates an example tool from [examples].
  ExampleTool(this.examples)
    : super(name: 'example_tool', description: 'example tool');

  /// Example dataset source.
  final Object examples;

  @override
  /// Returns `null` because this tool mutates prompt context only.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
  /// Appends example-driven system instructions for the current user query.
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    final Content? userContent = toolContext.invocationContext.userContent;
    final String? query = userContent?.parts.isNotEmpty == true
        ? userContent!.parts.first.text
        : null;
    if (query == null || query.trim().isEmpty) {
      return;
    }

    llmRequest.appendInstructions(<String>[
      example_util.buildExampleSi(examples, query.trim(), llmRequest.model),
    ]);
  }

  /// Builds an [ExampleTool] from serialized config values.
  static ExampleTool fromConfig(ToolArgsConfig config) {
    final Object? examples = config['examples'];
    if (examples is List) {
      final List<Example> parsed = <Example>[];
      for (final Object? item in examples) {
        if (item is Map) {
          final String? input = item['input'] as String?;
          final String? output = item['output'] as String?;
          if (input != null && output != null) {
            parsed.add(
              Example(
                input: Content.userText(input),
                output: <Content>[Content.modelText(output)],
              ),
            );
          }
        }
      }
      return ExampleTool(parsed);
    }
    throw ArgumentError(
      'Example tool config must contain `examples` as a list of {input, output}.',
    );
  }
}
