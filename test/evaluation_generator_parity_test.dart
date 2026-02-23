import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EchoAgent extends BaseAgent {
  _EchoAgent() : super(name: 'echo_agent');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String input =
        context.userContent?.parts
            .map((Part p) => p.text ?? '')
            .where((String t) => t.isNotEmpty)
            .join(' ') ??
        '';
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('Echo: $input'),
    );
  }
}

class _MockModel extends BaseLlm {
  _MockModel({required this.responses}) : super(model: 'eval-generator-model');

  final List<LlmResponse> responses;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    if (_index >= responses.length) {
      return;
    }
    yield responses[_index++].copyWith();
  }
}

class _SingleTurnSimulator extends UserSimulator<BaseUserSimulatorConfig> {
  _SingleTurnSimulator({required this.userMessage})
    : _served = false,
      super(
        config: BaseUserSimulatorConfig(),
        configDecoder: (BaseUserSimulatorConfig config) =>
            BaseUserSimulatorConfig(values: config.toJson()),
      );

  final Content userMessage;
  final List<int> observedEventCounts = <int>[];
  bool _served;

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> events) async {
    observedEventCounts.add(events.length);
    if (_served) {
      return NextUserMessage(status: Status.noMessageGenerated);
    }
    _served = true;
    return NextUserMessage(status: Status.success, userMessage: userMessage);
  }

  @override
  Evaluator? getSimulationEvaluator() => null;
}

class _CapturingUserSimulatorProvider extends UserSimulatorProvider {
  _CapturingUserSimulatorProvider(this.simulator) : super();

  final _SingleTurnSimulator simulator;
  int provideCount = 0;

  @override
  UserSimulator provide(EvalCase evalCase) {
    provideCount += 1;
    return simulator;
  }
}

void main() {
  group('evaluation generator parity', () {
    test('uses user simulator provider conversation loop', () async {
      final _SingleTurnSimulator simulator = _SingleTurnSimulator(
        userMessage: Content.userText('hello from simulator'),
      );
      final _CapturingUserSimulatorProvider provider =
          _CapturingUserSimulatorProvider(simulator);

      final EvalSet evalSet = EvalSet(
        evalSetId: 'set_sim',
        evalCases: <EvalCase>[
          EvalCase(
            evalId: 'case_sim',
            conversationScenario: ConversationScenario(
              startingPrompt: 'unused in custom provider',
              conversationPlan: 'single turn',
            ),
          ),
        ],
      );

      final List<EvalCaseResponses> responses =
          await EvaluationGenerator.generateResponses(
            evalSet: evalSet,
            rootAgent: _EchoAgent(),
            repeatNum: 1,
            userSimulatorProvider: provider,
          );

      expect(provider.provideCount, 1);
      expect(simulator.observedEventCounts, isNotEmpty);
      expect(simulator.observedEventCounts.first, 0);
      expect(simulator.observedEventCounts.last, greaterThan(0));

      final List<Invocation> invocations = responses.first.responses.first;
      expect(invocations, hasLength(1));
      expect(
        getTextFromContent(invocations.first.finalResponse),
        contains('Echo: hello from simulator'),
      );
    });

    test('captures app details from request intercepter metadata', () async {
      final _MockModel model = _MockModel(
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('done')),
        ],
      );

      String pingTool() => 'pong';

      final Agent rootAgent = Agent(
        name: 'root_agent',
        model: model,
        instruction: 'Follow policy exactly.',
        tools: <Object>[
          FunctionTool(
            func: pingTool,
            name: 'ping_tool',
            description: 'Returns pong.',
          ),
        ],
      );

      final Invocation promptInvocation = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'ping'},
          ],
        },
      );

      final EvalSet evalSet = EvalSet(
        evalSetId: 'set_app_details',
        evalCases: <EvalCase>[
          EvalCase(
            evalId: 'case_app_details',
            conversation: <Invocation>[promptInvocation],
          ),
        ],
      );

      final List<EvalCaseResponses> responses =
          await EvaluationGenerator.generateResponses(
            evalSet: evalSet,
            rootAgent: rootAgent,
            repeatNum: 1,
          );

      final Invocation invocation = responses.first.responses.first.first;
      final AppDetails? appDetails = invocation.appDetails;
      expect(appDetails, isNotNull);
      expect(appDetails!.agentDetails.containsKey('root_agent'), isTrue);

      final AgentDetails details = appDetails.agentDetails['root_agent']!;
      expect(details.instructions, contains('Follow policy exactly.'));
      expect(details.toolDeclarations, isNotEmpty);

      final String toolDeclarationsJson = getToolDeclarationsAsJsonStr(
        appDetails,
      );
      expect(toolDeclarationsJson, contains('ping_tool'));
    });
  });
}
