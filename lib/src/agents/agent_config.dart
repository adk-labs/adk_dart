import 'base_agent_config.dart';
import 'llm_agent_config.dart';
import 'loop_agent_config.dart';
import 'parallel_agent_config.dart';
import 'sequential_agent_config.dart';

const Set<String> _adkAgentClasses = <String>{
  'LlmAgent',
  'LoopAgent',
  'ParallelAgent',
  'SequentialAgent',
};

String agentConfigDiscriminator(Object? value) {
  if (value is! Map) {
    throw ArgumentError('Invalid agent config: $value');
  }
  final Map<String, Object?> map = value.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final String agentClass =
      (map['agent_class'] as String?) ??
      (map['agentClass'] as String?) ??
      'LlmAgent';
  if (_adkAgentClasses.contains(agentClass)) {
    return agentClass;
  }
  return 'BaseAgent';
}

class AgentConfig {
  AgentConfig(this.root);

  final BaseAgentConfig root;

  factory AgentConfig.fromJson(Map<String, Object?> json) {
    final String tag = agentConfigDiscriminator(json);
    return AgentConfig(switch (tag) {
      'LlmAgent' => LlmAgentConfig.fromJson(json),
      'LoopAgent' => LoopAgentConfig.fromJson(json),
      'ParallelAgent' => ParallelAgentConfig.fromJson(json),
      'SequentialAgent' => SequentialAgentConfig.fromJson(json),
      _ => BaseAgentConfig.fromJson(json),
    });
  }

  Map<String, Object?> toJson() => root.toJson();
}
