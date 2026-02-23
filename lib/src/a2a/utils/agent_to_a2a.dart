import 'dart:convert';
import 'dart:io';

import '../../agents/base_agent.dart';
import '../../runners/runner.dart';
import '../executor/a2a_agent_executor.dart';
import '../protocol.dart';
import 'agent_card_builder.dart';

Future<AgentCard?> _loadAgentCard(Object? agentCard) async {
  if (agentCard == null) {
    return null;
  }

  if (agentCard is AgentCard) {
    return agentCard;
  }

  if (agentCard is String) {
    try {
      final String jsonText = await File(agentCard).readAsString();
      final Object? decoded = jsonDecode(jsonText);
      if (decoded is Map<String, Object?>) {
        return AgentCard.fromJson(decoded);
      }
      if (decoded is Map) {
        return AgentCard.fromJson(
          decoded.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          ),
        );
      }
      throw FormatException('Agent card JSON must decode to an object.');
    } catch (error) {
      throw ArgumentError('Failed to load agent card from $agentCard: $error');
    }
  }

  throw ArgumentError(
    'agentCard must be AgentCard, file path string, or null.',
  );
}

Future<A2aApplication> toA2a(
  BaseAgent agent, {
  String host = 'localhost',
  int port = 8000,
  String protocol = 'http',
  Object? agentCard,
  Runner? runner,
}) async {
  final Runner resolvedRunner =
      runner ?? InMemoryRunner(agent: agent, appName: agent.name);

  final AgentCardBuilder cardBuilder = AgentCardBuilder(
    agent: agent,
    rpcUrl: '$protocol://$host:$port/',
  );

  final AgentCard? provided = await _loadAgentCard(agentCard);
  final AgentCard finalCard = provided ?? await cardBuilder.build();

  final A2aAgentExecutor executor = A2aAgentExecutor(runner: resolvedRunner);

  return A2aApplication(
    agentCard: finalCard,
    executor: executor,
    taskStore: <String, A2aTask>{},
  );
}
