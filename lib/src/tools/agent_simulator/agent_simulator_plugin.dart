import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import 'agent_simulator_engine.dart';

class AgentSimulatorPlugin extends BasePlugin {
  AgentSimulatorPlugin(this._simulatorEngine) : super(name: 'AgentSimulator');

  final AgentSimulatorEngine _simulatorEngine;

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    final Map<String, Object?>? simulated = await _simulatorEngine.simulate(
      tool,
      Map<String, Object?>.from(toolArgs),
      toolContext,
    );
    if (simulated == null) {
      return null;
    }
    return Map<String, dynamic>.from(simulated);
  }
}
