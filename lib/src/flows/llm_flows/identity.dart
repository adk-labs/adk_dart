import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import 'base_llm_flow.dart';

/// Adds framework-provided agent identity instructions.
class IdentityLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    String instruction =
        'You are an agent. Your internal name is "${agent.name}".';
    final String description = agent.description;
    if (description.isNotEmpty) {
      instruction += ' The description about you is "$description".';
    }
    llmRequest.appendInstructions(<String>[instruction]);
  }
}
