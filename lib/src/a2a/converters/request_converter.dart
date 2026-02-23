import '../../agents/run_config.dart';
import '../../types/content.dart';
import '../protocol.dart';
import 'part_converter.dart';

class AgentRunRequest {
  AgentRunRequest({
    this.userId,
    this.sessionId,
    this.invocationId,
    this.newMessage,
    this.stateDelta,
    this.runConfig,
  });

  String? userId;
  String? sessionId;
  String? invocationId;
  Content? newMessage;
  Map<String, Object?>? stateDelta;
  RunConfig? runConfig;
}

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
