import 'dart:collection';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeLlm extends BaseLlm {
  _FakeLlm({required this.responses}) : super(model: 'fake-model');

  final Queue<String> responses;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (responses.isEmpty) {
      return;
    }
    final String next = responses.removeFirst();
    yield LlmResponse(content: Content.modelText(next), turnComplete: true);
  }
}

void main() {
  group('user simulator contracts', () {
    test('NextUserMessage enforces message iff success', () {
      expect(
        () => NextUserMessage(status: Status.success),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NextUserMessage(
          status: Status.stopSignalDetected,
          userMessage: Content.userText('hello'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        NextUserMessage(
          status: Status.success,
          userMessage: Content.userText('ok'),
        ).status,
        Status.success,
      );
    });

    test(
      'StaticUserSimulator returns messages then stop signal status',
      () async {
        final StaticUserSimulator simulator = StaticUserSimulator(
          staticConversation: <Invocation>[
            Invocation(
              userContent: <String, Object?>{
                'role': 'user',
                'parts': <Object?>[
                  <String, Object?>{'text': 'first'},
                ],
              },
            ),
          ],
        );

        final NextUserMessage first = await simulator.getNextUserMessage(
          const <Event>[],
        );
        expect(first.status, Status.success);
        expect(first.userMessage?.parts.first.text, 'first');

        final NextUserMessage second = await simulator.getNextUserMessage(
          const <Event>[],
        );
        expect(second.status, Status.stopSignalDetected);
      },
    );

    test('UserSimulatorProvider selects static and llm simulators', () {
      final UserSimulatorProvider provider = UserSimulatorProvider();

      final UserSimulator staticSimulator = provider.provide(
        EvalCase(
          evalId: 'static-case',
          conversation: <Invocation>[
            Invocation(
              userContent: <String, Object?>{
                'role': 'user',
                'parts': <Object?>[
                  <String, Object?>{'text': 'hello'},
                ],
              },
            ),
          ],
        ),
      );
      expect(staticSimulator, isA<StaticUserSimulator>());

      final UserSimulator llmSimulator = provider.provide(
        EvalCase(
          evalId: 'llm-case',
          conversationScenario: ConversationScenario(
            startingPrompt: 'Start',
            conversationPlan: 'Step 1',
          ),
        ),
      );
      expect(llmSimulator, isA<LlmBackedUserSimulator>());
    });
  });

  group('llm-backed simulator prompts', () {
    test('template validator checks required placeholders', () {
      expect(
        isValidUserSimulatorTemplate(
          'A {{ stop_signal }} B {{ conversation_plan }} C {{ conversation_history }}',
          requiredParams: <String>[
            'stop_signal',
            'conversation_plan',
            'conversation_history',
          ],
        ),
        isTrue,
      );
      expect(
        isValidUserSimulatorTemplate(
          'A {{ stop_signal }}',
          requiredParams: <String>['stop_signal', 'conversation_plan'],
        ),
        isFalse,
      );
    });

    test('prompt builders render core fields', () {
      final String userPrompt = getLlmBackedUserSimulatorPrompt(
        conversationPlan: 'Book a table',
        conversationHistory: 'agent: hi',
        stopSignal: '</finished>',
      );
      expect(userPrompt, contains('Book a table'));
      expect(userPrompt, contains('agent: hi'));
      expect(userPrompt, contains('</finished>'));

      final String qualityPrompt = getPerTurnUserSimulatorQualityPrompt(
        conversationPlan: 'Book a table',
        conversationHistory: 'agent: hi',
        generatedUserResponse: 'please reserve at 7pm',
        stopSignal: '</finished>',
      );
      expect(qualityPrompt, contains('Book a table'));
      expect(qualityPrompt, contains('please reserve at 7pm'));
    });
  });

  group('prebuilt personas parity', () {
    test(
      'default registry exposes expert/novice/evaluator persona catalogs',
      () {
        final UserPersonaRegistry registry = getDefaultPersonaRegistry();
        final List<String> personaIds = registry
            .getRegisteredPersonas()
            .map((UserPersona persona) => persona.id)
            .toList();

        expect(
          personaIds,
          containsAll(<String>[
            'EXPERT',
            'NOVICE',
            'EVALUATOR',
            'default_goal_oriented',
          ]),
        );

        final UserPersona expert = registry.getPersona('EXPERT');
        expect(expert.behaviors, hasLength(6));
        expect(
          expert.behaviors.map((UserBehavior behavior) => behavior.name),
          containsAll(<String>[
            'Advance in the Agent succeeds',
            'Answer only relevant questions',
            'Correct the Agent if it makes a mistake',
            'Troubleshoot once (if necessary)',
            'End the conversation appropriately',
            'Professional tone',
          ]),
        );

        final UserPersona novice = registry.getPersona('NOVICE');
        expect(novice.behaviors, hasLength(5));
        expect(
          novice.behaviors.map((UserBehavior behavior) => behavior.name),
          containsAll(<String>[
            'Advance if the Agent succeeds',
            'Do not correct the Agent',
            'Answer all questions',
            'End the conversation appropriately',
            'Conversational tone',
          ]),
        );

        final UserPersona evaluator = registry.getPersona('EVALUATOR');
        expect(evaluator.behaviors, hasLength(5));
        expect(
          evaluator.behaviors.map((UserBehavior behavior) => behavior.name),
          contains('Answer only relevant questions'),
        );

        final UserPersona legacyDefault = registry.getPersona(
          'default_goal_oriented',
        );
        expect(legacyDefault.id, 'default_goal_oriented');
        expect(legacyDefault.behaviors, hasLength(1));
        expect(
          legacyDefault.behaviors.single.name,
          'Advance if the Agent succeeds',
        );
      },
    );
  });

  group('llm-backed user simulator runtime', () {
    test(
      'first turn uses starting prompt then consumes llm responses',
      () async {
        final Queue<String> responses = Queue<String>.from(<String>[
          'Please book for two people.',
          '</finished>',
        ]);
        final LlmBackedUserSimulator simulator = LlmBackedUserSimulator(
          config: LlmBackedUserSimulatorConfig(maxAllowedInvocations: 10),
          conversationScenario: ConversationScenario(
            startingPrompt: 'I need help booking dinner.',
            conversationPlan: 'Book dinner, then confirm.',
          ),
          llmFactory: (String _) => _FakeLlm(responses: responses),
        );

        final NextUserMessage first = await simulator.getNextUserMessage(
          const <Event>[],
        );
        expect(first.status, Status.success);
        expect(
          first.userMessage?.parts.first.text,
          'I need help booking dinner.',
        );

        final List<Event> history = <Event>[
          Event(
            invocationId: 'inv-1',
            author: 'agent',
            content: Content.modelText('What time should I book?'),
          ),
        ];

        final NextUserMessage second = await simulator.getNextUserMessage(
          history,
        );
        expect(second.status, Status.success);
        expect(
          second.userMessage?.parts.first.text,
          'Please book for two people.',
        );

        history.add(
          Event(
            invocationId: 'inv-2',
            author: 'agent',
            content: Content.modelText('Done.'),
          ),
        );

        final NextUserMessage third = await simulator.getNextUserMessage(
          history,
        );
        expect(third.status, Status.stopSignalDetected);
      },
    );

    test('turn limit is enforced', () async {
      final LlmBackedUserSimulator simulator = LlmBackedUserSimulator(
        config: LlmBackedUserSimulatorConfig(maxAllowedInvocations: 1),
        conversationScenario: ConversationScenario(
          startingPrompt: 'start',
          conversationPlan: 'plan',
        ),
        llmFactory: (String _) => _FakeLlm(responses: Queue<String>()),
      );

      final NextUserMessage first = await simulator.getNextUserMessage(
        const <Event>[],
      );
      expect(first.status, Status.success);

      final NextUserMessage second = await simulator.getNextUserMessage(
        const <Event>[],
      );
      expect(second.status, Status.turnLimitReached);
    });

    test('simulation evaluator is provided', () {
      final LlmBackedUserSimulator simulator = LlmBackedUserSimulator(
        config: LlmBackedUserSimulatorConfig(),
        conversationScenario: ConversationScenario(
          startingPrompt: 'start',
          conversationPlan: 'plan',
        ),
        llmFactory: (String _) => _FakeLlm(responses: Queue<String>()),
      );
      expect(simulator.getSimulationEvaluator(), isNotNull);
    });
  });
}
