import '../../features/_feature_registry.dart';

const String exactNearestNeighbors = 'EXACT_NEAREST_NEIGHBORS';
const String approximateNearestNeighbors = 'APPROXIMATE_NEAREST_NEIGHBORS';

enum Capabilities {
  dataRead('data_read');

  const Capabilities(this.value);

  final String value;

  static Capabilities fromValue(String value) {
    for (final Capabilities capability in Capabilities.values) {
      if (capability.value == value) {
        return capability;
      }
    }
    throw ArgumentError('Unknown Spanner capability: $value');
  }
}

enum QueryResultMode {
  defaultMode('default'),
  dictList('dict_list');

  const QueryResultMode(this.value);

  final String value;

  static QueryResultMode fromValue(String value) {
    for (final QueryResultMode mode in QueryResultMode.values) {
      if (mode.value == value) {
        return mode;
      }
    }
    throw ArgumentError('Unknown query result mode: $value');
  }
}

class TableColumn {
  TableColumn({required this.name, required this.type, this.isNullable = true});

  final String name;
  final String type;
  final bool isNullable;

  factory TableColumn.fromJson(Map<String, Object?> json) {
    final String name = _readRequiredString(json, const <String>['name']);
    final String type = _readRequiredString(json, const <String>['type']);
    final bool isNullable =
        _readBool(json, const <String>['is_nullable', 'isNullable']) ?? true;
    return TableColumn(name: name, type: type, isNullable: isNullable);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'type': type,
      'is_nullable': isNullable,
    };
  }

  static TableColumn fromObject(Object? value) {
    if (value is TableColumn) {
      return value;
    }
    if (value is Map) {
      return TableColumn.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    throw ArgumentError('Invalid TableColumn value: $value');
  }
}

class VectorSearchIndexSettings {
  VectorSearchIndexSettings({
    required this.indexName,
    this.additionalKeyColumns,
    this.additionalStoringColumns,
    this.treeDepth = 2,
    this.numLeaves = 1000,
    this.numBranches,
  });

  final String indexName;
  final List<String>? additionalKeyColumns;
  final List<String>? additionalStoringColumns;
  final int treeDepth;
  final int numLeaves;
  final int? numBranches;

  factory VectorSearchIndexSettings.fromJson(Map<String, Object?> json) {
    final String indexName = _readRequiredString(json, const <String>[
      'index_name',
      'indexName',
    ]);

    return VectorSearchIndexSettings(
      indexName: indexName,
      additionalKeyColumns: _readStringList(json, const <String>[
        'additional_key_columns',
        'additionalKeyColumns',
      ]),
      additionalStoringColumns: _readStringList(json, const <String>[
        'additional_storing_columns',
        'additionalStoringColumns',
      ]),
      treeDepth: _readInt(json, const <String>['tree_depth', 'treeDepth']) ?? 2,
      numLeaves:
          _readInt(json, const <String>['num_leaves', 'numLeaves']) ?? 1000,
      numBranches: _readInt(json, const <String>[
        'num_branches',
        'numBranches',
      ]),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index_name': indexName,
      if (additionalKeyColumns != null)
        'additional_key_columns': List<String>.from(additionalKeyColumns!),
      if (additionalStoringColumns != null)
        'additional_storing_columns': List<String>.from(
          additionalStoringColumns!,
        ),
      'tree_depth': treeDepth,
      'num_leaves': numLeaves,
      if (numBranches != null) 'num_branches': numBranches,
    };
  }

  static VectorSearchIndexSettings fromObject(Object? value) {
    if (value is VectorSearchIndexSettings) {
      return value;
    }
    if (value is Map) {
      return VectorSearchIndexSettings.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    throw ArgumentError('Invalid VectorSearchIndexSettings value: $value');
  }
}

class SpannerVectorStoreSettings {
  SpannerVectorStoreSettings({
    required this.projectId,
    required this.instanceId,
    required this.databaseId,
    required this.tableName,
    required this.contentColumn,
    required this.embeddingColumn,
    required this.vectorLength,
    required this.vertexAiEmbeddingModelName,
    List<String>? selectedColumns,
    this.nearestNeighborsAlgorithm = exactNearestNeighbors,
    this.topK = 4,
    this.distanceType = 'COSINE',
    this.numLeavesToSearch,
    this.additionalFilter,
    this.vectorSearchIndexSettings,
    List<TableColumn>? additionalColumnsToSetup,
    List<String>? primaryKeyColumns,
  }) : selectedColumns = _normalizeSelectedColumns(
         selectedColumns: selectedColumns,
         contentColumn: contentColumn,
       ),
       additionalColumnsToSetup = additionalColumnsToSetup == null
           ? null
           : List<TableColumn>.from(additionalColumnsToSetup),
       primaryKeyColumns = primaryKeyColumns == null
           ? null
           : List<String>.from(primaryKeyColumns) {
    if (vectorLength <= 0) {
      throw ArgumentError(
        'Invalid vector length in the Spanner vector store settings.',
      );
    }

    if (this.primaryKeyColumns != null) {
      final Set<String> columns = <String>{contentColumn, embeddingColumn};
      if (this.additionalColumnsToSetup != null) {
        columns.addAll(
          this.additionalColumnsToSetup!.map(
            (TableColumn column) => column.name,
          ),
        );
      }
      for (final String keyColumn in this.primaryKeyColumns!) {
        if (!columns.contains(keyColumn)) {
          throw ArgumentError(
            "Primary key column '$keyColumn' not found in column definitions.",
          );
        }
      }
    }
  }

