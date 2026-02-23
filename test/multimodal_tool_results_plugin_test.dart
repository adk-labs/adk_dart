import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _FakeTool extends BaseTool {
  _FakeTool() : super(name: 'fake_tool', description: 'fake');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'result': 'ok'};
  }
}

Context _newContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_mm',
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's_mm', appName: 'app', userId: 'u1'),
  );
  return Context(invocationContext, functionCallId: 'call_1');
}

void main() {
  test('stores single Part result in state and returns null', () async {
    final MultimodalToolResultsPlugin plugin = MultimodalToolResultsPlugin();
    final Context context = _newContext();
    final _FakeTool tool = _FakeTool();

    final Map<String, dynamic>? callbackResult = await plugin.afterToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: context,
      result: <String, dynamic>{'result': Part.text('tool part')},
    );

    expect(callbackResult, isNull);
    final Object? saved = context.state[partsReturnedByToolsStateKey];
    expect(saved, isA<List<Part>>());
    expect((saved as List<Part>).single.text, 'tool part');
  });

  test('stores list of Part results and appends to llm request', () async {
    final MultimodalToolResultsPlugin plugin = MultimodalToolResultsPlugin();
    final Context context = _newContext();
    final _FakeTool tool = _FakeTool();
    await plugin.afterToolCallback(
      tool: tool,
      toolArgs: <String, dynamic>{},
      toolContext: context,
      result: <String, dynamic>{
        'result': <Part>[Part.text('p1'), Part.text('p2')],
      },
    );

    final LlmRequest request = LlmRequest(
      contents: <Content>[
        Content(role: 'user', parts: <Part>[Part.text('question')]),
      ],
    );
    await plugin.beforeModelCallback(
      callbackContext: context,
      llmRequest: request,
    );

    expect(request.contents.single.parts, hasLength(3));
    expect(request.contents.single.parts[1].text, 'p1');
    expect(request.contents.single.parts[2].text, 'p2');
    expect(context.state[partsReturnedByToolsStateKey], isA<List<Part>>());
    expect(
      (context.state[partsReturnedByToolsStateKey] as List<Part>),
      isEmpty,
    );
  });

  test(
    'returns original result when callback output is not multimodal part',
    () async {
      final MultimodalToolResultsPlugin plugin = MultimodalToolResultsPlugin();
      final Map<String, dynamic> result = <String, dynamic>{'status': 'ok'};

      final Map<String, dynamic>? callbackResult = await plugin
          .afterToolCallback(
            tool: _FakeTool(),
            toolArgs: <String, dynamic>{},
            toolContext: _newContext(),
            result: result,
          );

      expect(callbackResult, same(result));
    },
  );
}
