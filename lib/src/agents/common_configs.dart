class CodeConfig {
  CodeConfig({required this.name, List<Object?>? args})
    : args = args ?? <Object?>[];

  final String name;
  final List<Object?> args;

  factory CodeConfig.fromJson(Map<String, Object?> json) {
    return CodeConfig(
      name: (json['name'] ?? '') as String,
      args: (json['args'] as List?)?.toList() ?? <Object?>[],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'name': name, if (args.isNotEmpty) 'args': args};
  }
}
