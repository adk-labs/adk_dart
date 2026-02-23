import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import 'base_llm_flow.dart';

/// Enables context-cache config and cache metadata reuse on requests.
class ContextCacheRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final Object? cacheConfig = invocationContext.contextCacheConfig;
    if (cacheConfig == null) {
      return;
    }

    llmRequest.cacheConfig = cacheConfig;

    final (Object? cacheMetadata, int? previousTokenCount) = _findCacheInfo(
      invocationContext,
      invocationContext.agent.name,
      invocationContext.invocationId,
    );

    if (cacheMetadata != null) {
      llmRequest.cacheMetadata = cacheMetadata;
    }
    if (previousTokenCount != null) {
      llmRequest.cacheableContentsTokenCount = previousTokenCount;
    }
  }
}

(Object?, int?) _findCacheInfo(
  InvocationContext invocationContext,
  String agentName,
  String currentInvocationId,
) {
  Object? cacheMetadata;
  int? previousTokenCount;

  final List<Event> events = invocationContext.session.events;
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (event.author != agentName) {
      continue;
    }

    if (cacheMetadata == null && event.cacheMetadata != null) {
      cacheMetadata = event.cacheMetadata;
      if (event.invocationId != currentInvocationId && cacheMetadata is Map) {
        final Map<String, dynamic> copied = Map<String, dynamic>.from(
          cacheMetadata.cast<String, dynamic>(),
        );
        final int invocationsUsed = _readInt(copied['invocations_used']) ?? 0;
        copied['invocations_used'] = invocationsUsed + 1;
        cacheMetadata = copied;
      }
    }

    if (previousTokenCount == null) {
      previousTokenCount = _extractPromptTokenCount(event.usageMetadata);
    }

    if (cacheMetadata != null && previousTokenCount != null) {
      break;
    }
  }

  return (cacheMetadata, previousTokenCount);
}

int? _extractPromptTokenCount(Object? usageMetadata) {
  if (usageMetadata is Map) {
    final Object? value =
        usageMetadata['promptTokenCount'] ??
        usageMetadata['prompt_token_count'];
    return _readInt(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
