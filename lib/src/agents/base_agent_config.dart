import 'common_configs.dart';

class BaseAgentConfig {
  BaseAgentConfig({
    this.agentClass = 'BaseAgent',
    required this.name,
    this.description = '',
    List<AgentRefConfig>? subAgents,
    List<CodeConfig>? beforeAgentCallbacks,
    List<CodeConfig>? afterAgentCallbacks,
    Map<String, Object?>? extras,
  }) : subAgents = subAgents ?? <AgentRefConfig>[],
       beforeAgentCallbacks = beforeAgentCallbacks ?? <CodeConfig>[],
       afterAgentCallbacks = afterAgentCallbacks ?? <CodeConfig>[],
       extras = extras ?? <String, Object?>{};

  final String agentClass;
  final String name;
  final String description;
  final List<AgentRefConfig> subAgents;
  final List<CodeConfig> beforeAgentCallbacks;
  final List<CodeConfig> afterAgentCallbacks;
  final Map<String, Object?> extras;

  static const Set<String> _knownKeys = <String>{
    'agent_class',
    'agentClass',
    'name',
    'description',
    'sub_agents',
    'subAgents',
    'before_agent_callbacks',
    'beforeAgentCallbacks',
    'after_agent_callbacks',
    'afterAgentCallbacks',
  };

  factory BaseAgentConfig.fromJson(
    Map<String, Object?> json, {
    bool forbidExtras = false,
  }) {
    final String? name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw ArgumentError('BaseAgentConfig requires non-empty `name`.');
    }

    final Map<String, Object?> extras = json.map(
      (String key, Object? value) => MapEntry(key, value),
    )..removeWhere((String key, Object? _) => _knownKeys.contains(key));
    if (forbidExtras && extras.isNotEmpty) {
      throw ArgumentError(
        'Unexpected fields for ${json['agent_class'] ?? json['agentClass'] ?? 'BaseAgent'}: '
        '${extras.keys.join(', ')}',
      );
    }

    return BaseAgentConfig(
      agentClass:
          (json['agent_class'] as String?) ??
          (json['agentClass'] as String?) ??
          'BaseAgent',
      name: name,
      description: (json['description'] ?? '') as String,
      subAgents: _decodeAgentRefs(json['sub_agents'] ?? json['subAgents']),
      beforeAgentCallbacks: _decodeCodeConfigs(
        json['before_agent_callbacks'] ?? json['beforeAgentCallbacks'],
      ),
      afterAgentCallbacks: _decodeCodeConfigs(
        json['after_agent_callbacks'] ?? json['afterAgentCallbacks'],
      ),
      extras: extras,
    );
  }

  static List<AgentRefConfig> _decodeAgentRefs(Object? value) {
    if (value is! List) {
      return <AgentRefConfig>[];
    }
    return value
        .map((Object? item) {
          if (item is! Map) {
            throw ArgumentError('sub_agents entry must be a map.');
          }
          return AgentRefConfig.fromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          );
        })
        .toList(growable: false);
  }

  static List<CodeConfig> _decodeCodeConfigs(Object? value) {
    if (value is! List) {
      return <CodeConfig>[];
    }
    return value
        .map((Object? item) {
          if (item is! Map) {
            throw ArgumentError('Callback entry must be a map.');
          }
          return CodeConfig.fromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          );
        })
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'agent_class': agentClass,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      if (subAgents.isNotEmpty)
        'sub_agents': subAgents.map((AgentRefConfig e) => e.toJson()).toList(),
      if (beforeAgentCallbacks.isNotEmpty)
        'before_agent_callbacks': beforeAgentCallbacks
            .map((CodeConfig e) => e.toJson())
            .toList(),
      if (afterAgentCallbacks.isNotEmpty)
        'after_agent_callbacks': afterAgentCallbacks
            .map((CodeConfig e) => e.toJson())
            .toList(),
      ...extras,
    };
  }
}
