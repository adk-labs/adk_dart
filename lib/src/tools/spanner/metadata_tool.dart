import 'dart:convert';

import 'client.dart';

Future<Map<String, Object?>> listTableNames({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required Object credentials,
  String namedSchema = '',
}) async {
  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    final String schema = namedSchema.isEmpty ? '_default' : namedSchema;
    final List<String> tables = database
        .listTables(schema: schema)
        .map((SpannerTable table) => table.tableId)
        .toList(growable: false);

    return <String, Object?>{'status': 'SUCCESS', 'results': tables};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> getTableSchema({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String tableName,
  required Object credentials,
  String namedSchema = '',
}) async {
  const String columnsQuery = '''
      SELECT
          COLUMN_NAME,
          TABLE_SCHEMA,
          SPANNER_TYPE,
          ORDINAL_POSITION,
          COLUMN_DEFAULT,
          IS_NULLABLE,
          IS_GENERATED,
          GENERATION_EXPRESSION,
          IS_STORED
      FROM
          INFORMATION_SCHEMA.COLUMNS
      WHERE
          TABLE_NAME = @table_name
          AND TABLE_SCHEMA = @named_schema
      ORDER BY
          ORDINAL_POSITION
  ''';

  const String keyColumnUsageQuery = '''
      SELECT
          COLUMN_NAME,
          CONSTRAINT_NAME,
          ORDINAL_POSITION,
          POSITION_IN_UNIQUE_CONSTRAINT
      FROM
          INFORMATION_SCHEMA.KEY_COLUMN_USAGE
      WHERE
          TABLE_NAME = @table_name
          AND TABLE_SCHEMA = @named_schema
  ''';

  const String tableMetadataQuery = '''
      SELECT
          TABLE_SCHEMA,
          TABLE_NAME,
          TABLE_TYPE,
          PARENT_TABLE_NAME,
          ON_DELETE_ACTION,
          SPANNER_STATE,
          INTERLEAVE_TYPE,
          ROW_DELETION_POLICY_EXPRESSION
      FROM
          INFORMATION_SCHEMA.TABLES
      WHERE
          TABLE_NAME = @table_name
          AND TABLE_SCHEMA = @named_schema;
  ''';

  final Map<String, Object?> params = <String, Object?>{
    'table_name': tableName,
    'named_schema': namedSchema,
  };
  const Map<String, Object?> paramTypes = <String, Object?>{
    'table_name': 'STRING',
    'named_schema': 'STRING',
  };

  final Map<String, Object?> results = <String, Object?>{
    'schema': <String, Object?>{},
    'metadata': <Object?>[],
  };

  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    if (database.databaseDialect == SpannerDatabaseDialect.postgresql) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'PostgreSQL dialect is not supported',
      };
    }

    final SpannerSnapshot snapshot = database.snapshot(multiUse: true);
    final Map<String, Object?> schema =
        (results['schema'] as Map<String, Object?>);

    final SpannerResultSet columnsResultSet = snapshot.executeSql(
      sql: columnsQuery,
      params: params,
      paramTypes: paramTypes,
    );
    for (final Object? row in columnsResultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.length < 9) {
        continue;
      }
      final String columnName = '${values[0]}';
      schema[columnName] = <String, Object?>{
        'SPANNER_TYPE': values[2],
        'TABLE_SCHEMA': values[1],
        'ORDINAL_POSITION': values[3],
        'COLUMN_DEFAULT': values[4],
        'IS_NULLABLE': values[5],
        'IS_GENERATED': values[6],
        'GENERATION_EXPRESSION': values[7],
        'IS_STORED': values[8],
      };
    }

    final SpannerResultSet keyResultSet = snapshot.executeSql(
      sql: keyColumnUsageQuery,
      params: params,
      paramTypes: paramTypes,
    );
    for (final Object? row in keyResultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.length < 4) {
        continue;
      }
      final String columnName = '${values[0]}';
      final Object? columnMetadata = schema[columnName];
      if (columnMetadata is! Map<String, Object?>) {
        continue;
      }
      final List<Object?> keyColumnUsage =
          (columnMetadata['KEY_COLUMN_USAGE'] as List<Object?>?) ?? <Object?>[];
      keyColumnUsage.add(<String, Object?>{
        'CONSTRAINT_NAME': values[1],
        'ORDINAL_POSITION': values[2],
        'POSITION_IN_UNIQUE_CONSTRAINT': values[3],
      });
      columnMetadata['KEY_COLUMN_USAGE'] = keyColumnUsage;
    }

    final List<Object?> metadata = (results['metadata'] as List<Object?>);
    final SpannerResultSet metadataResultSet = snapshot.executeSql(
      sql: tableMetadataQuery,
      params: params,
      paramTypes: paramTypes,
    );
    for (final Object? row in metadataResultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.length < 8) {
        continue;
      }
      metadata.add(<String, Object?>{
        'TABLE_SCHEMA': values[0],
        'TABLE_NAME': values[1],
        'TABLE_TYPE': values[2],
        'PARENT_TABLE_NAME': values[3],
        'ON_DELETE_ACTION': values[4],
        'SPANNER_STATE': values[5],
        'INTERLEAVE_TYPE': values[6],
        'ROW_DELETION_POLICY_EXPRESSION': values[7],
      });
    }

    final Object? serializableResults = _ensureJsonEncodable(results);
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': serializableResults,
    };
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> listTableIndexes({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String tableId,
  required Object credentials,
}) async {
  const String sqlQuery =
      'SELECT INDEX_NAME, TABLE_SCHEMA, INDEX_TYPE, '
      'PARENT_TABLE_NAME, IS_UNIQUE, IS_NULL_FILTERED, INDEX_STATE '
      'FROM INFORMATION_SCHEMA.INDEXES '
      'WHERE TABLE_NAME = @table_id ';

  final Map<String, Object?> params = <String, Object?>{'table_id': tableId};
  const Map<String, Object?> paramTypes = <String, Object?>{
    'table_id': 'STRING',
  };

  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    if (database.databaseDialect == SpannerDatabaseDialect.postgresql) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'PostgreSQL dialect is not supported.',
      };
    }

    final List<Object?> indexes = <Object?>[];
    final SpannerSnapshot snapshot = database.snapshot();
    final SpannerResultSet resultSet = snapshot.executeSql(
      sql: sqlQuery,
      params: params,
      paramTypes: paramTypes,
    );

    for (final Object? row in resultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.length < 7) {
        continue;
      }
      final Map<String, Object?> indexInfo = <String, Object?>{
        'INDEX_NAME': values[0],
        'TABLE_SCHEMA': values[1],
        'INDEX_TYPE': values[2],
        'PARENT_TABLE_NAME': values[3],
        'IS_UNIQUE': values[4],
        'IS_NULL_FILTERED': values[5],
        'INDEX_STATE': values[6],
      };
      indexes.add(_ensureJsonEncodable(indexInfo));
    }

    return <String, Object?>{'status': 'SUCCESS', 'results': indexes};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> listTableIndexColumns({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required String tableId,
  required Object credentials,
}) async {
  const String sqlQuery =
      'SELECT INDEX_NAME, TABLE_SCHEMA, COLUMN_NAME, '
      'ORDINAL_POSITION, IS_NULLABLE, SPANNER_TYPE '
      'FROM INFORMATION_SCHEMA.INDEX_COLUMNS '
      'WHERE TABLE_NAME = @table_id ';

  final Map<String, Object?> params = <String, Object?>{'table_id': tableId};
  const Map<String, Object?> paramTypes = <String, Object?>{
    'table_id': 'STRING',
  };

  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    if (database.databaseDialect == SpannerDatabaseDialect.postgresql) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'PostgreSQL dialect is not supported.',
      };
    }

    final List<Object?> indexColumns = <Object?>[];
    final SpannerSnapshot snapshot = database.snapshot();
    final SpannerResultSet resultSet = snapshot.executeSql(
      sql: sqlQuery,
      params: params,
      paramTypes: paramTypes,
    );

    for (final Object? row in resultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.length < 6) {
        continue;
      }
      final Map<String, Object?> indexColumnInfo = <String, Object?>{
        'INDEX_NAME': values[0],
        'TABLE_SCHEMA': values[1],
        'COLUMN_NAME': values[2],
        'ORDINAL_POSITION': values[3],
        'IS_NULLABLE': values[4],
        'SPANNER_TYPE': values[5],
      };
      indexColumns.add(_ensureJsonEncodable(indexColumnInfo));
    }

    return <String, Object?>{'status': 'SUCCESS', 'results': indexColumns};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

