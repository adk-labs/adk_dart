import 'base_agent_config.dart';

class SequentialAgentConfig extends BaseAgentConfig {
  SequentialAgentConfig({
    super.agentClass = 'SequentialAgent',
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallbacks,
    super.afterAgentCallbacks,
    super.extras,
  });

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

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'agent_class': 'SequentialAgent',
    };
  }
}
