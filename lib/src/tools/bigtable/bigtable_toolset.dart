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
  /// Creates a parameterized view SQL execution tool for [viewParameterNames]
  /// or [viewParameters].
  BigtableParameterizedViewTool({
    List<String>? viewParameterNames,
    Map<String, Object?>? viewParameters,
    super.credentialsConfig,
    super.toolSettings,
  }) : viewParameterNames = viewParameterNames == null
           ? const <String>[]
           : List<String>.unmodifiable(viewParameterNames),
       viewParameters = viewParameters == null
           ? null
           : Map<String, Object?>.unmodifiable(viewParameters),
       super(
         func: query_tool.executeSql,
         name: 'execute_sql_parameterized',
       ) {
    if (this.viewParameterNames.isNotEmpty && this.viewParameters != null) {
      throw ArgumentError(
        'Cannot specify both viewParameterNames and viewParameters.',
      );
    }
  }

  /// Parameter names resolved from trusted [ToolContext] attributes.
  final List<String> viewParameterNames;

  /// Explicit view parameter values injected into parameterized view queries.
  final Map<String, Object?>? viewParameters;

  @override
  FunctionDeclaration? getDeclaration() {
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
        },
        'required': <String>[
          'project_id',
          'instance_id',
          'query',
        ],
      },
    );
  }

  static String? _resolveContextAttribute(
    ToolContext toolContext,
    String paramName,
  ) {
    switch (paramName) {
      case 'user_id':
      case 'userId':
        return toolContext.userId;
      case 'app_name':
      case 'appName':
        return toolContext.session.appName;
      case 'session_id':
      case 'sessionId':
        return toolContext.session.id;
      case 'invocation_id':
      case 'invocationId':
        return toolContext.invocationId;
      case 'agent_name':
      case 'agentName':
        return toolContext.agentName;
      default:
        throw ArgumentError(
          'Unsupported view parameter name "$paramName". Only trusted '
          'ToolContext attributes are supported; pass custom parameters via '
          'viewParameters.',
        );
    }
  }

  Future<Map<String, Object?>> _resolveViewParameters(
    ToolContext toolContext,
  ) async {
    final Map<String, Object?> resolved = <String, Object?>{};
    for (final String paramName in viewParameterNames) {
      final String? value = _resolveContextAttribute(toolContext, paramName);
      if (value == null || value.isEmpty) {
        throw ArgumentError(
          'Missing value for view parameter "$paramName" on ToolContext.',
        );
      }
      resolved[paramName] = value;
    }

    if (viewParameters != null) {
      for (final MapEntry<String, Object?> entry in viewParameters!.entries) {
        Object? value = entry.value;
        if (value is Function) {
          value = Function.apply(value, <Object?>[toolContext]);
          if (value is Future) {
            value = await value;
          }
        }
        if (value != null) {
          resolved[entry.key] = value;
        } else {
          resolved.remove(entry.key);
        }
      }
    }

    return resolved;
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final Map<String, dynamic> normalizedArgs = Map<String, dynamic>.from(args);
    if (normalizedArgs.containsKey('project_id') &&
        !normalizedArgs.containsKey('projectId')) {
      normalizedArgs['projectId'] = normalizedArgs.remove('project_id');
    }
    if (normalizedArgs.containsKey('instance_id') &&
        !normalizedArgs.containsKey('instanceId')) {
      normalizedArgs['instanceId'] = normalizedArgs.remove('instance_id');
    }
    normalizedArgs.remove('view_parameters');
    normalizedArgs.remove('viewParameters');
    if (viewParameterNames.isNotEmpty || viewParameters != null) {
      normalizedArgs['viewParameters'] = await _resolveViewParameters(
        toolContext,
      );
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
    Map<String, Object?>? viewParameters,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = bigtableToolSettings ?? BigtableToolSettings(),
       viewParameterNames = viewParameterNames == null
           ? null
           : List<String>.unmodifiable(viewParameterNames),
       viewParameters = viewParameters == null
           ? null
           : Map<String, Object?>.unmodifiable(viewParameters),
       super(toolNamePrefix: defaultBigtableToolNamePrefix) {
    if (this.viewParameterNames != null &&
        this.viewParameterNames!.isNotEmpty &&
        this.viewParameters != null) {
      throw ArgumentError(
        'Cannot specify both viewParameterNames and viewParameters.',
      );
    }
  }

  final BigtableCredentialsConfig? _credentialsConfig;
  final BigtableToolSettings _toolSettings;

  /// Optional parameter names for parameterized Bigtable logical views.
  ///
  /// When non-empty, `execute_sql_parameterized` is exposed in place of the
  /// generic `execute_sql` tool.
  final List<String>? viewParameterNames;

  /// Optional explicit parameter values for parameterized Bigtable logical views.
  ///
  /// When non-empty, `execute_sql_parameterized` is exposed in place of the
  /// generic `execute_sql` tool.
  final Map<String, Object?>? viewParameters;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    isFeatureEnabled(FeatureName.bigtableToolset);

    final bool hasViewParameters =
        (viewParameterNames != null && viewParameterNames!.isNotEmpty) ||
        (viewParameters != null && viewParameters!.isNotEmpty);

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
          viewParameterNames: viewParameterNames,
          viewParameters: viewParameters,
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
