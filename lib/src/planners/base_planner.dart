import '../agents/callback_context.dart';
import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import '../types/content.dart';

abstract class BasePlanner {
  /// Builds system instruction appended to LLM request for planning.
  String? buildPlanningInstruction(
    ReadonlyContext readonlyContext,
    LlmRequest llmRequest,
  );

  /// Post-processes LLM response parts for planning contracts.
  List<Part>? processPlanningResponse(
    CallbackContext callbackContext,
    List<Part> responseParts,
  );
}
