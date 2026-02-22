class RuntimeEnvironment {
  RuntimeEnvironment({String? name, Map<String, String>? variables})
    : name = name ?? 'local',
      variables =
          variables ?? Map<String, String>.from(const <String, String>{});

  final String name;
  final Map<String, String> variables;

  String? get(String key) => variables[key];
}
