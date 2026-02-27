import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../utils/output_schema_utils.dart';
import 'base_llm_flow.dart';

/// Populates baseline request fields from agent configuration.
class BasicLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    llmRequest.model = agent.canonicalModel.model;
    llmRequest.config =
        agent.generateContentConfig?.copyWith() ?? GenerateContentConfig();

    // Keep parity with Python behavior: set output schema directly when tools
    // are absent or when model supports native schema+tools together.
    if (agent.outputSchema != null &&
        (agent.tools.isEmpty ||
            canUseOutputSchemaWithTools(agent.canonicalModel))) {
      llmRequest.setOutputSchema(agent.outputSchema!);
    }

    final runConfig = invocationContext.runConfig;
    if (runConfig != null) {
      llmRequest.liveConnectConfig.responseModalities =
          runConfig.responseModalities;
      llmRequest.liveConnectConfig.speechConfig = runConfig.speechConfig;
      llmRequest.liveConnectConfig.outputAudioTranscription =
          runConfig.outputAudioTranscription;
      llmRequest.liveConnectConfig.inputAudioTranscription =
          runConfig.inputAudioTranscription;
      llmRequest.liveConnectConfig.realtimeInputConfig =
          runConfig.realtimeInputConfig;
      llmRequest.liveConnectConfig.enableAffectiveDialog =
          runConfig.enableAffectiveDialog;
      llmRequest.liveConnectConfig.proactivity = runConfig.proactivity;
      llmRequest.liveConnectConfig.sessionResumption =
          runConfig.sessionResumption;
      llmRequest.liveConnectConfig.contextWindowCompression =
          runConfig.contextWindowCompression;
    }
  }
}
