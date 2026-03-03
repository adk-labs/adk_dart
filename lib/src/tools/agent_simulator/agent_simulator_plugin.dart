import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import 'agent_simulator_engine.dart';

/// Plugin that replaces tool calls with simulated outputs.
class AgentSimulatorPlugin extends BasePlugin {
  /// Creates a simulator plugin backed by [_simulatorEngine].
  AgentSimulatorPlugin(this._simulatorEngine) : super(name: 'AgentSimulator');

  final AgentSimulatorEngine _simulatorEngine;

  @override
  /// Attempts to simulate [tool] before the real tool call executes.
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
