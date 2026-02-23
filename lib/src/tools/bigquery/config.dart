import '../../features/_feature_registry.dart';

enum WriteMode {
  blocked('blocked'),
  protected('protected'),
  allowed('allowed');

  const WriteMode(this.value);

  final String value;

  static WriteMode fromObject(Object? value) {
    if (value is WriteMode) {
      return value;
    }

    final String normalized = '$value'.trim().toLowerCase();
    for (final WriteMode mode in WriteMode.values) {
      if (mode.value == normalized) {
        return mode;
      }
    }

    throw ArgumentError('Invalid write_mode value: $value');
  }
}

class BigQueryToolConfig {
  BigQueryToolConfig({
    this.writeMode = WriteMode.blocked,
    this.maximumBytesBilled,
    this.maxQueryResultRows = 50,
    this.applicationName,
    this.computeProjectId,
    this.location,
    Map<String, String>? jobLabels,
  }) : jobLabels = jobLabels == null
           ? null
           : Map<String, String>.unmodifiable(
               Map<String, String>.from(jobLabels),
             ) {
    _validateMaximumBytesBilled(maximumBytesBilled);
    _validateApplicationName(applicationName);
    _validateJobLabels(this.jobLabels);
    if (maxQueryResultRows <= 0) {
      throw ArgumentError('max_query_result_rows must be > 0.');
    }
  }

  final WriteMode writeMode;
  final int? maximumBytesBilled;
  final int maxQueryResultRows;
  final String? applicationName;
  final String? computeProjectId;
  final String? location;
  final Map<String, String>? jobLabels;

  static void ensureFeatureEnabled({Map<String, String>? environment}) {
    isFeatureEnabled(FeatureName.bigQueryToolConfig, environment: environment);
  }

  factory BigQueryToolConfig.fromJson(Map<String, Object?> json) {
    ensureFeatureEnabled();

    const Set<String> allowedKeys = <String>{
      'write_mode',
      'writeMode',
      'maximum_bytes_billed',
      'maximumBytesBilled',
      'max_query_result_rows',
      'maxQueryResultRows',
      'application_name',
      'applicationName',
      'compute_project_id',
      'computeProjectId',
      'location',
      'job_labels',
      'jobLabels',
    };

    final Set<String> unknownKeys = json.keys
        .where((String key) => !allowedKeys.contains(key))
        .toSet();
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError(
        'Unknown BigQueryToolConfig fields: ${unknownKeys.join(', ')}',
      );
    }

    final WriteMode writeMode = WriteMode.fromObject(
      json['write_mode'] ?? json['writeMode'] ?? WriteMode.blocked,
    );

    final int? maximumBytesBilled = _parseIntOrNull(
      json['maximum_bytes_billed'] ?? json['maximumBytesBilled'],
    );

    final int maxQueryResultRows = _parsePositiveInt(
      json['max_query_result_rows'] ?? json['maxQueryResultRows'],
      fallback: 50,
      fieldName: 'max_query_result_rows',
    );

    final String? applicationName = _readString(
      json['application_name'] ?? json['applicationName'],
    );
    final String? computeProjectId = _readString(
      json['compute_project_id'] ?? json['computeProjectId'],
    );
    final String? location = _readString(json['location']);

    final Object? labelsRaw = json['job_labels'] ?? json['jobLabels'];
    Map<String, String>? jobLabels;
    if (labelsRaw != null) {
      if (labelsRaw is! Map) {
        throw ArgumentError('job_labels must be a map of string keys/values.');
      }
      jobLabels = <String, String>{
        for (final MapEntry<Object?, Object?> entry in labelsRaw.entries)
          '${entry.key}': '${entry.value}',
      };
    }

    return BigQueryToolConfig(
      writeMode: writeMode,
      maximumBytesBilled: maximumBytesBilled,
      maxQueryResultRows: maxQueryResultRows,
      applicationName: applicationName,
      computeProjectId: computeProjectId,
      location: location,
      jobLabels: jobLabels,
    );
  }

  Map<String, Object?> toJson() {
    ensureFeatureEnabled();

    return <String, Object?>{
      'write_mode': writeMode.value,
      if (maximumBytesBilled != null)
        'maximum_bytes_billed': maximumBytesBilled,
      'max_query_result_rows': maxQueryResultRows,
      if (applicationName != null && applicationName!.isNotEmpty)
        'application_name': applicationName,
      if (computeProjectId != null && computeProjectId!.isNotEmpty)
        'compute_project_id': computeProjectId,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (jobLabels != null && jobLabels!.isNotEmpty) 'job_labels': jobLabels,
    };
  }

  BigQueryToolConfig copyWith({
    WriteMode? writeMode,
    Object? maximumBytesBilled = _sentinel,
    int? maxQueryResultRows,
    Object? applicationName = _sentinel,
    Object? computeProjectId = _sentinel,
    Object? location = _sentinel,
    Object? jobLabels = _sentinel,
  }) {
    return BigQueryToolConfig(
      writeMode: writeMode ?? this.writeMode,
      maximumBytesBilled: identical(maximumBytesBilled, _sentinel)
          ? this.maximumBytesBilled
          : maximumBytesBilled as int?,
      maxQueryResultRows: maxQueryResultRows ?? this.maxQueryResultRows,
      applicationName: identical(applicationName, _sentinel)
          ? this.applicationName
          : applicationName as String?,
      computeProjectId: identical(computeProjectId, _sentinel)
          ? this.computeProjectId
          : computeProjectId as String?,
      location: identical(location, _sentinel)
          ? this.location
          : location as String?,
      jobLabels: identical(jobLabels, _sentinel)
          ? this.jobLabels
          : jobLabels as Map<String, String>?,
    );
  }

  static BigQueryToolConfig fromObject(Object? value) {
    if (value is BigQueryToolConfig) {
      return value;
    }
    if (value is Map) {
      return BigQueryToolConfig.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    return BigQueryToolConfig();
  }

  static void _validateMaximumBytesBilled(int? value) {
    if (value != null && value < 10485760) {
      throw ArgumentError(
        'In BigQuery on-demand pricing, charges are rounded up to the nearest '
        'MB with minimum 10 MB processed. maximum_bytes_billed must be >= 10485760.',
      );
    }
  }

  static void _validateApplicationName(String? value) {
    if (value != null && value.contains(' ')) {
      throw ArgumentError('Application name should not contain spaces.');
    }
  }

  static void _validateJobLabels(Map<String, String>? labels) {
    if (labels == null) {
      return;
    }
    for (final String key in labels.keys) {
      if (key.isEmpty) {
        throw ArgumentError('Label keys cannot be empty.');
      }
    }
  }
}

const Object _sentinel = Object();

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value'.trim();
  return text.isEmpty ? null : text;
}

int _parsePositiveInt(
  Object? value, {
  required int fallback,
  required String fieldName,
}) {
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    if (value > 0) {
      return value;
    }
    throw ArgumentError('$fieldName must be > 0.');
  }
  if (value is num) {
    final int parsed = value.toInt();
    if (parsed > 0) {
      return parsed;
    }
    throw ArgumentError('$fieldName must be > 0.');
  }
  if (value is String) {
    final int? parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  throw ArgumentError('Invalid $fieldName value: $value');
}

int? _parseIntOrNull(Object? value) {
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
    return int.tryParse(value.trim());
  }
  throw ArgumentError('Invalid integer value: $value');
}
