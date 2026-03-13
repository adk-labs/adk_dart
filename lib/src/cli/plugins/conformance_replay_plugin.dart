/// Runtime plugin that replays recorded conformance tool interactions.
library;

import '../../agents/callback_context.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/readonly_context.dart';
import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import '../../utils/yaml_utils.dart';
import 'conformance_recordings_schema.dart';

class _InvocationReplayState {
  _InvocationReplayState({
    required this.testCasePath,
    required this.userMessageIndex,
    required this.recordings,
  });

  final String testCasePath;
  final int userMessageIndex;
  final ConformanceRecordings recordings;
  final Map<String, int> agentToolReplayIndices = <String, int>{};
}

/// Error raised when replay configuration is invalid.
class ReplayConfigError implements Exception {
  /// Creates a replay config error.
  ReplayConfigError(this.message);

  /// Error message.
  final String message;

  @override
  String toString() => 'ReplayConfigError: $message';
}

/// Error raised when runtime behavior diverges from recordings.
class ReplayVerificationError implements Exception {
  /// Creates a replay verification error.
  ReplayVerificationError(this.message);

  /// Error message.
  final String message;

  @override
  String toString() => 'ReplayVerificationError: $message';
}

/// Replays tool responses when `_adk_replay_config` is set.
class ConformanceReplayPlugin extends BasePlugin {
  /// Creates a conformance replay plugin.
  ConformanceReplayPlugin({super.name = 'adk_conformance_replay'});

  final Map<String, _InvocationReplayState> _invocationStates =
      <String, _InvocationReplayState>{};

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final CallbackContext context = CallbackContext(invocationContext);
    if (_isReplayModeOn(context)) {
      _loadInvocationState(context);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    if (!_isReplayModeOn(toolContext)) {
      return null;
    }

    final _InvocationReplayState state =
        _getInvocationState(toolContext) ?? _loadInvocationState(toolContext);
    final ConformanceToolRecording recording =
        _verifyAndGetNextToolRecordingForAgent(
          state,
          toolContext.agentName,
          tool.name,
          toolArgs,
        );
    final ConformanceJson? toolResponse = recording.toolResponse;
    if (toolResponse == null) {
      throw ReplayVerificationError(
        'Missing recorded tool response for ${tool.name}.',
      );
    }
    return asConformanceDynamicMap(toolResponse['response']) ??
        <String, dynamic>{};
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final CallbackContext context = CallbackContext(invocationContext);
    if (_isReplayModeOn(context)) {
      _invocationStates.remove(context.invocationId);
    }
  }

  bool _isReplayModeOn(ReadonlyContext callbackContext) {
    final Object? rawConfig = callbackContext.state['_adk_replay_config'];
    if (rawConfig is! Map) {
      return false;
    }
    final ConformanceJson config = asConformanceObjectMap(rawConfig);
    return '${config['dir'] ?? ''}'.isNotEmpty &&
        config['user_message_index'] != null;
  }

  _InvocationReplayState? _getInvocationState(ReadonlyContext context) {
    return _invocationStates[context.invocationId];
  }

  _InvocationReplayState _loadInvocationState(Context context) {
    final Object? rawConfig = context.state['_adk_replay_config'];
    final ConformanceJson config = rawConfig is Map<String, Object?>
        ? rawConfig
        : asConformanceObjectMap(rawConfig);
    context.state['_adk_replay_config'] = config;
    final String caseDir = '${config['dir'] ?? ''}'.trim();
    final int userMessageIndex = asConformanceInt(config['user_message_index']);
    if (caseDir.isEmpty) {
      throw ReplayConfigError(
        'Replay parameters are missing from session state.',
      );
    }

    final String recordingsPath = '$caseDir/${_recordingsFileName(config)}';
    final Object? decoded = loadYamlFile(recordingsPath);
    if (decoded is! Map) {
      throw ReplayConfigError(
        'Recordings file format is invalid: $recordingsPath',
      );
    }

    final ConformanceRecordings recordings = ConformanceRecordings.fromJson(
      asConformanceObjectMap(decoded),
    );
    config['_adk_replay_recordings'] = recordings.toJson();
    config['_adk_replay_indexes'] =
        config['_adk_replay_indexes'] ?? <String, Object?>{};

    final _InvocationReplayState state = _InvocationReplayState(
      testCasePath: caseDir,
      userMessageIndex: userMessageIndex,
      recordings: recordings,
    );
    _invocationStates[context.invocationId] = state;
    return state;
  }

  ConformanceToolRecording _verifyAndGetNextToolRecordingForAgent(
    _InvocationReplayState state,
    String agentName,
    String toolName,
    Map<String, dynamic> toolArgs,
  ) {
    final int currentIndex = state.agentToolReplayIndices[agentName] ?? 0;
    final List<ConformanceToolRecording> agentRecordings = state
        .recordings
        .recordings
        .where((ConformanceRecording recording) {
          return recording.agentName == agentName &&
              recording.userMessageIndex == state.userMessageIndex &&
              recording.toolRecording != null;
        })
        .map((ConformanceRecording recording) => recording.toolRecording!)
        .toList(growable: false);

    if (currentIndex >= agentRecordings.length) {
      throw ReplayVerificationError(
        'Runtime sent more tool requests than expected for agent '
        "'$agentName' at user_message_index ${state.userMessageIndex}.",
      );
    }

    final ConformanceToolRecording expected = agentRecordings[currentIndex];
    state.agentToolReplayIndices[agentName] = currentIndex + 1;

    final ConformanceJson toolCall = expected.toolCall;
    final String recordedName = '${toolCall['name'] ?? ''}';
    final String recordedArgs = stableJsonSignature(toolCall['args']);
    final String currentArgs = stableJsonSignature(toolArgs);
    if (recordedName != toolName) {
      throw ReplayVerificationError(
        "Tool name mismatch for agent '$agentName' at index $currentIndex: "
        "recorded '$recordedName', current '$toolName'.",
      );
    }
    if (recordedArgs != currentArgs) {
      throw ReplayVerificationError(
        'Tool args mismatch for agent '
        "'$agentName' at index $currentIndex: recorded ${toolCall['args']}, current $toolArgs.",
      );
    }

    return expected;
  }

  String _recordingsFileName(ConformanceJson config) {
    return '${config['streaming_mode'] ?? 'none'}' == 'sse'
        ? 'generated-recordings-sse.yaml'
        : 'generated-recordings.yaml';
  }
}
