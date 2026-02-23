import 'dart:convert';

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../tools/set_model_response_tool.dart';
import '../../types/content.dart';
import 'base_llm_flow.dart';

/// Handles output schema when the agent also has tools.
class OutputSchemaRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    if (agent.outputSchema == null || agent.tools.isEmpty) {
      return;
    }

    // Dart currently assumes tools+response schema needs set_model_response.
    final SetModelResponseTool setResponseTool = SetModelResponseTool(
      agent.outputSchema!,
    );
    llmRequest.appendTools(<SetModelResponseTool>[setResponseTool]);
    llmRequest.appendInstructions(<String>[
      'IMPORTANT: You can use other tools, but final answer must be returned '
          'using `set_model_response` in the required structured format.',
    ]);
  }
}

String? getStructuredModelResponse(Event functionResponseEvent) {
  for (final FunctionResponse functionResponse
      in functionResponseEvent.getFunctionResponses()) {
    if (functionResponse.name == 'set_model_response') {
      return jsonEncode(functionResponse.response);
    }
  }
  return null;
}

Event createFinalModelResponseEvent(
  InvocationContext invocationContext,
  String jsonResponse,
) {
  return Event(
    invocationId: invocationContext.invocationId,
    author: invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: 'model', parts: <Part>[Part.text(jsonResponse)]),
  );
}
