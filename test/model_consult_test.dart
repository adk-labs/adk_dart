import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _AdvisorModel extends BaseLlm {
  _AdvisorModel({this.reply = 'Consider using approach B.'})
    : super(model: 'advisor-test-model');

  final String reply;
  int callCount = 0;
  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount++;
    lastRequest = request;
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[Part.text(reply)],
      ),
    );
  }
}

Future<ToolContext> _newToolContext() async {
  final sessionService = InMemorySessionService();
  final session = await sessionService.createSession(
    appName: 'test_app',
    userId: 'user_1',
  );

  final agent = Agent(name: 'main_agent', model: _AdvisorModel());
  final invocationContext = InvocationContext(
    invocationId: 'inv_1',
    agent: agent,
    session: session,
    sessionService: sessionService,
  );

  return Context(invocationContext);
}

void main() {
  group('ModelConsultTool', () {
    test('queries advisor model and returns advice', () async {
      final advisor = _AdvisorModel();
      final tool = ModelConsultTool(model: advisor);
      final toolContext = await _newToolContext();

      final result = await tool.run(
        args: {'question': 'What is the optimal caching strategy?'},
        toolContext: toolContext,
      );

      expect(result, isA<Map<String, Object?>>());
      final map = result as Map<String, Object?>;
      expect(map['status'], equals('success'));
      expect(map['advice'], equals('Consider using approach B.'));
      expect(advisor.callCount, equals(1));
    });

    test('ModelConsultToolset exposes ModelConsultTool', () async {
      final advisor = _AdvisorModel(reply: 'Custom advice');
      final toolset = ModelConsultToolset(model: advisor);

      final tools = await toolset.getTools();
      expect(tools.length, equals(1));
      expect(tools.first.name, equals(defaultConsultModelToolName));
    });
  });
}
