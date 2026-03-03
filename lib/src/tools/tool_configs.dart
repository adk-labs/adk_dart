/// Base config container for tool implementations.
class BaseToolConfig {
  /// Creates a base tool config.
  BaseToolConfig({Map<String, Object?>? extras})
    : extras = extras ?? <String, Object?>{};

  /// Extra implementation-specific configuration fields.
  final Map<String, Object?> extras;
}

/// Typed wrapper for tool argument configuration.
class ToolArgsConfig {
  /// Creates tool argument config values.
  ToolArgsConfig({Map<String, Object?>? values})
    : values = values ?? <String, Object?>{};

  /// Raw argument values keyed by name.
  final Map<String, Object?> values;

  /// Returns one argument value by [key].
  Object? operator [](String key) => values[key];

  /// Encodes arguments for persistence.
  Map<String, Object?> toJson() => Map<String, Object?>.from(values);
}

/// Serialized tool declaration with optional argument config.
class ToolConfig {
  /// Creates a tool config payload.
  ToolConfig({required this.name, this.args});

  /// Tool name.
  final String name;

  /// Optional argument configuration.
  final ToolArgsConfig? args;

  /// Decodes a tool config from JSON.
  factory ToolConfig.fromJson(Map<String, Object?> json) {
    return ToolConfig(
      name: (json['name'] ?? '') as String,
      args: json['args'] is Map
          ? ToolArgsConfig(
              values: (json['args'] as Map).map(
                (Object? key, Object? value) => MapEntry('$key', value),
              ),
            )
          : null,
    );
  }

  /// Encodes this tool config for persistence.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (args != null) 'args': args!.toJson(),
    };
  }
}
