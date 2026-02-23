import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import 'metadata_tool.dart' as metadata_tool;
import 'query_tool.dart' as query_tool;
import 'search_tool.dart' as search_tool;
import 'settings.dart';
import 'spanner_credentials.dart';

const String defaultSpannerToolNamePrefix = 'spanner';

class SpannerToolset extends BaseToolset {
  SpannerToolset({
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
    isFeatureEnabled(FeatureName.spannerToolset);

    final List<GoogleTool> allTools = <GoogleTool>[
      GoogleTool(
        func: metadata_tool.listTableNames,
        name: 'list_table_names',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.listTableIndexes,
        name: 'list_table_indexes',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.listTableIndexColumns,
        name: 'list_table_index_columns',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.listNamedSchemas,
        name: 'list_named_schemas',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
      GoogleTool(
        func: metadata_tool.getTableSchema,
        name: 'get_table_schema',
        credentialsConfig: _credentialsConfig,
        toolSettings: _toolSettings,
      ),
    ];

    if (_toolSettings.capabilities.contains(Capabilities.dataRead)) {
      allTools.add(
        GoogleTool(
          func: query_tool.getExecuteSql(_toolSettings),
          name: 'execute_sql',
          credentialsConfig: _credentialsConfig,
          toolSettings: _toolSettings,
        ),
      );
      allTools.add(
        GoogleTool(
          func: search_tool.similaritySearch,
          name: 'similarity_search',
          credentialsConfig: _credentialsConfig,
          toolSettings: _toolSettings,
        ),
      );
      if (_toolSettings.vectorStoreSettings != null) {
        allTools.add(
          GoogleTool(
            func: search_tool.vectorStoreSimilaritySearch,
            name: 'vector_store_similarity_search',
            credentialsConfig: _credentialsConfig,
            toolSettings: _toolSettings,
          ),
        );
      }
    }

    return allTools
        .where((GoogleTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}
