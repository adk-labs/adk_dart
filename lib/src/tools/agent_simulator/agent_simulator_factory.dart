import '../../tools/base_tool.dart';
import 'agent_simulator_config.dart';
import 'agent_simulator_engine.dart';
import 'agent_simulator_plugin.dart';

/// Callback signature used to simulate one tool invocation.
typedef AgentSimulatorCallback =
    Future<Map<String, Object?>?> Function(
      BaseTool tool,
      Map<String, Object?> args,
      Object toolContext,
    );

/// Factory utilities that wire simulator callbacks and plugins.
class AgentSimulatorFactory {
  /// Creates an [AgentSimulatorFactory] utility namespace.
  const AgentSimulatorFactory._();

  /// Creates a callback that simulates tools using [config].
  static AgentSimulatorCallback createCallback(AgentSimulatorConfig config) {
    final AgentSimulatorEngine simulatorEngine = AgentSimulatorEngine(config);
    return (
      BaseTool tool,
      Map<String, Object?> args,
      Object toolContext,
    ) async {
      return simulatorEngine.simulate(tool, args, toolContext);
    };
  }

  /// Creates a plugin that intercepts tool calls and simulates responses.
  static AgentSimulatorPlugin createPlugin(AgentSimulatorConfig config) {
    final AgentSimulatorEngine simulatorEngine = AgentSimulatorEngine(config);
    return AgentSimulatorPlugin(simulatorEngine);
  }
}
