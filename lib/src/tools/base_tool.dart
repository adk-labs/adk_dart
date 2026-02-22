import '../models/llm_request.dart';
import 'tool_context.dart';

abstract class BaseTool {
  BaseTool({
    required this.name,
    required this.description,
    this.isLongRunning = false,
    this.customMetadata,
  });

  String name;
  String description;
  bool isLongRunning;
  Map<String, dynamic>? customMetadata;

  FunctionDeclaration? getDeclaration() => null;

  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  });

  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    llmRequest.appendTools(<BaseTool>[this]);
  }
}
