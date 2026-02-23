import '../../agents/base_agent.dart';
import '../../apps/app.dart';

typedef AgentOrApp = Object;

abstract class BaseAgentLoader {
  AgentOrApp loadAgent(String agentName);

  List<String> listAgents();

  List<Map<String, Object?>> listAgentsDetailed() {
    return listAgents()
        .map(
          (String name) => <String, Object?>{
            'name': name,
            'display_name': null,
            'description': null,
            'type': null,
          },
        )
        .toList(growable: false);
  }
}

BaseAgent asBaseAgent(AgentOrApp value) {
  if (value is App) {
    return value.rootAgent;
  }
  if (value is BaseAgent) {
    return value;
  }
  throw ArgumentError('Loaded object is neither App nor BaseAgent.');
}
