class BaseToolConfig {
  BaseToolConfig({Map<String, Object?>? extras})
    : extras = extras ?? <String, Object?>{};

  final Map<String, Object?> extras;
}

class ToolArgsConfig {
  ToolArgsConfig({Map<String, Object?>? values})
    : values = values ?? <String, Object?>{};

  final Map<String, Object?> values;

  Object? operator [](String key) => values[key];

  Map<String, Object?> toJson() => Map<String, Object?>.from(values);
}

class ToolConfig {
  ToolConfig({required this.name, ToolArgsConfig? args}) : args = args;

  final String name;
  final ToolArgsConfig? args;

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (args != null) 'args': args!.toJson(),
    };
  }
}
