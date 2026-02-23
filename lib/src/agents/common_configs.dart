class ArgumentConfig {
  ArgumentConfig({this.name, required this.value});

  final String? name;
  final Object? value;

  factory ArgumentConfig.fromJson(Map<String, Object?> json) {
    if (!json.containsKey('value')) {
      throw ArgumentError('ArgumentConfig requires `value`.');
    }
    return ArgumentConfig(name: json['name'] as String?, value: json['value']);
  }

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

  Map<String, Object?> toJson() {
    return <String, Object?>{'value': value, if (name != null) 'name': name};
  }
}

class CodeConfig {
  CodeConfig({required this.name, List<Object?>? args})
    : args = _normalizeArgs(args);

  final String name;
  final List<ArgumentConfig> args;

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (args.isNotEmpty)
        'args': args.map((ArgumentConfig e) => e.toJson()).toList(),
    };
  }
}

class AgentRefConfig {
  AgentRefConfig({this.configPath, this.code}) {
    final bool hasConfigPath = configPath != null && configPath!.isNotEmpty;
    final bool hasCode = code != null && code!.isNotEmpty;
    if (hasConfigPath == hasCode) {
      throw ArgumentError(
        'Exactly one of `config_path` or `code` must be provided.',
      );
    }
  }

  final String? configPath;
  final String? code;

  factory AgentRefConfig.fromJson(Map<String, Object?> json) {
    return AgentRefConfig(
      configPath:
          json['config_path'] as String? ?? json['configPath'] as String?,
      code: json['code'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (configPath != null) 'config_path': configPath,
      if (code != null) 'code': code,
    };
  }
}
