import 'user_simulator_personas.dart';

final UserPersonaRegistry _defaultPersonaRegistry = _buildDefaultRegistry();

UserPersonaRegistry _buildDefaultRegistry() {
  final UserPersonaRegistry registry = UserPersonaRegistry();
  registry.registerPersona(
    'default_goal_oriented',
    UserPersona(
      id: 'default_goal_oriented',
      description:
          'Goal-oriented user who follows the conversation plan and provides '
          'required details when asked.',
      behaviors: <UserBehavior>[
        UserBehavior(
          name: 'Advance when agent succeeds',
          description:
              'Moves to the next planned goal once the previous goal is done.',
          behaviorInstructions: <String>[
            'Keep requests aligned with the conversation plan.',
            'Do not invent new goals unrelated to the plan.',
          ],
          violationRubrics: <String>[
            'Introduces a new unrelated goal.',
            'Repeats already completed goals without reason.',
          ],
        ),
      ],
    ),
  );
  return registry;
}

UserPersonaRegistry getDefaultPersonaRegistry() => _defaultPersonaRegistry;
