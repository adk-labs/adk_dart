/// Configuration models for Data Agent tool behavior.
library;

import '../../features/_feature_registry.dart';

/// Configuration values for Data Agent tool behavior.
class DataAgentToolConfig {
  /// Creates Data Agent tool configuration.
  DataAgentToolConfig({this.maxQueryResultRows = 50});

  /// Maximum rows returned from Data Agent queries.
  final int maxQueryResultRows;

  /// Ensures the Data Agent tool config feature flag is enabled.
  static void ensureFeatureEnabled({Map<String, String>? environment}) {
    isFeatureEnabled(FeatureName.dataAgentToolConfig, environment: environment);
  }

  /// Decodes Data Agent configuration from JSON.
  factory DataAgentToolConfig.fromJson(Map<String, Object?> json) {
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
        'Unknown DataAgentToolConfig fields: ${unknownKeys.join(', ')}',
      );
    }

    final Object? rawValue =
        json['max_query_result_rows'] ?? json['maxQueryResultRows'];
    final int maxRows = _parsePositiveInt(rawValue, fallback: 50);
    return DataAgentToolConfig(maxQueryResultRows: maxRows);
  }

  /// Encodes this config for persistence.
  Map<String, Object?> toJson() {
    ensureFeatureEnabled();
    return <String, Object?>{'max_query_result_rows': maxQueryResultRows};
  }

  /// Coerces supported object types into [DataAgentToolConfig].
  static DataAgentToolConfig fromObject(Object? value) {
    if (value is DataAgentToolConfig) {
      return value;
    }
    if (value is Map) {
      return DataAgentToolConfig.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    return DataAgentToolConfig();
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