  final String projectId;
  final String instanceId;
  final String databaseId;
  final String tableName;
  final String contentColumn;
  final String embeddingColumn;
  final int vectorLength;
  final String vertexAiEmbeddingModelName;
  final List<String> selectedColumns;
  final String nearestNeighborsAlgorithm;
  final int topK;
  final String distanceType;
  final int? numLeavesToSearch;
  final String? additionalFilter;
  final VectorSearchIndexSettings? vectorSearchIndexSettings;
  final List<TableColumn>? additionalColumnsToSetup;
  final List<String>? primaryKeyColumns;

  factory SpannerVectorStoreSettings.fromJson(Map<String, Object?> json) {
    return SpannerVectorStoreSettings(
      projectId: _readRequiredString(json, const <String>[
        'project_id',
        'projectId',
      ]),
      instanceId: _readRequiredString(json, const <String>[
        'instance_id',
        'instanceId',
      ]),
      databaseId: _readRequiredString(json, const <String>[
        'database_id',
        'databaseId',
      ]),
      tableName: _readRequiredString(json, const <String>[
        'table_name',
        'tableName',
      ]),
      contentColumn: _readRequiredString(json, const <String>[
        'content_column',
        'contentColumn',
      ]),
      embeddingColumn: _readRequiredString(json, const <String>[
        'embedding_column',
        'embeddingColumn',
      ]),
      vectorLength: _readRequiredInt(json, const <String>[
        'vector_length',
        'vectorLength',
      ]),
      vertexAiEmbeddingModelName: _readRequiredString(json, const <String>[
        'vertex_ai_embedding_model_name',
        'vertexAiEmbeddingModelName',
      ]),
      selectedColumns: _readStringList(json, const <String>[
        'selected_columns',
        'selectedColumns',
      ]),
      nearestNeighborsAlgorithm:
          _readString(json, const <String>[
            'nearest_neighbors_algorithm',
            'nearestNeighborsAlgorithm',
          ]) ??
          exactNearestNeighbors,
      topK: _readInt(json, const <String>['top_k', 'topK']) ?? 4,
      distanceType:
          _readString(json, const <String>['distance_type', 'distanceType']) ??
          'COSINE',
      numLeavesToSearch: _readInt(json, const <String>[
        'num_leaves_to_search',
        'numLeavesToSearch',
      ]),
      additionalFilter: _readString(json, const <String>[
        'additional_filter',
        'additionalFilter',
      ]),
      vectorSearchIndexSettings: _readObject(json, const <String>[
        'vector_search_index_settings',
        'vectorSearchIndexSettings',
      ], converter: VectorSearchIndexSettings.fromObject),
      additionalColumnsToSetup: _readObjectList(json, const <String>[
        'additional_columns_to_setup',
        'additionalColumnsToSetup',
      ], converter: TableColumn.fromObject),
      primaryKeyColumns: _readStringList(json, const <String>[
        'primary_key_columns',
        'primaryKeyColumns',
      ]),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_id': projectId,
      'instance_id': instanceId,
      'database_id': databaseId,
      'table_name': tableName,
      'content_column': contentColumn,
      'embedding_column': embeddingColumn,
      'vector_length': vectorLength,
      'vertex_ai_embedding_model_name': vertexAiEmbeddingModelName,
      'selected_columns': List<String>.from(selectedColumns),
      'nearest_neighbors_algorithm': nearestNeighborsAlgorithm,
      'top_k': topK,
      'distance_type': distanceType,
      if (numLeavesToSearch != null) 'num_leaves_to_search': numLeavesToSearch,
      if (additionalFilter != null) 'additional_filter': additionalFilter,
      if (vectorSearchIndexSettings != null)
        'vector_search_index_settings': vectorSearchIndexSettings!.toJson(),
      if (additionalColumnsToSetup != null)
        'additional_columns_to_setup': additionalColumnsToSetup!
            .map((TableColumn column) => column.toJson())
            .toList(growable: false),
      if (primaryKeyColumns != null)
        'primary_key_columns': List<String>.from(primaryKeyColumns!),
    };
  }

