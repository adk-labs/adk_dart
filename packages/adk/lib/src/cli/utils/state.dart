/// Helpers for deriving initial CLI state values from agent instructions.
library;

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/workflow/workflow.dart';

void _createEmptyState(
  Object agentOrNode,
  Map<String, Object?> allState,
  Set<Object> visited,
) {
  if (!visited.add(agentOrNode)) {
    return;
  }

  if (agentOrNode is BaseAgent) {
    for (final BaseAgent subAgent in agentOrNode.subAgents) {
      _createEmptyState(subAgent, allState, visited);
    }
  }

  if (agentOrNode is Workflow) {
    for (final BaseNode graphNode in agentOrNode.nodes) {
      _createEmptyState(graphNode, allState, visited);
    }
  } else if (agentOrNode is AgentNode) {
    _createEmptyState(agentOrNode.agent, allState, visited);
  }

  if (agentOrNode is LlmAgent &&
      agentOrNode.instruction is String &&
      (agentOrNode.instruction as String).isNotEmpty) {
    final Iterable<Match> matches = RegExp(
      r'{([\w]+)}',
    ).allMatches(agentOrNode.instruction as String);
    for (final Match match in matches) {
      final String? key = match.group(1);
      if (key != null && key.isNotEmpty) {
        allState[key] = '';
      }
    }
  }
}

/// Creates an empty state map inferred from [agent] instruction placeholders.
///
/// Accepts a [BaseAgent] or workflow [BaseNode]. Keys already provided in
/// [initializedStates] are excluded from the result.
Map<String, Object?> createEmptyState(
  Object agent, {
  Map<String, Object?>? initializedStates,
}) {
  final Map<String, Object?> nonInitialized = <String, Object?>{};
  _createEmptyState(agent, nonInitialized, Set<Object>.identity());
  for (final String key in initializedStates?.keys ?? const <String>[]) {
    nonInitialized.remove(key);
  }
  return nonInitialized;
}
