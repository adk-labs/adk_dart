import 'common.dart';
import 'simulation/pre_built_personas.dart';
import 'simulation/user_simulator_personas.dart';

class ConversationScenario {
  ConversationScenario({
    required this.startingPrompt,
    required this.conversationPlan,
    this.userPersona,
  });

  final String startingPrompt;
  final String conversationPlan;
  final UserPersona? userPersona;

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

  EvalJson toJson() {
    return <String, Object?>{
      'starting_prompt': startingPrompt,
      'conversation_plan': conversationPlan,
      if (userPersona != null) 'user_persona': userPersona!.toJson(),
    };
  }
}

class ConversationScenarios {
  ConversationScenarios({List<ConversationScenario>? scenarios})
    : scenarios = scenarios ?? <ConversationScenario>[];

  final List<ConversationScenario> scenarios;

  factory ConversationScenarios.fromJson(EvalJson json) {
    return ConversationScenarios(
      scenarios: asObjectList(json['scenarios']).map((Object? value) {
        return ConversationScenario.fromJson(asEvalJson(value));
      }).toList(),
    );
  }

  EvalJson toJson() {
    return <String, Object?>{
      'scenarios': scenarios
          .map((ConversationScenario scenario) => scenario.toJson())
          .toList(),
    };
  }
}
