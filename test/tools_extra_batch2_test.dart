import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<Context> _newContext({Content? userContent}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'u1',
  );
  return Context(
    InvocationContext(
      invocationId: 'inv_tool_extra',
      sessionService: sessionService,
      agent: Agent(name: 'root', model: _NoopModel()),
      session: session,
      userContent: userContent,
    ),
  );
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

void main() {
  group('tools extra batch2', () {
    test('ToolConfig parses and serializes args', () {
      final ToolConfig config = ToolConfig.fromJson(<String, Object?>{
        'name': 'my_tool',
        'args': <String, Object?>{'x': 1},
      });
      expect(config.name, 'my_tool');
      expect(config.args?['x'], 1);
      expect(config.toJson()['name'], 'my_tool');
    });

    test('ExampleTool appends example instruction', () async {
      final ExampleTool tool = ExampleTool(<Example>[
        Example(input: 'hi', output: 'hello'),
      ]);
      final Context context = await _newContext(
        userContent: Content.userText('what is up?'),
      );
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

      await tool.processLlmRequest(toolContext: context, llmRequest: request);
      expect(request.config.systemInstruction, contains('Example 1'));
      expect(request.config.systemInstruction, contains('what is up?'));
    });

    test(
      'UrlContextTool validates model support and appends built-in declaration',
      () async {
        final UrlContextTool tool = UrlContextTool();
        final Context context = await _newContext();

        await expectLater(
          () => tool.processLlmRequest(
            toolContext: context,
            llmRequest: LlmRequest(model: 'gemini-1.5-flash'),
          ),
          throwsArgumentError,
        );

        final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
        await tool.processLlmRequest(toolContext: context, llmRequest: request);
        final List<ToolDeclaration>? tools = request.config.tools;
        expect(tools, isNotNull);
        expect(tools!.isNotEmpty, isTrue);
        expect(tools.last.functionDeclarations.first.name, 'url_context');
      },
    );
  });
}
