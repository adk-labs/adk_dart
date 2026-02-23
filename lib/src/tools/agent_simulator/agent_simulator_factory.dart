import '../../tools/base_tool.dart';
import 'agent_simulator_config.dart';
import 'agent_simulator_engine.dart';
import 'agent_simulator_plugin.dart';

typedef AgentSimulatorCallback =
    Future<Map<String, Object?>?> Function(
      BaseTool tool,
      Map<String, Object?> args,
      Object toolContext,
    );

class AgentSimulatorFactory {
  const AgentSimulatorFactory._();

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

  static AgentSimulatorPlugin createPlugin(AgentSimulatorConfig config) {
    final AgentSimulatorEngine simulatorEngine = AgentSimulatorEngine(config);
    return AgentSimulatorPlugin(simulatorEngine);
  }
}