  static SpannerVectorStoreSettings fromObject(Object? value) {
    if (value is SpannerVectorStoreSettings) {
      return value;
    }
    if (value is Map) {
      return SpannerVectorStoreSettings.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    throw ArgumentError('Invalid SpannerVectorStoreSettings value: $value');
  }

  static List<String> _normalizeSelectedColumns({
    required List<String>? selectedColumns,
    required String contentColumn,
  }) {
    if (selectedColumns == null || selectedColumns.isEmpty) {
      return <String>[contentColumn];
    }
    return List<String>.from(selectedColumns);
  }
}

class SpannerToolSettings {
  SpannerToolSettings({
    List<Capabilities>? capabilities,
    this.maxExecutedQueryResultRows = 50,
    this.queryResultMode = QueryResultMode.defaultMode,
    this.vectorStoreSettings,
  }) : capabilities = capabilities == null
           ? <Capabilities>[Capabilities.dataRead]
           : List<Capabilities>.from(capabilities);

  final List<Capabilities> capabilities;
  final int maxExecutedQueryResultRows;
  final QueryResultMode queryResultMode;
  final SpannerVectorStoreSettings? vectorStoreSettings;

  static void ensureFeatureEnabled({Map<String, String>? environment}) {
    isFeatureEnabled(FeatureName.spannerToolSettings, environment: environment);
  }

  factory SpannerToolSettings.fromJson(Map<String, Object?> json) {
    ensureFeatureEnabled();

    const Set<String> allowedKeys = <String>{
      'capabilities',
      'max_executed_query_result_rows',
      'maxExecutedQueryResultRows',
      'query_result_mode',
      'queryResultMode',
      'vector_store_settings',
      'vectorStoreSettings',
    };
    final Set<String> unknownKeys = json.keys
        .where((String key) => !allowedKeys.contains(key))
        .toSet();
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError(
        'Unknown SpannerToolSettings fields: ${unknownKeys.join(', ')}',
      );
    }

    return SpannerToolSettings(
      capabilities: _readCapabilities(json['capabilities']),
      maxExecutedQueryResultRows:
          _readInt(json, const <String>[
            'max_executed_query_result_rows',
            'maxExecutedQueryResultRows',
          ]) ??
          50,
      queryResultMode:
          _readQueryResultMode(
            _readString(json, const <String>[
              'query_result_mode',
              'queryResultMode',
            ]),
          ) ??
          QueryResultMode.defaultMode,
      vectorStoreSettings: _readObject(json, const <String>[
        'vector_store_settings',
        'vectorStoreSettings',
      ], converter: SpannerVectorStoreSettings.fromObject),
    );
  }

  Map<String, Object?> toJson() {
    ensureFeatureEnabled();
    return <String, Object?>{
      'capabilities': capabilities
          .map((Capabilities capability) => capability.value)
          .toList(growable: false),
      'max_executed_query_result_rows': maxExecutedQueryResultRows,
      'query_result_mode': queryResultMode.value,
      if (vectorStoreSettings != null)
        'vector_store_settings': vectorStoreSettings!.toJson(),
    };
  }

  static SpannerToolSettings fromObject(Object? value) {
    if (value is SpannerToolSettings) {
      return value;
    }
    if (value is Map) {
      return SpannerToolSettings.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    return SpannerToolSettings();
  }
}

String _readRequiredString(Map<String, Object?> json, List<String> keys) {
  final String? value = _readString(json, keys);
  if (value == null || value.isEmpty) {
    throw ArgumentError('Missing required field `${keys.first}`.');
  }
  return value;
}

int _readRequiredInt(Map<String, Object?> json, List<String> keys) {
  final int? value = _readInt(json, keys);
  if (value == null) {
    throw ArgumentError('Missing required field `${keys.first}`.');
  }
  return value;
}

String? _readString(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    final String text = '$value';
    return text.isEmpty ? null : text;
  }
  return null;
}

int? _readInt(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    throw ArgumentError('Invalid int value for `$key`: $value');
  }
  return null;
}

bool? _readBool(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    throw ArgumentError('Invalid bool value for `$key`: $value');
  }
  return null;
}

List<String>? _readStringList(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    if (value is List) {
      return value.map((Object? item) => '$item').toList(growable: false);
    }
    throw ArgumentError('Invalid list value for `$key`: $value');
  }
  return null;
}

T? _readObject<T>(
  Map<String, Object?> json,
  List<String> keys, {
  required T Function(Object? value) converter,
}) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    return converter(json[key]);
  }
  return null;
}

List<T>? _readObjectList<T>(
  Map<String, Object?> json,
  List<String> keys, {
  required T Function(Object? value) converter,
}) {
  for (final String key in keys) {
    if (!json.containsKey(key)) {
      continue;
    }
    final Object? value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! List) {
      throw ArgumentError('Invalid list value for `$key`: $value');
    }
    return value.map((Object? item) => converter(item)).toList(growable: false);
  }
  return null;
}

List<Capabilities>? _readCapabilities(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw ArgumentError('Invalid capabilities value: $value');
  }
  return value
      .map((Object? item) {
        if (item is Capabilities) {
          return item;
        }
        return Capabilities.fromValue('$item');
      })
      .toList(growable: false);
}

QueryResultMode? _readQueryResultMode(String? value) {
  if (value == null) {
    return null;
  }
  return QueryResultMode.fromValue(value);
}
