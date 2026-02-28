import 'dart:developer' as developer;

import '../agents/callback_context.dart';
import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_planner.dart';

class BuiltInPlanner extends BasePlanner {
  BuiltInPlanner({required this.thinkingConfig});

  final Object thinkingConfig;

  void applyThinkingConfig(LlmRequest llmRequest) {
    if (llmRequest.config.thinkingConfig != null) {
      developer.log(
        'Overwriting existing thinkingConfig with BuiltInPlanner value.',
        name: 'adk_dart.planners',
      );
    }
    llmRequest.config.thinkingConfig = thinkingConfig;
  }

  @override
  String? buildPlanningInstruction(
    ReadonlyContext readonlyContext,
    LlmRequest llmRequest,
  ) {
    return null;
  }

  @override
  List<Part>? processPlanningResponse(
    CallbackContext callbackContext,
    List<Part> responseParts,
  ) {
    return null;
  }
}
