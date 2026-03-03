/// Plugin hooks and implementations for ADK runtime pipelines.
library;

import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';

/// Base class for ADK runtime plugins.
abstract class BasePlugin {
  /// Creates a plugin with a unique [name].
  BasePlugin({required this.name});

  /// Unique plugin name used for registration and error reporting.
  final String name;

  /// Handles raw user messages before runner processing.
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    return null;
  }

  /// Runs before an invocation starts.
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return null;
  }

  /// Handles events emitted during invocation.
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return null;
  }

  /// Runs after an invocation finishes.
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {}

  /// Releases plugin resources.
  Future<void> close() async {}

  /// Runs before an agent is invoked.
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return null;
  }

  /// Runs after an agent completes.
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return null;
  }

  /// Runs before a model request is sent.
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    return null;
  }

  /// Runs after a model response is received.
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    return null;
  }

  /// Handles model invocation errors.
  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    return null;
  }

  /// Runs before tool execution.
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  /// Runs after successful tool execution.
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return null;
  }

  /// Handles tool execution errors.
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return null;
  }
}
