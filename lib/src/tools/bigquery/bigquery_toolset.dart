import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'bigquery_credentials.dart';
import 'config.dart';
import 'data_insights_tool.dart' as data_insights_tool;
import 'metadata_tool.dart' as metadata_tool;
import 'query_tool.dart' as query_tool;

class BigQueryToolset extends BaseToolset {
  BigQueryToolset({
    super.toolFilter,
    BigQueryCredentialsConfig? credentialsConfig,
    BigQueryToolConfig? bigqueryToolConfig,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = bigqueryToolConfig ?? BigQueryToolConfig();

  final BigQueryCredentialsConfig? _credentialsConfig;
  final BigQueryToolConfig _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.bigQueryToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: metadata_tool.getDatasetInfo,
        name: 'get_dataset_info',
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
        func: metadata_tool.listDatasetIds,
        name: 'list_dataset_ids',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.listTableIds,
        name: 'list_table_ids',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.getJobInfo,
        name: 'get_job_info',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: query_tool.getExecuteSql(_toolSettings),
        name: 'execute_sql',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: query_tool.forecast,
        name: 'forecast',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: query_tool.analyzeContribution,
        name: 'analyze_contribution',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: query_tool.detectAnomalies,
        name: 'detect_anomalies',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: data_insights_tool.askDataInsights,
        name: 'ask_data_insights',
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
