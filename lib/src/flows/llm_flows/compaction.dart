import '../../agents/invocation_context.dart';
import '../../apps/compaction.dart' as app_compaction;
import '../../events/event.dart';
import '../../models/llm_request.dart';
import 'base_llm_flow.dart';

/// Runs token-threshold compaction before contents are prepared.
class CompactionRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final bool compacted = await app_compaction
        .runCompactionForTokenThresholdConfig(
          config: invocationContext.eventsCompactionConfig,
          session: invocationContext.session,
          sessionService: invocationContext.sessionService,
          agentName: invocationContext.agent.name,
          currentBranch: invocationContext.branch,
        );
    if (compacted) {
      invocationContext.tokenCompactionChecked = true;
    }
  }
}
