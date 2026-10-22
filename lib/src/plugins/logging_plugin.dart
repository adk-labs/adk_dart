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
import 'base_plugin.dart';
import 'callback_helpers.dart';

/// Console logging plugin for invocation, model, and tool lifecycle events.
class LoggingPlugin extends BasePlugin {
  /// Creates a logging plugin.
  LoggingPlugin({
    super.name = 'logging_plugin',
    this.toolResultClassifier,
  });

  /// Optional classifier for tool results that report errors without throwing.
  final ToolResultClassifier? toolResultClassifier;

  /// Logs the incoming user message and invocation context.
  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    _log('USER MESSAGE RECEIVED');
    _log('Invocation ID: ${invocationContext.invocationId}');
    _log('Session ID: ${invocationContext.session.id}');
    _log('User ID: ${invocationContext.userId}');
    _log('App Name: ${invocationContext.appName}');
    _log('Root Agent: ${invocationContext.agent.name}');
    _log('User Content: ${_formatContent(userMessage)}');
    if (invocationContext.branch != null) {
      _log('Branch: ${invocationContext.branch}');
    }
    return null;
  }

  /// Logs invocation start details.
  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    _log('INVOCATION STARTING');
    _log('Invocation ID: ${invocationContext.invocationId}');
    _log('Starting Agent: ${invocationContext.agent.name}');
    return null;
  }

  /// Logs each emitted event.
  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    _log('EVENT YIELDED');
    _log('Event ID: ${event.id}');
    _log('Author: ${event.author}');
    _log('Content: ${_formatContent(event.content)}');
    _log('Final Response: ${event.isFinalResponse()}');
    final List<FunctionCall> functionCalls = event.getFunctionCalls();
    if (functionCalls.isNotEmpty) {
      _log(
        'Function Calls: ${functionCalls.map((FunctionCall fc) => fc.name).toList()}',
      );
    }
    final List<FunctionResponse> functionResponses = event
        .getFunctionResponses();
    if (functionResponses.isNotEmpty) {
      _log(
        'Function Responses: ${functionResponses.map((FunctionResponse fr) => fr.name).toList()}',
      );
    }
    final Set<String>? longRunningIds = event.longRunningToolIds;
    if (longRunningIds != null && longRunningIds.isNotEmpty) {
      _log('Long Running Tools: ${longRunningIds.toList()}');
    }
    final NodeInfo nodeInfo = event.nodeInfo;
    if (nodeInfo.path.isNotEmpty) {
      _log('Node Path: ${nodeInfo.path}');
      if (event.partial != true) {
        if (event.output != null && nodeInfo.messageAsOutput != true) {
          _log('Node Output: ${_formatValue(event.output)}');
        }
        if (isDurableNodeError(event)) {
          _log(
            'Node Error: [${event.errorCode}] ${event.errorMessage ?? ''}'
                .trimRight(),
          );
        }
      }
    }
    return null;
  }

  /// Logs invocation completion details.
  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    _log('INVOCATION COMPLETED');
    _log('Invocation ID: ${invocationContext.invocationId}');
    _log('Final Agent: ${invocationContext.agent.name}');
  }

  /// Logs agent start.
  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    _log('AGENT STARTING');
    _log('Agent Name: ${callbackContext.agentName}');
    _log('Invocation ID: ${callbackContext.invocationId}');
    if (callbackContext.invocationContext.branch != null) {
      _log('Branch: ${callbackContext.invocationContext.branch}');
    }
    return null;
  }

  /// Logs agent completion.
  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    _log('AGENT COMPLETED');
    _log('Agent Name: ${callbackContext.agentName}');
    _log('Invocation ID: ${callbackContext.invocationId}');
    return null;
  }

  /// Logs outbound model request details.
  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    _log('LLM REQUEST');
    _log('Model: ${llmRequest.model ?? 'default'}');
    _log('Agent: ${callbackContext.agentName}');
    final String? instruction = llmRequest.config.systemInstruction;
    if (instruction != null && instruction.isNotEmpty) {
      const int maxLength = 200;
      final String preview = instruction.length > maxLength
          ? '${instruction.substring(0, maxLength)}...'
          : instruction;
      _log("System Instruction: '$preview'");
    }
    if (llmRequest.toolsDict.isNotEmpty) {
      _log('Available Tools: ${llmRequest.toolsDict.keys.toList()}');
    }
    return null;
  }

  /// Logs inbound model response details.
  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    _log('LLM RESPONSE');
    _log('Agent: ${callbackContext.agentName}');
    final bool isFinal = llmResponse.partial != true;
    if (isFinal &&
        llmResponse.errorCode != null &&
        llmResponse.errorCode!.isNotEmpty) {
      _log('ERROR - Code: ${llmResponse.errorCode}');
      _log('Error Message: ${llmResponse.errorMessage}');
    } else {
      _log('Content: ${_formatContent(llmResponse.content)}');
      if (llmResponse.partial != null) {
        _log('Partial: ${llmResponse.partial}');
      }
      if (llmResponse.turnComplete != null) {
        _log('Turn Complete: ${llmResponse.turnComplete}');
      }
    }
    if (isFinal &&
        llmResponse.finishReason != null &&
        llmResponse.finishReason!.isNotEmpty) {
      _log('Finish Reason: ${llmResponse.finishReason}');
    }
    if (llmResponse.usageMetadata != null) {
      _log('Usage Metadata: ${llmResponse.usageMetadata}');
    }
    return null;
  }

  /// Logs tool-call start details.
  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    _log('TOOL STARTING');
    _log('Tool Name: ${tool.name}');
    _log('Agent: ${toolContext.agentName}');
    _log('Function Call ID: ${toolContext.functionCallId}');
    _log('Arguments: ${_formatArgs(toolArgs)}');
    return null;
  }

  /// Logs tool-call completion details, or the failure its result reports.
  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    if (popToolErrorRecorded(this, toolContext)) {
      return null;
    }
    final String? errorMessage = classifyToolResultError(
      tool: tool,
      toolArgs: toolArgs,
      toolContext: toolContext,
      result: result,
      toolResultClassifier: toolResultClassifier,
    );
    if (errorMessage != null) {
      _log('TOOL ERROR');
      _log('Tool Name: ${tool.name}');
      _log('Agent: ${toolContext.agentName}');
      _log('Function Call ID: ${toolContext.functionCallId}');
      _log('Arguments: ${_formatArgs(toolArgs)}');
      _log('Result: ${_formatArgs(result)}');
      _log('Error: $errorMessage');
      return null;
    }
    _log('TOOL COMPLETED');
    _log('Tool Name: ${tool.name}');
    _log('Agent: ${toolContext.agentName}');
    _log('Function Call ID: ${toolContext.functionCallId}');
    _log('Result: ${_formatArgs(result)}');
    return null;
  }

  /// Logs model errors.
  @override
  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    _log('LLM ERROR');
    _log('Agent: ${callbackContext.agentName}');
    _log('Error: $error');
    return null;
  }

  /// Logs tool-call errors.
  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    final List<String> lines = <String>[
      'TOOL ERROR',
      'Tool Name: ${tool.name}',
      'Agent: ${toolContext.agentName}',
      'Function Call ID: ${toolContext.functionCallId}',
      'Arguments: ${_formatArgs(toolArgs)}',
      'Error: $error',
    ];
    markToolErrorRecorded(this, toolContext);
    for (final String line in lines) {
      _log(line);
    }
    return null;
  }

  void _log(String message) {
    print('[$name] $message');
  }

  String _formatContent(Content? content, {int maxLength = 200}) {
    if (content == null || content.parts.isEmpty) {
      return 'None';
    }
    final List<String> parts = <String>[];
    for (final Part part in content.parts) {
      if (part.text != null) {
        String text = part.text!.trim();
        if (text.length > maxLength) {
          text = '${text.substring(0, maxLength)}...';
        }
        parts.add("text: '$text'");
      } else if (part.functionCall != null) {
        parts.add('function_call: ${part.functionCall!.name}');
      } else if (part.functionResponse != null) {
        parts.add('function_response: ${part.functionResponse!.name}');
      } else if (part.codeExecutionResult != null) {
        parts.add('code_execution_result');
      } else {
        parts.add('other_part');
      }
    }
    return parts.join(' | ');
  }

  String _formatArgs(Map<String, dynamic> args, {int maxLength = 300}) {
    if (args.isEmpty) {
      return '{}';
    }
    String value = args.toString();
    if (value.length > maxLength) {
      value = '${value.substring(0, maxLength)}...}';
    }
    return value;
  }

  String _formatValue(Object? value, {int maxLength = 300}) {
    String formatted = value is String ? "'$value'" : '$value';
    if (formatted.length > maxLength) {
      formatted = '${formatted.substring(0, maxLength)}...';
    }
    return formatted;
  }
}
