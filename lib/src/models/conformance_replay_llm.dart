/// Replay-only LLM used by conformance tests.
library;

import '../cli/plugins/conformance_recordings_schema.dart';
import '../cli/plugins/conformance_replay_plugin.dart'
    show ReplayConfigError, ReplayVerificationError;
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

/// Model adapter that replays recorded responses instead of calling a backend.
class ConformanceReplayLlm extends BaseLlm {
  /// Creates a replay model from serialized [config] and [agentName].
  ConformanceReplayLlm({
    required ConformanceJson config,
    required this.agentName,
  }) : _config = config,
       super(model: 'adk-conformance-replay');

  final ConformanceJson _config;
  final String agentName;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final Object? rawRecordings = _config['_adk_replay_recordings'];
    final ConformanceRecordings recordings = rawRecordings is Map
        ? ConformanceRecordings.fromJson(asConformanceObjectMap(rawRecordings))
        : throw ReplayConfigError('Replay recordings are not loaded.');
    final int userMessageIndex = asConformanceInt(
      _config['user_message_index'],
    );
    final int replayIndex = asConformanceInt(_config['current_replay_index']);

    final List<ConformanceLlmRecording> agentRecordings = recordings.recordings
        .where((ConformanceRecording recording) {
          return recording.agentName == agentName &&
              recording.userMessageIndex == userMessageIndex &&
              recording.llmRecording != null;
        })
        .map((ConformanceRecording recording) => recording.llmRecording!)
        .toList(growable: false);

    if (replayIndex >= agentRecordings.length) {
      throw ReplayVerificationError(
        'Runtime sent more LLM requests than expected for agent '
        "'$agentName' at user_message_index $userMessageIndex.",
      );
    }

    final ConformanceLlmRecording recording = agentRecordings[replayIndex];
    _verifyRequestMatch(
      recording.llmRequest,
      request,
      replayIndex: replayIndex,
      userMessageIndex: userMessageIndex,
    );

    for (final ConformanceJson response in recording.llmResponses) {
      yield deserializeLlmResponse(response);
    }
  }

  void _verifyRequestMatch(
    ConformanceJson recordedRequest,
    LlmRequest currentRequest, {
    required int replayIndex,
    required int userMessageIndex,
  }) {
    final String recorded = stableJsonSignature(
      canonicalizeSerializedLlmRequest(recordedRequest),
    );
    final String current = stableJsonSignature(
      canonicalizeSerializedLlmRequest(serializeLlmRequest(currentRequest)),
    );
    if (recorded != current) {
      throw ReplayVerificationError(
        "LLM request mismatch in turn $userMessageIndex for agent '$agentName' "
        '(index $replayIndex).',
      );
    }
  }
}