Future<Map<String, Object?>> listNamedSchemas({
  required String projectId,
  required String instanceId,
  required String databaseId,
  required Object credentials,
}) async {
  const String sqlQuery = '''
    SELECT
        SCHEMA_NAME
    FROM
        INFORMATION_SCHEMA.SCHEMATA
    WHERE
        SCHEMA_NAME NOT IN ('', 'INFORMATION_SCHEMA', 'SPANNER_SYS');
    ''';

  try {
    final SpannerClient spannerClient = getSpannerClient(
      project: projectId,
      credentials: credentials,
    );
    final SpannerInstance instance = spannerClient.instance(instanceId);
    final SpannerDatabase database = instance.database(databaseId);

    if (database.databaseDialect == SpannerDatabaseDialect.postgresql) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'PostgreSQL dialect is not supported.',
      };
    }

    final List<String> namedSchemas = <String>[];
    final SpannerSnapshot snapshot = database.snapshot();
    final SpannerResultSet resultSet = snapshot.executeSql(sql: sqlQuery);
    for (final Object? row in resultSet.rows) {
      final List<Object?> values = _asRow(row);
      if (values.isEmpty) {
        continue;
      }
      namedSchemas.add('${values[0]}');
    }

    return <String, Object?>{'status': 'SUCCESS', 'results': namedSchemas};
  } catch (error) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$error'};
  }
}

List<Object?> _asRow(Object? row) {
  if (row is List) {
    return row.cast<Object?>();
  }
  if (row is Iterable) {
    return row.cast<Object?>().toList(growable: false);
  }
  if (row is Map) {
    return row.values.cast<Object?>().toList(growable: false);
  }
  return <Object?>[row];
}

Object? _ensureJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return value;
  } catch (_) {
    return '$value';
  }
}
