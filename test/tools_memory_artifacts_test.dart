import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Future<Context> _newToolContext({
  required BaseMemoryService memoryService,
  required BaseArtifactService artifactService,
  Content? userContent,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'u1',
    sessionId: 's_tool_ctx',
  );
  return Context(
    InvocationContext(
      sessionService: sessionService,
      artifactService: artifactService,
      memoryService: memoryService,
      invocationId: 'inv_tool_ctx',
      agent: Agent(
        name: 'root_agent',
        model: _NoopModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      ),
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
  test(
    'LoadMemoryTool returns matched memories and appends instruction',
    () async {
      final InMemoryMemoryService memoryService = InMemoryMemoryService();
      await memoryService.addSessionToMemory(
        Session(
          id: 's_mem',
          appName: 'app',
          userId: 'u1',
          events: <Event>[
            Event(
              invocationId: 'inv_mem',
              author: 'user',
              content: Content.userText('hello memory'),
            ),
          ],
        ),
      );

      final Context toolContext = await _newToolContext(
        memoryService: memoryService,
        artifactService: InMemoryArtifactService(),
      );
      final LoadMemoryTool tool = LoadMemoryTool();
      final Object? result = await tool.run(
        args: <String, dynamic>{'query': 'hello'},
        toolContext: toolContext,
      );

      expect(result, isA<Map<String, Object?>>());
      expect((result! as Map<String, Object?>)['memories'], isNotEmpty);

      final LlmRequest request = LlmRequest();
      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );
      expect(request.config.systemInstruction, contains('load_memory'));
    },
  );

  test('PreloadMemoryTool inserts past conversation instruction', () async {
    final InMemoryMemoryService memoryService = InMemoryMemoryService();
    await memoryService.addSessionToMemory(
      Session(
        id: 's_mem_preload',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_mem',
            author: 'assistant',
            content: Content(role: 'model', parts: <Part>[Part.text('stored')]),
          ),
        ],
      ),
    );

    final Context toolContext = await _newToolContext(
      memoryService: memoryService,
      artifactService: InMemoryArtifactService(),
      userContent: Content.userText('stored'),
    );
    final PreloadMemoryTool tool = PreloadMemoryTool();
    final LlmRequest request = LlmRequest();

    await tool.processLlmRequest(toolContext: toolContext, llmRequest: request);
    expect(request.config.systemInstruction, contains('<PAST_CONVERSATIONS>'));
    expect(request.config.systemInstruction, contains('stored'));
  });

  test(
    'LoadArtifactsTool appends requested artifacts to request contents',
    () async {
      final Context toolContext = await _newToolContext(
        memoryService: InMemoryMemoryService(),
        artifactService: InMemoryArtifactService(),
      );
      await toolContext.saveArtifact('report.txt', Part.text('artifact-body'));

      final LoadArtifactsTool tool = LoadArtifactsTool();
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'load_artifacts',
                response: <String, dynamic>{
                  'artifact_names': <String>['report.txt'],
                },
              ),
            ],
          ),
        ],
      );

      await tool.processLlmRequest(
        toolContext: toolContext,
        llmRequest: request,
      );

      final bool hasArtifactBody = request.contents.any(
        (Content content) => content.parts.any(
          (Part part) =>
              part.text != null && part.text!.contains('artifact-body'),
        ),
      );
      expect(hasArtifactBody, isTrue);
    },
  );
}
