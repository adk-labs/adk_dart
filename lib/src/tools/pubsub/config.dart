import '../../features/_feature_registry.dart';

class PubSubToolConfig {
  PubSubToolConfig({this.projectId});

  final String? projectId;

  static void ensureFeatureEnabled({Map<String, String>? environment}) {
    isFeatureEnabled(FeatureName.pubsubToolConfig, environment: environment);
  }

  factory PubSubToolConfig.fromJson(Map<String, Object?> json) {
    ensureFeatureEnabled();

    const Set<String> allowedKeys = <String>{'project_id', 'projectId'};
    final Set<String> unknownKeys = json.keys
        .where((String key) => !allowedKeys.contains(key))
        .toSet();
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError(
        'Unknown PubSubToolConfig fields: ${unknownKeys.join(', ')}',
      );
    }

    final String? projectId =
        _readString(json['project_id']) ?? _readString(json['projectId']);
    return PubSubToolConfig(projectId: projectId);
  }

  Map<String, Object?> toJson() {
    ensureFeatureEnabled();
    return <String, Object?>{
      if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId,
    };
  }

  static PubSubToolConfig fromObject(Object? value) {
    if (value is PubSubToolConfig) {
      return value;
    }
    if (value is Map) {
      return PubSubToolConfig.fromJson(
        value.map((Object? key, Object? item) => MapEntry('$key', item)),
      );
    }
    return PubSubToolConfig();
  }
}

String? _readString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  return text.isEmpty ? null : text;
}
