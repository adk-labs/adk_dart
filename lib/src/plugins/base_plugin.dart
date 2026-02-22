import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';

abstract class BasePlugin {
  BasePlugin({required this.name});

  final String name;

  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    return null;
  }

  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return null;
  }

  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return null;
  }

  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {}

  Future<void> close() async {}

  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return null;
  }

  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return null;
  }

  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    return null;
  }

  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    return null;
  }

  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    return null;
  }

  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    return null;
  }

  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return null;
  }

  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return null;
  }
}
