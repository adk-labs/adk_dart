/// Converters from A2A request envelopes to runner request payloads.
library;

import '../../agents/run_config.dart';
import '../../types/content.dart';
import '../protocol.dart';
import 'part_converter.dart';

/// Normalized runner request derived from an A2A request.
class AgentRunRequest {
  /// Creates an agent-run request.
  AgentRunRequest({
    this.userId,
    this.sessionId,
    this.invocationId,
    this.newMessage,
    this.stateDelta,
    this.runConfig,
  });

  /// User identifier.
  String? userId;

  /// Session identifier.
  String? sessionId;

  /// Invocation identifier.
  String? invocationId;

  /// Incoming user message content.
  Content? newMessage;

  /// Optional state delta applied before execution.
  Map<String, Object?>? stateDelta;

  /// Optional run configuration.
  RunConfig? runConfig;
}

/// Converter signature from [A2aRequestContext] to [AgentRunRequest].
typedef A2ARequestToAgentRunRequestConverter =
    AgentRunRequest Function(
      A2aRequestContext request,
      A2APartToGenAIPartConverter partConverter,
    );

String _getUserId(A2aRequestContext request) {
  final String? userName = request.callContext?.user?.userName;
  if (userName != null && userName.trim().isNotEmpty) {
    return userName;
  }
  return 'A2A_USER_${request.contextId}';
}

/// Converts an [A2aRequestContext] into an [AgentRunRequest].
AgentRunRequest convertA2aRequestToAgentRunRequest(
  A2aRequestContext request, {
  A2APartToGenAIPartConverter partConverter = convertA2aPartToGenaiPart,
}) {
  final A2aMessage? message = request.message;
  if (message == null) {
    throw ArgumentError('Request message cannot be null.');
  }

  final Map<String, dynamic> customMetadata = <String, dynamic>{};
  if (request.metadata.isNotEmpty) {
    customMetadata['a2a_metadata'] = Map<String, Object?>.from(
      request.metadata,
    );
  }

  final List<Part> outputParts = <Part>[];
  for (final A2aPart a2aPart in message.parts) {
    final Object? converted = partConverter(a2aPart);
    if (converted is Part) {
      outputParts.add(converted);
      continue;
    }
    if (converted is List<Part>) {
      outputParts.addAll(converted);
    }
  }

  return AgentRunRequest(
    userId: _getUserId(request),
    sessionId: request.contextId,
    newMessage: Content(role: 'user', parts: outputParts),
    runConfig: RunConfig(customMetadata: customMetadata),
  );
}
