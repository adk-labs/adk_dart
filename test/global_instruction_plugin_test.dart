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

Context _newContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_global_instruction',
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
  return Context(invocationContext);
}

void main() {
  test('injects global instruction when request has no instruction', () async {
    final GlobalInstructionPlugin plugin = GlobalInstructionPlugin(
      globalInstruction: 'Global policy',
    );
    final LlmRequest request = LlmRequest();

    await plugin.beforeModelCallback(
      callbackContext: _newContext(),
      llmRequest: request,
    );

    expect(request.config.systemInstruction, 'Global policy');
  });

  test('prepends global instruction before existing instruction', () async {
    final GlobalInstructionPlugin plugin = GlobalInstructionPlugin(
      globalInstruction: 'Global policy',
    );
    final LlmRequest request = LlmRequest(
      config: GenerateContentConfig(systemInstruction: 'Local instruction'),
    );

    await plugin.beforeModelCallback(
      callbackContext: _newContext(),
      llmRequest: request,
    );

    expect(
      request.config.systemInstruction,
      'Global policy\n\nLocal instruction',
    );
  });

  test('supports async instruction provider', () async {
    final GlobalInstructionPlugin plugin = GlobalInstructionPlugin(
      globalInstructionProvider: (CallbackContext context) async {
        return 'Provider instruction for ${context.agentName}';
      },
    );
    final LlmRequest request = LlmRequest();

    await plugin.beforeModelCallback(
      callbackContext: _newContext(),
      llmRequest: request,
    );

    expect(
      request.config.systemInstruction,
      'Provider instruction for root_agent',
    );
  });
}
