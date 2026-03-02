import '../tool_context.dart';
import 'settings.dart';
import 'utils.dart' as utils;

/// Executes a SQL query against Spanner using normalized tool [settings].
///
/// Returns a status map from `utils.executeSql`, including query results or
/// structured error details.
Future<Map<String, Object?>> executeSql({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String query,
  required Object credentials,
  required Object settings,
  ToolContext? toolContext,
}) async {
  return utils.executeSql(
    projectId: projectId,
    instanceId: instanceId,
    databaseId: databaseId,
    query: query,
    credentials: credentials,
    settings: SpannerToolSettings.fromObject(settings),
    toolContext: toolContext,
  );
}

/// Function signature for the Spanner `execute_sql` tool handler.
typedef ExecuteSqlTool =
    Future<Map<String, Object?>> Function({
      required String projectId,
      required String instanceId,
      required String databaseId,
      required String query,
      required Object credentials,
      required Object settings,
      ToolContext? toolContext,
    });

/// Returns an [ExecuteSqlTool] tailored to the configured [settings].
ExecuteSqlTool getExecuteSql(SpannerToolSettings settings) {
  if (settings.queryResultMode == QueryResultMode.dictList) {
    return ({
      required String projectId,
      required String instanceId,
      required String databaseId,
      required String query,
      required Object credentials,
      required Object settings,
      ToolContext? toolContext,
    }) {
      return executeSql(
        projectId: projectId,
        instanceId: instanceId,
        databaseId: databaseId,
        query: query,
        credentials: credentials,
        settings: settings,
        toolContext: toolContext,
      );
    };
  }

  return executeSql;
}
