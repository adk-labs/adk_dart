import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'bigtable_credentials.dart';
import 'metadata_tool.dart' as metadata_tool;
import 'query_tool.dart' as query_tool;
import 'settings.dart';

const String defaultBigtableToolNamePrefix = 'bigtable';

class BigtableToolset extends BaseToolset {
  BigtableToolset({
    super.toolFilter,
    BigtableCredentialsConfig? credentialsConfig,
    BigtableToolSettings? bigtableToolSettings,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = bigtableToolSettings ?? BigtableToolSettings(),
       super(toolNamePrefix: defaultBigtableToolNamePrefix);

  final BigtableCredentialsConfig? _credentialsConfig;
  final BigtableToolSettings _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.bigtableToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: metadata_tool.listInstances,
        name: 'list_instances',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.getInstanceInfo,
        name: 'get_instance_info',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.listTables,
        name: 'list_tables',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.getTableInfo,
        name: 'get_table_info',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: query_tool.executeSql,
        name: 'execute_sql',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}
