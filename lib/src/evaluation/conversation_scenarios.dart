/// Shared evaluation models and utility helpers.
library;

import 'common.dart';
import 'simulation/pre_built_personas.dart';
import 'simulation/user_simulator_personas.dart';

/// Defines a synthetic multi-turn conversation scenario for simulation.
class ConversationScenario {
  /// Creates a conversation scenario.
  ConversationScenario({
    required this.startingPrompt,
    required this.conversationPlan,
    this.userPersona,
  });

  /// Initial user message used to start the conversation.
  final String startingPrompt;

  /// Narrative plan guiding expected conversation progression.
  final String conversationPlan;

  /// Optional persona used to generate user behavior.
  final UserPersona? userPersona;

  /// Decodes a scenario from JSON maps used by eval fixtures.
  factory ConversationScenario.fromJson(EvalJson json) {
    final Object? rawPersona = json['userPersona'] ?? json['user_persona'];
    UserPersona? userPersona;
    if (rawPersona is String) {
      userPersona = getDefaultPersonaRegistry().getPersona(rawPersona);
    } else if (rawPersona != null) {
      userPersona = UserPersona.fromJson(asEvalJson(rawPersona));
    }

    return ConversationScenario(
      startingPrompt:
          asNullableString(json['startingPrompt']) ??
          asNullableString(json['starting_prompt']) ??
          '',
      conversationPlan:
          asNullableString(json['conversationPlan']) ??
          asNullableString(json['conversation_plan']) ??
          '',
      userPersona: userPersona,
    );
  }

  /// Encodes this scenario for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'starting_prompt': startingPrompt,
      'conversation_plan': conversationPlan,
      if (userPersona != null) 'user_persona': userPersona!.toJson(),
    };
  }
}

/// Wraps multiple [ConversationScenario] entries.
class ConversationScenarios {
  /// Creates a conversation scenario collection.
  ConversationScenarios({List<ConversationScenario>? scenarios})
    : scenarios = scenarios ?? <ConversationScenario>[];

  /// Scenarios included in this collection.
  final List<ConversationScenario> scenarios;

  /// Decodes a scenario collection from JSON.
  factory ConversationScenarios.fromJson(EvalJson json) {
    return ConversationScenarios(
      scenarios: asObjectList(json['scenarios']).map((Object? value) {
        return ConversationScenario.fromJson(asEvalJson(value));
      }).toList(),
    );
  }

  /// Encodes this collection for persistence.
  EvalJson toJson() {
    return <String, Object?>{
      'scenarios': scenarios
          .map((ConversationScenario scenario) => scenario.toJson())
          .toList(),
    };
  }
}
