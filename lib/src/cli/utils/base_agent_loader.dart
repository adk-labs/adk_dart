import '../../agents/base_agent.dart';
import '../../apps/app.dart';

/// Union type used by loaders that can return either an [App] or [BaseAgent].
typedef AgentOrApp = Object;

/// Loads root agents and app metadata from an agents directory.
abstract class BaseAgentLoader {
  /// Loads a single agent or app identified by [agentName].
  AgentOrApp loadAgent(String agentName);

  /// All available agent names under this loader's root.
  List<String> listAgents();

  /// Rich agent metadata for UI listing endpoints.
  ///
  /// Subclasses can override this to include extra fields.
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

/// Converts [value] to a [BaseAgent].
///
/// Returns `value.rootAgent` when [value] is an [App].
///
/// Throws an [ArgumentError] when [value] is neither [App] nor [BaseAgent].
BaseAgent asBaseAgent(AgentOrApp value) {
  if (value is App) {
    return value.rootAgent;
  }
  if (value is BaseAgent) {
    return value;
  }
  throw ArgumentError('Loaded object is neither App nor BaseAgent.');
}
