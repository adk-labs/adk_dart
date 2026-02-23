import '../../errors/not_found_error.dart';
import '../common.dart';

class UserBehavior {
  UserBehavior({
    required this.name,
    required this.description,
    List<String>? behaviorInstructions,
    List<String>? violationRubrics,
  }) : behaviorInstructions = behaviorInstructions ?? <String>[],
       violationRubrics = violationRubrics ?? <String>[];

  final String name;
  final String description;
  final List<String> behaviorInstructions;
  final List<String> violationRubrics;

  factory UserBehavior.fromJson(EvalJson json) {
    return UserBehavior(
      name: asNullableString(json['name']) ?? '',
      description: asNullableString(json['description']) ?? '',
      behaviorInstructions: asObjectList(
        json['behaviorInstructions'] ?? json['behavior_instructions'],
      ).whereType<String>().toList(),
      violationRubrics: asObjectList(
        json['violationRubrics'] ?? json['violation_rubrics'],
      ).whereType<String>().toList(),
    );
  }

  String getBehaviorInstructionsStr() {
    return behaviorInstructions.map((String i) => '  * $i').join('\n');
  }

  String getViolationRubricsStr() {
    return violationRubrics.map((String i) => '  * $i').join('\n');
  }

  EvalJson toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'behavior_instructions': List<String>.from(behaviorInstructions),
      'violation_rubrics': List<String>.from(violationRubrics),
    };
  }
}

class UserPersona {
  UserPersona({
    required this.id,
    required this.description,
    List<UserBehavior>? behaviors,
  }) : behaviors = behaviors ?? <UserBehavior>[];

  final String id;
  final String description;
  final List<UserBehavior> behaviors;

  factory UserPersona.fromJson(EvalJson json) {
    return UserPersona(
      id: asNullableString(json['id']) ?? '',
      description: asNullableString(json['description']) ?? '',
      behaviors: asObjectList(json['behaviors']).map((Object? value) {
        return UserBehavior.fromJson(asEvalJson(value));
      }).toList(),
    );
  }

  EvalJson toJson() {
    return <String, Object?>{
      'id': id,
      'description': description,
      'behaviors': behaviors.map((UserBehavior b) => b.toJson()).toList(),
    };
  }
}

class UserPersonaRegistry {
  final Map<String, UserPersona> _registry = <String, UserPersona>{};

  UserPersona getPersona(String personaId) {
    final UserPersona? persona = _registry[personaId];
    if (persona == null) {
      throw NotFoundError('$personaId not found in registry.');
    }
    return persona;
  }

  void registerPersona(String personaId, UserPersona userPersona) {
    _registry[personaId] = userPersona;
  }

  List<UserPersona> getRegisteredPersonas() {
    return _registry.values.map((UserPersona p) => p).toList();
  }
}
