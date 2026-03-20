/// Toolset exposing experimental Spanner admin tools.
library;

import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'admin_tool.dart' as admin_tool;
import 'settings.dart';
import 'spanner_credentials.dart';
import 'spanner_toolset.dart';

/// Experimental toolset for Spanner admin operations.
class SpannerAdminToolset extends BaseToolset {
  /// Creates a Spanner admin toolset.
  SpannerAdminToolset({
    super.toolFilter,
    SpannerCredentialsConfig? credentialsConfig,
    SpannerToolSettings? spannerToolSettings,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = spannerToolSettings ?? SpannerToolSettings(),
       super(toolNamePrefix: defaultSpannerToolNamePrefix);

  final SpannerCredentialsConfig? _credentialsConfig;
  final SpannerToolSettings _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.spannerAdminToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: admin_tool.listInstances,
        name: 'list_instances',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.getInstance,
        name: 'get_instance',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.createDatabase,
        name: 'create_database',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.listDatabases,
        name: 'list_databases',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.createInstance,
        name: 'create_instance',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.listInstanceConfigs,
        name: 'list_instance_configs',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: admin_tool.getInstanceConfig,
        name: 'get_instance_config',
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
