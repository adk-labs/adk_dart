/// Discriminated configuration model for root agent definitions.
library;

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

/// Resolves the agent-class discriminator from raw JSON-like [value].
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

/// Wrapper for a parsed root [BaseAgentConfig].
class AgentConfig {
  /// Creates an [AgentConfig] for [root].
  AgentConfig(this.root);

  /// Root agent configuration.
  final BaseAgentConfig root;

  /// Creates an [AgentConfig] from JSON.
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

  /// Serializes the root config to JSON.
  Map<String, Object?> toJson() => root.toJson();
}
