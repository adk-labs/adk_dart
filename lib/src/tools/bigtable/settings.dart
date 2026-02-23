import '../../features/_feature_registry.dart';

class BigtableToolSettings {
  BigtableToolSettings({this.maxQueryResultRows = 50});

  final int maxQueryResultRows;

  static void ensureFeatureEnabled({Map<String, String>? environment}) {
    isFeatureEnabled(
      FeatureName.bigtableToolSettings,
      environment: environment,
    );
  }

  factory BigtableToolSettings.fromJson(Map<String, Object?> json) {
    ensureFeatureEnabled();

    const Set<String> allowedKeys = <String>{
      'max_query_result_rows',
      'maxQueryResultRows',
    };
    final Set<String> unknownKeys = json.keys
        .where((String key) => !allowedKeys.contains(key))
        .toSet();
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError(
        'Unknown BigtableToolSettings fields: ${unknownKeys.join(', ')}',
      );
    }

    final int maxRows = _parsePositiveInt(
      json['max_query_result_rows'] ?? json['maxQueryResultRows'],
      fallback: 50,
    );
    return BigtableToolSettings(maxQueryResultRows: maxRows);
  }

  Map<String, Object?> toJson() {
    ensureFeatureEnabled();
    return <String, Object?>{'max_query_result_rows': maxQueryResultRows};
  }

  static BigtableToolSettings fromObject(Object? value) {
    if (value is BigtableToolSettings) {
      return value;
    }
    if (value is Map) {
      return BigtableToolSettings.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    return BigtableToolSettings();
  }
}

int _parsePositiveInt(Object? value, {required int fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    if (value > 0) {
      return value;
    }
    throw ArgumentError('max_query_result_rows must be > 0.');
  }
  if (value is num) {
    final int parsed = value.toInt();
    if (parsed > 0) {
      return parsed;
    }
    throw ArgumentError('max_query_result_rows must be > 0.');
  }
  if (value is String) {
    final int? parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }
  throw ArgumentError('Invalid max_query_result_rows value: $value');
}
