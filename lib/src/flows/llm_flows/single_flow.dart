import '../../auth/auth_preprocessor.dart';
import 'base_llm_flow.dart';
import 'basic.dart';
import 'code_execution.dart';
import 'compaction.dart';
import 'contents.dart';
import 'context_cache_processor.dart';
import 'identity.dart';
import 'instructions.dart';
import 'interactions_processor.dart';
import 'nl_planning.dart';
import 'output_schema_processor.dart';
import 'request_confirmation.dart';

class SingleFlow extends BaseLlmFlow {
  SingleFlow() : super() {
    requestProcessors.addAll(<BaseLlmRequestProcessor>[
      BasicLlmRequestProcessor(),
      AuthLlmRequestProcessor(),
      RequestConfirmationLlmRequestProcessor(),
      InstructionsLlmRequestProcessor(),
      IdentityLlmRequestProcessor(),
      CompactionRequestProcessor(),
      ContentsLlmRequestProcessor(),
      ContextCacheRequestProcessor(),
      InteractionsRequestProcessor(),
      NlPlanningRequestProcessor(),
      CodeExecutionRequestProcessor(),
      OutputSchemaRequestProcessor(),
    ]);
    responseProcessors.addAll(<BaseLlmResponseProcessor>[
      NlPlanningResponseProcessor(),
      CodeExecutionResponseProcessor(),
    ]);
  }
}
