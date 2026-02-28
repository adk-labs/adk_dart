import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../planners/base_planner.dart';
import '../../planners/built_in_planner.dart';
import '../../planners/plan_re_act_planner.dart';
import '../../types/content.dart';
import '../llm_flows/base_llm_flow.dart';

class NlPlanningRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final BasePlanner? planner = _getPlanner(invocationContext);
    if (planner == null) {
      return;
    }

    if (planner is BuiltInPlanner) {
      planner.applyThinkingConfig(llmRequest);
    } else if (planner is PlanReActPlanner) {
      final String planningInstruction = planner.buildPlanningInstruction(
        ReadonlyContext(invocationContext),
        llmRequest,
      );
      if (planningInstruction.isNotEmpty) {
        llmRequest.appendInstructions(<String>[planningInstruction]);
      }
      _removeThoughtFromRequest(llmRequest);
    }
  }
}

class NlPlanningResponseProcessor extends BaseLlmResponseProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmResponse llmResponse,
  ) async* {
    final content = llmResponse.content;
    if (content == null || content.parts.isEmpty) {
      return;
    }

    final BasePlanner? planner = _getPlanner(invocationContext);
    if (planner == null || planner is BuiltInPlanner) {
      return;
    }

    final Context callbackContext = Context(invocationContext);
    final List<Part> parts = content.parts;
    final List<Part>? processed = planner.processPlanningResponse(
      callbackContext,
      List<Part>.from(parts.map((Part part) => part.copyWith())),
    );

    if (processed != null && processed.isNotEmpty) {
      content.parts = processed;
    }

    if (callbackContext.state.hasDelta()) {
      yield Event(
        invocationId: invocationContext.invocationId,
        author: invocationContext.agent.name,
        branch: invocationContext.branch,
        actions: callbackContext.actions,
      );
    }
  }
}

BasePlanner? _getPlanner(InvocationContext invocationContext) {
  final dynamic agent = invocationContext.agent;
  if (agent is! LlmAgent) {
    return null;
  }

  final Object? planner = agent.planner;
  if (_isFalsyPlannerValue(planner)) {
    return null;
  }

  if (planner is BasePlanner) {
    return planner;
  }
  return PlanReActPlanner();
}

bool _isFalsyPlannerValue(Object? planner) {
  if (planner == null) {
    return true;
  }
  if (planner is bool) {
    return planner == false;
  }
  if (planner is String) {
    return planner.isEmpty;
  }
  if (planner is num) {
    return planner == 0;
  }
  if (planner is Iterable) {
    return planner.isEmpty;
  }
  if (planner is Map) {
    return planner.isEmpty;
  }
  return false;
}

void _removeThoughtFromRequest(LlmRequest llmRequest) {
  if (llmRequest.contents.isEmpty) {
    return;
  }

  for (final content in llmRequest.contents) {
    for (final part in content.parts) {
      part.thought = false;
    }
  }
}
