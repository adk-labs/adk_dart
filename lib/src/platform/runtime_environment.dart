/// Runtime environment metadata model.
library;

/// Named runtime environment with key/value variables.
class RuntimeEnvironment {
  /// Creates runtime environment metadata.
  RuntimeEnvironment({String? name, Map<String, String>? variables})
    : name = name ?? 'local',
      variables =
          variables ?? Map<String, String>.from(const <String, String>{});

  /// Environment name.
  final String name;

  /// Environment variable map.
  final Map<String, String> variables;

  /// Returns variable value for [key], or `null` when absent.
  String? get(String key) => variables[key];
}
