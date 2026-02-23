import 'base_agent_config.dart';

class ParallelAgentConfig extends BaseAgentConfig {
  ParallelAgentConfig({
    super.agentClass = 'ParallelAgent',
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallbacks,
    super.afterAgentCallbacks,
    super.extras,
  });

  factory ParallelAgentConfig.fromJson(Map<String, Object?> json) {
    final BaseAgentConfig base = BaseAgentConfig.fromJson(
      json,
      forbidExtras: true,
    );
    return ParallelAgentConfig(
      agentClass:
          (json['agent_class'] as String?) ??
          (json['agentClass'] as String?) ??
          'ParallelAgent',
      name: base.name,
      description: base.description,
      subAgents: base.subAgents,
      beforeAgentCallbacks: base.beforeAgentCallbacks,
      afterAgentCallbacks: base.afterAgentCallbacks,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{...super.toJson(), 'agent_class': 'ParallelAgent'};
  }
}
