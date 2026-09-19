/// Core abstractions for runtime-executable tools.
library;

import '../models/llm_request.dart';
import '../types/content.dart';
import 'tool_context.dart';

/// Controls whether a tool is blocking or non-blocking in Live API mode.
enum ToolBehavior {
  /// The model waits for the tool response before continuing.
  blocking('BLOCKING'),

  /// The model continues the conversation while the tool executes in the background.
  nonBlocking('NON_BLOCKING');

  const ToolBehavior(this.wireValue);

  /// Wire format string representation.
  final String wireValue;
}

/// Base contract for one callable tool exposed to the model runtime.
abstract class BaseTool {
  /// Creates a tool with a stable [name] and user-visible [description].
  BaseTool({
    required this.name,
    required this.description,
    this.isLongRunning = false,
    this.defersResponse = false,
    this.customMetadata,
    this.behavior,
    this.responseScheduling,
  });

  /// Unique tool name used in function-calling payloads.
  String name;

  /// Human-readable purpose text shown to the model.
  String description;

  /// Whether the tool can outlive a single response turn.
  bool isLongRunning;

  /// Whether response event creation is handled by framework code elsewhere.
  bool defersResponse;

  /// Arbitrary metadata attached to this tool declaration.
  Map<String, dynamic>? customMetadata;

  /// Controls whether the tool is blocking or non-blocking in Live mode.
  ToolBehavior? behavior;

  /// Live response scheduling policy for this tool.
  FunctionResponseScheduling? responseScheduling;

  /// Returns the function declaration exposed to the model, if any.
  FunctionDeclaration? getDeclaration() => null;

  /// Whether this tool call requires human confirmation before execution.
  ///
  /// When returning `true`, the framework confirmation gate holds the call back.
  Future<bool> checkRequireConfirmation(
    Map<String, dynamic> args,
    ToolContext toolContext,
  ) async => false;

  /// Executes the tool and returns a JSON-like response payload.
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  });

  /// Returns a telemetry error type when [response] represents a tool error.
  ///
  /// Tool implementations can return structured error payloads instead of
  /// throwing. This hook lets telemetry record those failures consistently.
  String? detectErrorInResponse(Object? response) => null;

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
