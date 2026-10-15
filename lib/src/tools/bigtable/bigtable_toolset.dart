/// Bigtable toolset assembly and configuration helpers.
library;

import '../../agents/readonly_context.dart';
import '../../features/_feature_registry.dart';
import '../../models/llm_request.dart';
import '../base_tool.dart';
import '../base_toolset.dart';
import '../google_tool.dart';
import '../tool_context.dart';
import 'bigtable_credentials.dart';
import 'metadata_tool.dart' as metadata_tool;
import 'query_tool.dart' as query_tool;
import 'settings.dart';

/// Default name prefix assigned to Bigtable tools.
const String defaultBigtableToolNamePrefix = 'bigtable';

/// Tool that executes SQL queries against parameterized Bigtable logical views.
class BigtableParameterizedViewTool extends GoogleTool {
  /// Creates a parameterized view SQL execution tool for [viewParameterNames].
  BigtableParameterizedViewTool({
    required List<String> viewParameterNames,
    super.credentialsConfig,
    super.toolSettings,
  }) : viewParameterNames = List<String>.unmodifiable(viewParameterNames),
       super(
         func: query_tool.executeSql,
         name: 'execute_sql_parameterized',
       );

  /// Parameter names required by the target Bigtable logical view.
  final List<String> viewParameterNames;

  @override
  FunctionDeclaration? getDeclaration() {
    final Map<String, Object?> viewProperties = <String, Object?>{
      for (final String paramName in viewParameterNames)
        paramName: <String, Object?>{'type': 'string'},
    };
    return FunctionDeclaration(
      name: name,
      description: description.isEmpty
          ? 'Executes a SQL query against a parameterized Bigtable logical view.'
          : description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'project_id': <String, Object?>{'type': 'string'},
          'instance_id': <String, Object?>{'type': 'string'},
          'query': <String, Object?>{'type': 'string'},
          'view_parameters': <String, Object?>{
            'type': 'object',
            'properties': viewProperties,
            'required': List<String>.from(viewParameterNames),
          },
        },
        'required': <String>[
          'project_id',
          'instance_id',
          'query',
          'view_parameters',
        ],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    final Map<String, dynamic> normalizedArgs = Map<String, dynamic>.from(args);
    if (normalizedArgs.containsKey('project_id') &&
        !normalizedArgs.containsKey('projectId')) {
      normalizedArgs['projectId'] = normalizedArgs.remove('project_id');
    }
    if (normalizedArgs.containsKey('instance_id') &&
        !normalizedArgs.containsKey('instanceId')) {
      normalizedArgs['instanceId'] = normalizedArgs.remove('instance_id');
    }
    final Object? rawViewParams =
        normalizedArgs.remove('view_parameters') ??
        normalizedArgs['viewParameters'];
    if (rawViewParams is Map) {
      normalizedArgs['viewParameters'] = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in rawViewParams.entries)
          '${entry.key}': entry.value,
      };
    }
    return super.run(args: normalizedArgs, toolContext: toolContext);
  }
}

/// Toolset that exposes Bigtable operations as ADK tools.
class BigtableToolset extends BaseToolset {
  /// Creates a Bigtable toolset with optional credential and tool settings.
  BigtableToolset({
    super.toolFilter,
    BigtableCredentialsConfig? credentialsConfig,
    BigtableToolSettings? bigtableToolSettings,
    List<String>? viewParameterNames,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = bigtableToolSettings ?? BigtableToolSettings(),
       viewParameterNames = viewParameterNames == null
           ? null
           : List<String>.unmodifiable(viewParameterNames),
       super(toolNamePrefix: defaultBigtableToolNamePrefix);

  final BigtableCredentialsConfig? _credentialsConfig;
  final BigtableToolSettings _toolSettings;

  /// Optional parameter names for parameterized Bigtable logical views.
  ///
  /// When non-empty, `execute_sql_parameterized` is exposed in place of the
  /// generic `execute_sql` tool.
  final List<String>? viewParameterNames;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.bigtableToolset);

    final bool hasViewParameters =
        viewParameterNames != null && viewParameterNames!.isNotEmpty;

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
      if (hasViewParameters)
        BigtableParameterizedViewTool(
          viewParameterNames: viewParameterNames!,
          credentialsConfig: _credentialsConfig,
          toolSettings: _toolSettings,
        )
      else
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
