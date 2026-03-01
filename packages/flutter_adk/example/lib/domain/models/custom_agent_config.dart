class CustomAgentConfig {
  const CustomAgentConfig({
    required this.name,
    required this.description,
    required this.instruction,
    required this.enableCapitalTool,
    required this.enableWeatherTool,
    required this.enableTimeTool,
  });

  factory CustomAgentConfig.defaults() {
    return const CustomAgentConfig(
      name: 'My Custom Agent',
      description: 'User-configured assistant with selectable tools.',
      instruction:
          'You are a customizable assistant. Use available tools when relevant. '
          'If a needed tool is not available, explain limitations clearly and propose next best action.',
      enableCapitalTool: true,
      enableWeatherTool: true,
      enableTimeTool: true,
    );
  }

  final String name;
  final String description;
  final String instruction;
  final bool enableCapitalTool;
  final bool enableWeatherTool;
  final bool enableTimeTool;

  CustomAgentConfig copyWith({
    String? name,
    String? description,
    String? instruction,
    bool? enableCapitalTool,
    bool? enableWeatherTool,
    bool? enableTimeTool,
  }) {
    return CustomAgentConfig(
      name: name ?? this.name,
      description: description ?? this.description,
      instruction: instruction ?? this.instruction,
      enableCapitalTool: enableCapitalTool ?? this.enableCapitalTool,
      enableWeatherTool: enableWeatherTool ?? this.enableWeatherTool,
      enableTimeTool: enableTimeTool ?? this.enableTimeTool,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'instruction': instruction,
      'enableCapitalTool': enableCapitalTool,
      'enableWeatherTool': enableWeatherTool,
      'enableTimeTool': enableTimeTool,
    };
  }

  factory CustomAgentConfig.fromJson(Map<String, Object?> json) {
    return CustomAgentConfig(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : CustomAgentConfig.defaults().name,
      description: (json['description'] as String?)?.trim().isNotEmpty == true
          ? (json['description'] as String).trim()
          : CustomAgentConfig.defaults().description,
      instruction: (json['instruction'] as String?)?.trim().isNotEmpty == true
          ? (json['instruction'] as String).trim()
          : CustomAgentConfig.defaults().instruction,
      enableCapitalTool: json['enableCapitalTool'] != false,
      enableWeatherTool: json['enableWeatherTool'] != false,
      enableTimeTool: json['enableTimeTool'] != false,
    );
  }
}
