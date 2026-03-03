/// Built-in planner implementation for request-level thinking configuration.
library;

import 'dart:developer' as developer;

import '../agents/callback_context.dart';
import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_planner.dart';

/// Planner that injects a fixed thinking configuration into model requests.
class BuiltInPlanner extends BasePlanner {
  /// Creates a planner with a required [thinkingConfig].
  BuiltInPlanner({required this.thinkingConfig});

  /// Thinking config payload applied to outgoing requests.
  final Object thinkingConfig;

  /// Applies planner-owned thinking config to [llmRequest].
  void applyThinkingConfig(LlmRequest llmRequest) {
    if (llmRequest.config.thinkingConfig != null) {
      developer.log(
        'Overwriting existing thinkingConfig with BuiltInPlanner value.',
        name: 'adk_dart.planners',
      );
    }
    llmRequest.config.thinkingConfig = thinkingConfig;
  }

  /// Returns no additional planning instruction.
  @override
  String? buildPlanningInstruction(
    ReadonlyContext readonlyContext,
    LlmRequest llmRequest,
  ) {
    return null;
  }

  /// Returns no planner-specific response transformation.
  @override
  List<Part>? processPlanningResponse(
    CallbackContext callbackContext,
    List<Part> responseParts,
  ) {
    return null;
  }
}
