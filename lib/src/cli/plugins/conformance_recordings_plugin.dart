/// Runtime plugin that records conformance LLM and tool interactions.
library;

import '../../agents/callback_context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import '../../utils/yaml_utils.dart';
import 'conformance_recordings_schema.dart';

class _InvocationRecordingState {
  _InvocationRecordingState({
    required this.testCasePath,
    required this.userMessageIndex,
    required this.recordings,
  });

  final String testCasePath;
  final int userMessageIndex;
  final ConformanceRecordings recordings;
  final Map<String, ConformanceRecording> pendingLlmRecordings =
      <String, ConformanceRecording>{};
  final Map<String, ConformanceRecording> pendingToolRecordings =
      <String, ConformanceRecording>{};
  final List<ConformanceRecording> pendingRecordingsOrder =
      <ConformanceRecording>[];
}

/// Records LLM and tool interactions when `_adk_recordings_config` is set.
class ConformanceRecordingsPlugin extends BasePlugin {
  /// Creates a conformance recordings plugin.
  ConformanceRecordingsPlugin({super.name = 'adk_conformance_recordings'});

  final Map<String, _InvocationRecordingState> _invocationStates =
      <String, _InvocationRecordingState>{};

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final CallbackContext context = CallbackContext(invocationContext);
    if (!_isRecordModeOn(context)) {
      return;
    }

    final _InvocationRecordingState state =
        _getInvocationState(context) ?? _createInvocationState(context);
    try {
      for (final ConformanceRecording pending in state.pendingRecordingsOrder) {
        if (pending.llmRecording != null) {
          if (pending.llmRecording!.llmResponses.isNotEmpty) {
            state.recordings.recordings.add(pending);
          }
          continue;
        }
        if (pending.toolRecording?.toolResponse != null) {
          state.recordings.recordings.add(pending);
        }
      }

      dumpPydanticToYaml(
        state.recordings.toJson(),
        '${state.testCasePath}/${_recordingsFileName(context)}',
        sortKeys: false,
      );
    } finally {
      _invocationStates.remove(context.invocationId);
    }
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    if (!_isRecordModeOn(callbackContext)) {
      return null;
    }

    final _InvocationRecordingState state =
        _getInvocationState(callbackContext) ??
        _createInvocationState(callbackContext);
    final ConformanceRecording recording = ConformanceRecording(
      userMessageIndex: state.userMessageIndex,
      agentName: callbackContext.agentName,
      llmRecording: ConformanceLlmRecording(
        llmRequest: serializeLlmRequest(llmRequest),
      ),
    );
    state.pendingLlmRecordings[callbackContext.agentName] = recording;
    state.pendingRecordingsOrder.add(recording);
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    if (!_isRecordModeOn(callbackContext)) {
      return null;
    }

    final _InvocationRecordingState state =
        _getInvocationState(callbackContext) ??
        _createInvocationState(callbackContext);
    final ConformanceRecording? pending =
        state.pendingLlmRecordings[callbackContext.agentName];
    if (pending?.llmRecording == null) {
      return null;
    }
    pending!.llmRecording!.llmResponses.add(serializeLlmResponse(llmResponse));
    if (llmResponse.partial != true) {
      state.pendingLlmRecordings.remove(callbackContext.agentName);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    if (!_isRecordModeOn(toolContext)) {
      return null;
    }
    final String? functionCallId = toolContext.functionCallId;
    if (functionCallId == null || functionCallId.isEmpty) {
      return null;
    }

    final _InvocationRecordingState state =
        _getInvocationState(toolContext) ?? _createInvocationState(toolContext);
    final ConformanceRecording recording = ConformanceRecording(
      userMessageIndex: state.userMessageIndex,
      agentName: toolContext.agentName,
      toolRecording: ConformanceToolRecording(
        toolCall: serializeToolCall(
          id: functionCallId,
          name: tool.name,
          args: toolArgs,
        ),
      ),
    );
    state.pendingToolRecordings[functionCallId] = recording;
    state.pendingRecordingsOrder.add(recording);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    if (!_isRecordModeOn(toolContext)) {
      return null;
    }
    final String? functionCallId = toolContext.functionCallId;
    if (functionCallId == null || functionCallId.isEmpty) {
      return null;
    }

    final _InvocationRecordingState state =
        _getInvocationState(toolContext) ?? _createInvocationState(toolContext);
    final ConformanceRecording? pending = state.pendingToolRecordings.remove(
      functionCallId,
    );
    if (pending?.toolRecording == null) {
      return null;
    }
    pending!.toolRecording = ConformanceToolRecording(
      toolCall: pending.toolRecording!.toolCall,
      toolResponse: serializeToolResponse(
        id: functionCallId,
        name: tool.name,
        response: result,
      ),
    );
    return null;
  }

  bool _isRecordModeOn(ReadonlyContext callbackContext) {
    final Object? rawConfig = callbackContext.state['_adk_recordings_config'];
    if (rawConfig is! Map) {
      return false;
    }
    final ConformanceJson config = asConformanceObjectMap(rawConfig);
    return '${config['dir'] ?? ''}'.isNotEmpty &&
        config['user_message_index'] != null;
  }

  _InvocationRecordingState? _getInvocationState(ReadonlyContext context) {
    return _invocationStates[context.invocationId];
  }

  _InvocationRecordingState _createInvocationState(ReadonlyContext context) {
    final ConformanceJson config = asConformanceObjectMap(
      context.state['_adk_recordings_config'],
    );
    final String testCasePath = '${config['dir'] ?? ''}'.trim();
    final int userMessageIndex = asConformanceInt(config['user_message_index']);
    if (testCasePath.isEmpty) {
      throw StateError('Conformance recording directory is missing.');
    }

    final String recordingsPath =
        '$testCasePath/${_recordingsFileName(context)}';
    ConformanceRecordings recordings = ConformanceRecordings();
    try {
      final Object? decoded = loadYamlFile(recordingsPath);
      if (decoded is Map) {
        recordings = ConformanceRecordings.fromJson(
          asConformanceObjectMap(decoded),
        );
      }
    } on Exception {
      recordings = ConformanceRecordings();
    }

    final _InvocationRecordingState state = _InvocationRecordingState(
      testCasePath: testCasePath,
      userMessageIndex: userMessageIndex,
      recordings: recordings,
    );
    _invocationStates[context.invocationId] = state;
    return state;
  }

  String _recordingsFileName(ReadonlyContext context) {
    final ConformanceJson config = asConformanceObjectMap(
      context.state['_adk_recordings_config'],
    );
    return '${config['streaming_mode'] ?? 'none'}' == 'sse'
        ? 'generated-recordings-sse.yaml'
        : 'generated-recordings.yaml';
  }
}
