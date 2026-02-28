import '../examples/example.dart';
import '../examples/example_util.dart' as example_util;
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

class ExampleToolConfig extends BaseToolConfig {
  ExampleToolConfig({required this.examples, super.extras});

  final Object examples;
}

class ExampleTool extends BaseTool {
  ExampleTool(this.examples)
    : super(name: 'example_tool', description: 'example tool');

  final Object examples;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  @override
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
