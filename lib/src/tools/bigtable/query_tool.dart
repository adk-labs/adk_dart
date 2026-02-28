import 'dart:convert';

import '../tool_context.dart';
import 'client.dart';
import 'settings.dart';

const int defaultMaxExecutedQueryResultRows = 50;

Future<Map<String, Object?>> executeSql({
  required String projectId,
  required String instanceId,
  required String query,
  required Object credentials,
  required Object settings,
  ToolContext? toolContext,
  Map<String, Object?>? parameters,
  Map<String, Object?>? parameterTypes,
}) async {
  // Present for parity with Python signature; not used in current implementation.
  toolContext;

  try {
    final BigtableDataClient btClient = getBigtableDataClient(
      project: projectId,
      credentials: credentials,
    );
    final BigtableQueryIterator queryIterator = btClient.executeQuery(
      query: query,
      instanceId: instanceId,
      parameters: parameters,
      parameterTypes: parameterTypes,
    );

    final BigtableToolSettings toolSettings = BigtableToolSettings.fromObject(
      settings,
    );
    final int maxRows = toolSettings.maxQueryResultRows > 0
        ? toolSettings.maxQueryResultRows
        : defaultMaxExecutedQueryResultRows;

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    int counter = maxRows;
    bool truncated = false;

    try {
      for (final BigtableQueryRow row in queryIterator) {
        if (counter <= 0) {
          truncated = true;
          break;
        }

        final Map<String, Object?> rowValues = <String, Object?>{};
        for (final MapEntry<String, Object?> entry in row.fields.entries) {
          rowValues[entry.key] = _ensureJsonEncodable(entry.value);
        }
        rows.add(rowValues);
        counter -= 1;
      }
    } finally {
      queryIterator.close();
    }

    final Map<String, Object?> result = <String, Object?>{
      'status': 'SUCCESS',
      'rows': rows,
    };
    if (truncated) {
      result['result_is_likely_truncated'] = true;
    }
    return result;
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Object? _ensureJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}
