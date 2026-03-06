/// Bigtable toolset assembly and configuration helpers.
library;

import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'bigtable_credentials.dart';
import 'metadata_tool.dart' as metadata_tool;
import 'query_tool.dart' as query_tool;
import 'settings.dart';

/// Default name prefix assigned to Bigtable tools.
const String defaultBigtableToolNamePrefix = 'bigtable';

/// Toolset that exposes Bigtable operations as ADK tools.
class BigtableToolset extends BaseToolset {
  /// Creates a Bigtable toolset with optional credential and tool settings.
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
        func: metadata_tool.listClusters,
        name: 'list_clusters',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.getClusterInfo,
        name: 'get_cluster_info',
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
