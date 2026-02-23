import 'dart:convert';
import 'dart:io';

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

class _DebugEntry {
  _DebugEntry({
    required this.timestamp,
    required this.entryType,
    this.invocationId,
    this.agentName,
    Map<String, Object?>? data,
  }) : data = data ?? <String, Object?>{};

  final String timestamp;
  final String entryType;
  final String? invocationId;
  final String? agentName;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp,
      'entry_type': entryType,
      if (invocationId != null) 'invocation_id': invocationId,
      if (agentName != null) 'agent_name': agentName,
      'data': data,
    };
  }
}

class _InvocationDebugState {
  _InvocationDebugState({
    required this.invocationId,
    required this.sessionId,
    required this.appName,
    required this.startTime,
    this.userId,
  });

  final String invocationId;
  final String sessionId;
  final String appName;
  final String? userId;
  final String startTime;
  final List<_DebugEntry> entries = <_DebugEntry>[];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'invocation_id': invocationId,
      'session_id': sessionId,
      'app_name': appName,
      if (userId != null) 'user_id': userId,
      'start_time': startTime,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class DebugLoggingPlugin extends BasePlugin {
  DebugLoggingPlugin({
    super.name = 'debug_logging_plugin',
    String outputPath = 'adk_debug.yaml',
    bool includeSessionState = true,
    bool includeSystemInstruction = true,
  }) : _outputFile = File(outputPath),
       _includeSessionState = includeSessionState,
       _includeSystemInstruction = includeSystemInstruction;

  final File _outputFile;
  final bool _includeSessionState;
  final bool _includeSystemInstruction;
  final Map<String, _InvocationDebugState> _invocationStates =
      <String, _InvocationDebugState>{};

  String _getTimestamp() => DateTime.now().toIso8601String();

  Map<String, Object?>? _serializeContent(Content? content) {
    if (content == null) {
      return null;
    }

    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    for (final Part part in content.parts) {
      final Map<String, Object?> partData = <String, Object?>{};
      if (part.text != null) {
        partData['text'] = part.text;
      }
      if (part.functionCall != null) {
        partData['function_call'] = <String, Object?>{
          if (part.functionCall!.id != null) 'id': part.functionCall!.id,
          'name': part.functionCall!.name,
          'args': _safeSerialize(part.functionCall!.args),
        };
      }
      if (part.functionResponse != null) {
        partData['function_response'] = <String, Object?>{
          if (part.functionResponse!.id != null)
            'id': part.functionResponse!.id,
          'name': part.functionResponse!.name,
          'response': _safeSerialize(part.functionResponse!.response),
        };
      }
      if (part.inlineData != null) {
        partData['inline_data'] = <String, Object?>{
          'mime_type': part.inlineData!.mimeType,
          if (part.inlineData!.displayName != null)
            'display_name': part.inlineData!.displayName,
          '_data_omitted': true,
        };
      }
      if (part.fileData != null) {
        partData['file_data'] = <String, Object?>{
          'file_uri': part.fileData!.fileUri,
          if (part.fileData!.mimeType != null)
            'mime_type': part.fileData!.mimeType,
          if (part.fileData!.displayName != null)
            'display_name': part.fileData!.displayName,
        };
      }
      if (part.codeExecutionResult != null) {
        partData['code_execution_result'] = _safeSerialize(
          part.codeExecutionResult,
        );
      }
      if (part.executableCode != null) {
        partData['executable_code'] = _safeSerialize(part.executableCode);
      }
      if (partData.isNotEmpty) {
        parts.add(partData);
      }
    }

    return <String, Object?>{
      if (content.role != null) 'role': content.role,
      'parts': parts,
    };
  }

  Object? _safeSerialize(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) {
      return value.map(_safeSerialize).toList(growable: false);
    }
    if (value is Set) {
      return value.map(_safeSerialize).toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? item) => MapEntry('$key', _safeSerialize(item)),
      );
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    return '$value';
  }

  void _addEntry(
    String invocationId,
    String entryType, {
    String? agentName,
    Map<String, Object?>? data,
  }) {
    final _InvocationDebugState? state = _invocationStates[invocationId];
    if (state == null) {
      return;
    }
    state.entries.add(
      _DebugEntry(
        timestamp: _getTimestamp(),
        entryType: entryType,
        invocationId: invocationId,
        agentName: agentName,
        data: data,
      ),
    );
  }

  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    _addEntry(
      invocationContext.invocationId,
      'user_message',
      data: <String, Object?>{'content': _serializeContent(userMessage)},
    );
    return null;
  }

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final _InvocationDebugState state = _InvocationDebugState(
      invocationId: invocationContext.invocationId,
      sessionId: invocationContext.session.id,
      appName: invocationContext.session.appName,
      userId: invocationContext.userId,
      startTime: _getTimestamp(),
    );
    _invocationStates[invocationContext.invocationId] = state;

    _addEntry(
      invocationContext.invocationId,
      'invocation_start',
      agentName: invocationContext.agent.name,
      data: <String, Object?>{'branch': invocationContext.branch},
    );
    return null;
  }

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    _addEntry(
      invocationContext.invocationId,
      'event',
      agentName: event.author,
      data: <String, Object?>{
        'event_id': event.id,
        'author': event.author,
        'content': _serializeContent(event.content),
        'is_final_response': event.isFinalResponse(),
        'partial': event.partial,
        'turn_complete': event.turnComplete,
        'branch': event.branch,
        'actions': _safeSerialize(<String, Object?>{
          'state_delta': event.actions.stateDelta,
          'artifact_delta': event.actions.artifactDelta,
          'transfer_to_agent': event.actions.transferToAgent,
          'escalate': event.actions.escalate,
          'requested_auth_configs': event.actions.requestedAuthConfigs.length,
        }),
        'error_code': event.errorCode,
        'error_message': event.errorMessage,
        'long_running_tool_ids': event.longRunningToolIds?.toList(),
      },
    );
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final String invocationId = invocationContext.invocationId;
    final _InvocationDebugState? state = _invocationStates[invocationId];
    if (state == null) {
      return;
    }

    if (_includeSessionState) {
      _addEntry(
        invocationId,
        'session_state_snapshot',
        data: <String, Object?>{
          'state':
              _safeSerialize(invocationContext.session.state)
                  as Map<String, Object?>?,
          'event_count': invocationContext.session.events.length,
        },
      );
    }

    _addEntry(invocationId, 'invocation_end');

    final Map<String, Object?> outputData = state.toJson();
    final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    await _outputFile.parent.create(recursive: true);
    await _outputFile.writeAsString(
      '---\n${encoder.convert(outputData)}\n',
      mode: FileMode.append,
      flush: true,
    );

    _invocationStates.remove(invocationId);
  }

  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    _addEntry(
      callbackContext.invocationId,
      'agent_start',
      agentName: callbackContext.agentName,
      data: <String, Object?>{
        'branch': callbackContext.invocationContext.branch,
      },
    );
    return null;
  }

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    _addEntry(
      callbackContext.invocationId,
      'agent_end',
      agentName: callbackContext.agentName,
    );
    return null;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final Map<String, Object?> requestData = <String, Object?>{
      'model': llmRequest.model,
      'content_count': llmRequest.contents.length,
      'contents': llmRequest.contents
          .map(_serializeContent)
          .toList(growable: false),
    };
    if (llmRequest.toolsDict.isNotEmpty) {
      requestData['tools'] = llmRequest.toolsDict.keys.toList();
    }

    final Map<String, Object?> configData = <String, Object?>{};
    final String? systemInstruction = llmRequest.config.systemInstruction;
    if (systemInstruction != null) {
      if (_includeSystemInstruction) {
        configData['system_instruction'] = systemInstruction;
      } else {
        configData['system_instruction_length'] = systemInstruction.length;
      }
    }
    if (llmRequest.config.thinkingConfig != null) {
      configData['thinking_config'] = _safeSerialize(
        llmRequest.config.thinkingConfig,
      );
    }
    if (llmRequest.config.responseMimeType != null) {
      configData['response_mime_type'] = llmRequest.config.responseMimeType;
    }
    if (llmRequest.config.responseSchema != null) {
      configData['has_response_schema'] = true;
    }
    if (configData.isNotEmpty) {
      requestData['config'] = configData;
    }

    _addEntry(
      callbackContext.invocationId,
      'llm_request',
      agentName: callbackContext.agentName,
      data: requestData,
    );
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    _addEntry(
      callbackContext.invocationId,
      'llm_response',
      agentName: callbackContext.agentName,
      data: <String, Object?>{
        'content': _serializeContent(llmResponse.content),
        'partial': llmResponse.partial,
        'turn_complete': llmResponse.turnComplete,
        'error_code': llmResponse.errorCode,
        'error_message': llmResponse.errorMessage,
        'usage_metadata': _safeSerialize(llmResponse.usageMetadata),
        'finish_reason': llmResponse.finishReason,
        'model_version': llmResponse.modelVersion,
      },
    );
    return null;
  }

  @override
  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    _addEntry(
      callbackContext.invocationId,
      'llm_error',
      agentName: callbackContext.agentName,
      data: <String, Object?>{
        'error_type': error.runtimeType.toString(),
        'error_message': '$error',
        'model': llmRequest.model,
      },
    );
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    _addEntry(
      toolContext.invocationId,
      'tool_call',
      agentName: toolContext.agentName,
      data: <String, Object?>{
        'tool_name': tool.name,
        'function_call_id': toolContext.functionCallId,
        'args': _safeSerialize(toolArgs) as Map<String, Object?>?,
      },
    );
    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    _addEntry(
      toolContext.invocationId,
      'tool_response',
      agentName: toolContext.agentName,
      data: <String, Object?>{
        'tool_name': tool.name,
        'function_call_id': toolContext.functionCallId,
        'result': _safeSerialize(result) as Map<String, Object?>?,
      },
    );
    return null;
  }

  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    _addEntry(
      toolContext.invocationId,
      'tool_error',
      agentName: toolContext.agentName,
      data: <String, Object?>{
        'tool_name': tool.name,
        'function_call_id': toolContext.functionCallId,
        'args': _safeSerialize(toolArgs) as Map<String, Object?>?,
        'error_type': error.runtimeType.toString(),
        'error_message': '$error',
      },
    );
    return null;
  }
}
