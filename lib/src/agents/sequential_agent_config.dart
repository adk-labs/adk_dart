/// Configuration model for sequential-agent declarations.
library;

import 'base_agent_config.dart';

/// Sequential agent configuration fields.
class SequentialAgentConfig extends BaseAgentConfig {
  /// Creates a sequential agent config.
  SequentialAgentConfig({
    super.agentClass = 'SequentialAgent',
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallbacks,
    super.afterAgentCallbacks,
    super.extras,
  });

  /// Creates a sequential agent config from JSON.
  factory SequentialAgentConfig.fromJson(Map<String, Object?> json) {
    final BaseAgentConfig base = BaseAgentConfig.fromJson(
      json,
      forbidExtras: true,
    );
    return SequentialAgentConfig(
      agentClass:
          (json['agent_class'] as String?) ??
          (json['agentClass'] as String?) ??
          'SequentialAgent',
      name: base.name,
      description: base.description,
      subAgents: base.subAgents,
      beforeAgentCallbacks: base.beforeAgentCallbacks,
      afterAgentCallbacks: base.afterAgentCallbacks,
    );
  }

  /// Serializes this sequential config to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'agent_class': 'SequentialAgent',
    };
  }
}
