/// Base configuration model for agent definitions.
library;

import 'common_configs.dart';

/// Common configuration fields shared across agent types.
class BaseAgentConfig {
  /// Creates a base agent configuration.
  BaseAgentConfig({
    this.agentClass = 'BaseAgent',
    required this.name,
    this.version = '',
    this.description = '',
    List<AgentRefConfig>? subAgents,
    List<CodeConfig>? beforeAgentCallbacks,
    List<CodeConfig>? afterAgentCallbacks,
    Map<String, Object?>? extras,
  }) : subAgents = subAgents ?? <AgentRefConfig>[],
       beforeAgentCallbacks = beforeAgentCallbacks ?? <CodeConfig>[],
       afterAgentCallbacks = afterAgentCallbacks ?? <CodeConfig>[],
       extras = extras ?? <String, Object?>{};

  /// Agent class identifier.
  final String agentClass;

  /// Agent name.
  final String name;

  /// Agent version string.
  final String version;

  /// Agent description text.
  final String description;

  /// Child agent references.
  final List<AgentRefConfig> subAgents;

  /// Callbacks executed before `runAsync`.
  final List<CodeConfig> beforeAgentCallbacks;

  /// Callbacks executed after `runAsync`.
  final List<CodeConfig> afterAgentCallbacks;

  /// Unknown or extension fields preserved from source config.
  final Map<String, Object?> extras;

  static const Set<String> _knownKeys = <String>{
    'agent_class',
    'agentClass',
    'name',
    'version',
    'description',
    'sub_agents',
    'subAgents',
    'before_agent_callbacks',
    'beforeAgentCallbacks',
    'after_agent_callbacks',
    'afterAgentCallbacks',
  };

  /// Creates a config object from JSON.
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
      version: (json['version'] ?? '') as String,
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

  /// Serializes this config object to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'agent_class': agentClass,
      'name': name,
      if (version.isNotEmpty) 'version': version,
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
