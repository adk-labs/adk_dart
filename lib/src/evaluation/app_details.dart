import 'common.dart';

class AgentDetails {
  AgentDetails({
    required this.name,
    this.instructions = '',
    List<Object?>? toolDeclarations,
  }) : toolDeclarations = toolDeclarations ?? <Object?>[];

  final String name;
  final String instructions;
  final List<Object?> toolDeclarations;

  factory AgentDetails.fromJson(EvalJson json) {
    return AgentDetails(
      name: asNullableString(json['name']) ?? '',
      instructions: asNullableString(json['instructions']) ?? '',
      toolDeclarations: asObjectList(
        json['toolDeclarations'] ?? json['tool_declarations'],
      ),
    );
  }

  EvalJson toJson() {
    return <String, Object?>{
      'name': name,
      'instructions': instructions,
      'tool_declarations': List<Object?>.from(toolDeclarations),
    };
  }
}

class AppDetails {
  AppDetails({Map<String, AgentDetails>? agentDetails})
    : agentDetails = agentDetails ?? <String, AgentDetails>{};

  final Map<String, AgentDetails> agentDetails;

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

  String getDeveloperInstructions(String agentName) {
    final AgentDetails? details = agentDetails[agentName];
    if (details == null) {
      throw ArgumentError('`$agentName` not found in the agentic system.');
    }
    return details.instructions;
  }

  Map<String, List<Object?>> getToolsByAgentName() {
    return agentDetails.map((String key, AgentDetails value) {
      return MapEntry(key, List<Object?>.from(value.toolDeclarations));
    });
  }

  EvalJson toJson() {
    return <String, Object?>{
      'agent_details': agentDetails.map((String key, AgentDetails value) {
        return MapEntry(key, value.toJson());
      }),
    };
  }
}
