import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'config.dart';
import 'credentials.dart';
import 'data_agent_tool.dart' as data_agent_tool;

class DataAgentToolset extends BaseToolset {
  DataAgentToolset({
    super.toolFilter,
    DataAgentCredentialsConfig? credentialsConfig,
    DataAgentToolConfig? dataAgentToolConfig,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = dataAgentToolConfig ?? DataAgentToolConfig();

  final DataAgentCredentialsConfig? _credentialsConfig;
  final DataAgentToolConfig _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.dataAgentToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: data_agent_tool.listAccessibleDataAgents,
        name: 'list_accessible_data_agents',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: data_agent_tool.getDataAgentInfo,
        name: 'get_data_agent_info',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: data_agent_tool.askDataAgent,
        name: 'ask_data_agent',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList();
  }

  @override
  Future<void> close() async {}
}
