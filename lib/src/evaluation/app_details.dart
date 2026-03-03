import 'common.dart';

/// Per-agent metadata captured during one invocation.
class AgentDetails {
  /// Creates agent detail metadata.
  AgentDetails({
    required this.name,
    this.instructions = '',
    List<Object?>? toolDeclarations,
  }) : toolDeclarations = toolDeclarations ?? <Object?>[];

  /// Agent name.
  final String name;

  /// System/developer instructions applied to the agent.
  final String instructions;

  /// Serialized tool declarations available to the agent.
  final List<Object?> toolDeclarations;

  /// Decodes agent details from JSON.
  factory AgentDetails.fromJson(EvalJson json) {
    return AgentDetails(
      name: asNullableString(json['name']) ?? '',
      instructions: asNullableString(json['instructions']) ?? '',
      toolDeclarations: asObjectList(
        json['toolDeclarations'] ?? json['tool_declarations'],
      ),
    );
  }

  /// Encodes agent details for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'name': name,
      'instructions': instructions,
      'tool_declarations': List<Object?>.from(toolDeclarations),
    };
  }
}

/// Invocation-scoped metadata for all participating agents.
class AppDetails {
  /// Creates app details.
  AppDetails({Map<String, AgentDetails>? agentDetails})
    : agentDetails = agentDetails ?? <String, AgentDetails>{};

  /// Agent metadata keyed by agent name.
  final Map<String, AgentDetails> agentDetails;

  /// Decodes app details from JSON.
  factory AppDetails.fromJson(EvalJson json) {
    final EvalJson agentsJson = asEvalJson(
      json['agentDetails'] ?? json['agent_details'],
    );
    return AppDetails(
      agentDetails: agentsJson.map((String key, Object? value) {
        return MapEntry(key, AgentDetails.fromJson(asEvalJson(value)));
      }),
    );
  }

  /// Returns instructions configured for [agentName].
  String getDeveloperInstructions(String agentName) {
    final AgentDetails? details = agentDetails[agentName];
    if (details == null) {
      throw ArgumentError('`$agentName` not found in the agentic system.');
    }
    return details.instructions;
  }

  /// Returns serialized tool declarations keyed by agent name.
  Map<String, List<Object?>> getToolsByAgentName() {
    return agentDetails.map((String key, AgentDetails value) {
      return MapEntry(key, List<Object?>.from(value.toolDeclarations));
    });
  }

  /// Encodes app details for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'agent_details': agentDetails.map((String key, AgentDetails value) {
        return MapEntry(key, value.toJson());
      }),
    };
  }
}
