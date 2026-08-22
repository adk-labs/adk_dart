/// Configuration models for Data Agent tool behavior.
library;

import '../../features/_feature_registry.dart';

/// Configuration values for Data Agent tool behavior.
class DataAgentToolConfig {
  /// Creates Data Agent tool configuration.
  DataAgentToolConfig({
    this.maxQueryResultRows = 50,
    this.location,
    this.apiEndpoint,
    this.dataAgentModificationTimeoutSeconds = 60,
    this.dataAgentModificationPollIntervalSeconds = 2,
    this.enableDataAgentModification = false,
  });

  /// Maximum rows returned from Data Agent queries.
  final int maxQueryResultRows;

  /// Optional Google Cloud location (e.g. 'global', 'eu', 'us').
  final String? location;

  /// Optional custom API endpoint.
  final String? apiEndpoint;

  /// Total timeout in seconds when waiting for data agent mutation.
  final int dataAgentModificationTimeoutSeconds;

  /// Poll interval in seconds when waiting for data agent mutation.
  final int dataAgentModificationPollIntervalSeconds;

  /// Whether the toolset is allowed to mutate data agent resources.
  final bool enableDataAgentModification;

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
      'location',
      'api_endpoint',
      'apiEndpoint',
      'data_agent_modification_timeout_seconds',
      'dataAgentModificationTimeoutSeconds',
      'data_agent_modification_poll_interval_seconds',
      'dataAgentModificationPollIntervalSeconds',
      'enable_data_agent_modification',
      'enableDataAgentModification',
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
    final String? loc = json['location'] as String?;
    final String? endpoint =
        (json['api_endpoint'] ?? json['apiEndpoint']) as String?;
    final Object? rawTimeout =
        json['data_agent_modification_timeout_seconds'] ??
        json['dataAgentModificationTimeoutSeconds'];
    final int timeout = _parsePositiveInt(rawTimeout, fallback: 60);
    final Object? rawPoll =
        json['data_agent_modification_poll_interval_seconds'] ??
        json['dataAgentModificationPollIntervalSeconds'];
    final int poll = _parsePositiveInt(rawPoll, fallback: 2);
    final bool enableModification =
        (json['enable_data_agent_modification'] ??
            json['enableDataAgentModification']) ==
        true;

    return DataAgentToolConfig(
      maxQueryResultRows: maxRows,
      location: loc,
      apiEndpoint: endpoint,
      dataAgentModificationTimeoutSeconds: timeout,
      dataAgentModificationPollIntervalSeconds: poll,
      enableDataAgentModification: enableModification,
    );
  }

  /// Encodes this config for persistence.
  Map<String, Object?> toJson() {
    ensureFeatureEnabled();
    return <String, Object?>{
      'max_query_result_rows': maxQueryResultRows,
      if (location != null) 'location': location,
      if (apiEndpoint != null) 'api_endpoint': apiEndpoint,
      'data_agent_modification_timeout_seconds':
          dataAgentModificationTimeoutSeconds,
      'data_agent_modification_poll_interval_seconds':
          dataAgentModificationPollIntervalSeconds,
      'enable_data_agent_modification': enableDataAgentModification,
    };
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
