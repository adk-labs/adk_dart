import 'base_agent_config.dart';

class LoopAgentConfig extends BaseAgentConfig {
  LoopAgentConfig({
    super.agentClass = 'LoopAgent',
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallbacks,
    super.afterAgentCallbacks,
    super.extras,
    this.maxIterations,
  });

  final int? maxIterations;

  static const Set<String> _knownLoopKeys = <String>{
    'max_iterations',
    'maxIterations',
  };

  factory LoopAgentConfig.fromJson(Map<String, Object?> json) {
    final BaseAgentConfig base = BaseAgentConfig.fromJson(json);
    final Map<String, Object?> extras = Map<String, Object?>.from(base.extras)
      ..removeWhere((String key, Object? _) => _knownLoopKeys.contains(key));
    if (extras.isNotEmpty) {
      throw ArgumentError(
        'Unexpected fields for LoopAgentConfig: ${extras.keys.join(', ')}',
      );
    }

    final Object? raw = json['max_iterations'] ?? json['maxIterations'];
    if (raw != null && raw is! int) {
      throw ArgumentError('max_iterations must be an integer.');
    }

    return LoopAgentConfig(
      agentClass:
          (json['agent_class'] as String?) ??
          (json['agentClass'] as String?) ??
          'LoopAgent',
      name: base.name,
      description: base.description,
      subAgents: base.subAgents,
      beforeAgentCallbacks: base.beforeAgentCallbacks,
      afterAgentCallbacks: base.afterAgentCallbacks,
      maxIterations: raw as int?,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'agent_class': 'LoopAgent',
      if (maxIterations != null) 'max_iterations': maxIterations,
    };
  }
}
