import 'dart:convert';

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../tools/set_model_response_tool.dart';
import '../../types/content.dart';
import '../../utils/output_schema_utils.dart';
import 'base_llm_flow.dart';

/// Handles output schema when the agent also has tools.
class OutputSchemaRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    if (agent.outputSchema == null ||
        agent.tools.isEmpty ||
        canUseOutputSchemaWithTools(agent.canonicalModel)) {
      return;
    }

    // Preserve Python parity fallback for unsupported model+tool combinations.
    final SetModelResponseTool setResponseTool = SetModelResponseTool(
      agent.outputSchema!,
    );
    llmRequest.appendTools(<SetModelResponseTool>[setResponseTool]);
    llmRequest.appendInstructions(<String>[
      'IMPORTANT: You have access to other tools, but you must provide '
          'your final response using the set_model_response tool with the '
          'required structured format. After using any other tools needed '
          'to complete the task, always call set_model_response with your '
          'final answer in the specified schema format.',
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
