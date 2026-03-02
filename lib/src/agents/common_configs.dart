/// Shared config models used across agent configuration types.
library;

/// Named or positional argument configuration.
class ArgumentConfig {
  /// Creates an argument config.
  ArgumentConfig({this.name, required this.value});

  /// Optional argument name.
  final String? name;

  /// Argument value.
  final Object? value;

  /// Creates argument config from JSON.
  factory ArgumentConfig.fromJson(Map<String, Object?> json) {
    if (!json.containsKey('value')) {
      throw ArgumentError('ArgumentConfig requires `value`.');
    }
    return ArgumentConfig(name: json['name'] as String?, value: json['value']);
  }

  /// Creates argument config from dynamic input.
  factory ArgumentConfig.fromDynamic(Object? raw) {
    if (raw is ArgumentConfig) {
      return raw;
    }
    if (raw is Map) {
      final Map<String, Object?> map = raw.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      if (map.containsKey('value')) {
        return ArgumentConfig.fromJson(map);
      }
    }
    return ArgumentConfig(value: raw);
  }

  /// Serializes argument config to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{'value': value, if (name != null) 'name': name};
  }
}

/// Callable code reference and arguments.
class CodeConfig {
  /// Creates a code config.
  CodeConfig({required this.name, List<Object?>? args})
    : args = _normalizeArgs(args);

  /// Function or symbol name.
  final String name;

  /// Normalized argument list.
  final List<ArgumentConfig> args;

  /// Creates code config from JSON.
  factory CodeConfig.fromJson(Map<String, Object?> json) {
    return CodeConfig(
      name: (json['name'] ?? '') as String,
      args: _extractArgs(json['args']),
    );
  }

  static List<Object?> _extractArgs(Object? rawArgs) {
    if (rawArgs is List) {
      return rawArgs.toList();
    }
    if (rawArgs is Map) {
      return rawArgs.entries
          .map(
            (MapEntry<Object?, Object?> entry) => <String, Object?>{
              'name': '${entry.key}',
              'value': entry.value,
            },
          )
          .toList();
    }
    return <Object?>[];
  }

  static List<ArgumentConfig> _normalizeArgs(List<Object?>? args) {
    if (args == null || args.isEmpty) {
      return <ArgumentConfig>[];
    }
    return args
        .map((Object? arg) => ArgumentConfig.fromDynamic(arg))
        .toList(growable: false);
  }

  /// Serializes code config to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (args.isNotEmpty)
        'args': args.map((ArgumentConfig e) => e.toJson()).toList(),
    };
  }
}

/// Reference to a sub-agent via config path or code reference.
class AgentRefConfig {
  /// Creates an agent reference configuration.
  AgentRefConfig({this.configPath, this.code}) {
    final bool hasConfigPath = configPath != null && configPath!.isNotEmpty;
    final bool hasCode = code != null && code!.isNotEmpty;
    if (hasConfigPath == hasCode) {
      throw ArgumentError(
        'Exactly one of `config_path` or `code` must be provided.',
      );
    }
  }

  /// Config file path for the sub-agent.
  final String? configPath;

  /// Code symbol path for the sub-agent.
  final String? code;

  /// Creates an agent reference from JSON.
  factory AgentRefConfig.fromJson(Map<String, Object?> json) {
    return AgentRefConfig(
      configPath:
          json['config_path'] as String? ?? json['configPath'] as String?,
      code: json['code'] as String?,
    );
  }

  /// Serializes this reference to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (configPath != null) 'config_path': configPath,
      if (code != null) 'code': code,
    };
  }
}
