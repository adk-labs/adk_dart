import '../models/llm_request.dart';
import 'tool_context.dart';

/// Base contract for one callable tool exposed to the model runtime.
abstract class BaseTool {
  /// Creates a tool with a stable [name] and user-visible [description].
  BaseTool({
    required this.name,
    required this.description,
    this.isLongRunning = false,
    this.customMetadata,
  });

  /// Unique tool name used in function-calling payloads.
  String name;

  /// Human-readable purpose text shown to the model.
  String description;

  /// Whether the tool can outlive a single response turn.
  bool isLongRunning;

  /// Arbitrary metadata attached to this tool declaration.
  Map<String, dynamic>? customMetadata;

  /// Returns the function declaration exposed to the model, if any.
  FunctionDeclaration? getDeclaration() => null;

  /// Executes the tool and returns a JSON-like response payload.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  });

  /// Mutates outgoing [llmRequest] before model generation.
  ///
  /// The default behavior appends this tool to the request tool list.
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    llmRequest.appendTools(<BaseTool>[this]);
  }
}
