import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_configs.dart';
import 'tool_context.dart';

class Example {
  Example({required this.input, required this.output});

  final String input;
  final String output;
}

abstract class BaseExampleProvider {
  List<Example> provideExamples();
}

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

    final List<Example> resolved = _resolveExamples();
    if (resolved.isEmpty) {
      return;
    }
    llmRequest.appendInstructions(<String>[
      buildExampleSystemInstruction(resolved, query),
    ]);
  }

  List<Example> _resolveExamples() {
    final Object value = examples;
    if (value is BaseExampleProvider) {
      return value.provideExamples();
    }
    if (value is List<Example>) {
      return value;
    }
    return <Example>[];
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
            parsed.add(Example(input: input, output: output));
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

String buildExampleSystemInstruction(List<Example> examples, String query) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('Use the following examples as guidance.');
  for (int i = 0; i < examples.length; i += 1) {
    final Example example = examples[i];
    buffer.writeln('Example ${i + 1}');
    buffer.writeln('Input: ${example.input}');
    buffer.writeln('Output: ${example.output}');
  }
  buffer.writeln('Now answer this user query: $query');
  return buffer.toString().trim();
}
