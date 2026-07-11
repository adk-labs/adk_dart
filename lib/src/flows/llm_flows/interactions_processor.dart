/// LLM flow pipeline components and processors.
library;

import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import 'base_llm_flow.dart';

/// Extracts previous interaction id for stateful interaction APIs.
class InteractionsRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final (String? previousInteractionId, _) =
        findPreviousInteractionState(
      events: invocationContext.session.events,
      agentName: invocationContext.agent.name,
      currentBranch: invocationContext.branch,
    );
    if (previousInteractionId != null && previousInteractionId.isNotEmpty) {
      llmRequest.previousInteractionId = previousInteractionId;
    }
  }
}

/// Scans events in reverse to find the most recent (interactionId, environmentId) for [agentName].
(String?, String?) findPreviousInteractionState({
  required List<Event> events,
  required String agentName,
  required String? currentBranch,
}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (!_isEventInBranch(currentBranch, event)) {
      continue;
    }
    final String? interactionId = event.interactionId;
    if (event.author == agentName &&
        interactionId != null &&
        interactionId.isNotEmpty) {
      return (interactionId, event.environmentId);
    }
  }
  return (null, null);
}

bool _isEventInBranch(String? currentBranch, Event event) {
  if (currentBranch == null || currentBranch.isEmpty) {
    return event.branch == null || event.branch!.isEmpty;
  }
  return event.branch == currentBranch ||
      event.branch == null ||
      event.branch!.isEmpty;
}
