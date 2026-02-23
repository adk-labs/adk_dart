import '../../agents/base_agent.dart';
import '../../agents/llm_agent.dart';

void _createEmptyState(BaseAgent agent, Map<String, Object?> allState) {
  for (final BaseAgent subAgent in agent.subAgents) {
    _createEmptyState(subAgent, allState);
  }

  if (agent is LlmAgent &&
      agent.instruction is String &&
      (agent.instruction as String).isNotEmpty) {
    final Iterable<Match> matches = RegExp(
      r'{([\w]+)}',
    ).allMatches(agent.instruction as String);
    for (final Match match in matches) {
      final String? key = match.group(1);
      if (key != null && key.isNotEmpty) {
        allState[key] = '';
      }
    }
  }
}

Map<String, Object?> createEmptyState(
  BaseAgent agent, {
  Map<String, Object?>? initializedStates,
}) {
  final Map<String, Object?> nonInitialized = <String, Object?>{};
  _createEmptyState(agent, nonInitialized);
  for (final String key in initializedStates?.keys ?? const <String>[]) {
    nonInitialized.remove(key);
  }
  return nonInitialized;
}
