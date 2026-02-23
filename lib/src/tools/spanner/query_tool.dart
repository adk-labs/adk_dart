import '../tool_context.dart';
import 'settings.dart';
import 'utils.dart' as utils;

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
