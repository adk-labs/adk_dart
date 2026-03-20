/// Factory compatibility layer for environment simulation.
library;

import '../../tools/base_tool.dart';
import '../agent_simulator/agent_simulator_factory.dart';
import 'environment_simulation_config.dart';
import 'environment_simulation_plugin.dart';

/// Callback signature used to simulate one tool invocation.
typedef EnvironmentSimulationCallback =
    Future<Map<String, Object?>?> Function(
      BaseTool tool,
      Map<String, Object?> args,
      Object toolContext,
    );

/// Factory helpers that delegate to the legacy simulator implementation.
class EnvironmentSimulationFactory {
  /// Creates an [EnvironmentSimulationFactory] utility namespace.
  const EnvironmentSimulationFactory._();

  /// Creates a callback that simulates tools using [config].
  static EnvironmentSimulationCallback createCallback(
    EnvironmentSimulationConfig config,
  ) {
    return AgentSimulatorFactory.createCallback(config);
  }

  /// Creates a plugin that intercepts tool calls and simulates responses.
  static EnvironmentSimulationPlugin createPlugin(
    EnvironmentSimulationConfig config,
  ) {
    return AgentSimulatorFactory.createPlugin(config);
  }
}
