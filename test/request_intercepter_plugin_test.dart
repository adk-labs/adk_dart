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

InvocationContext _newInvocationContext() {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_eval',
    agent: LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    ),
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

void main() {
  test(
    'request intercepter stores request id and exposes request lookup',
    () async {
      final RequestIntercepterPlugin plugin = RequestIntercepterPlugin();
      final Context callbackContext = Context(_newInvocationContext());
      final LlmRequest request = LlmRequest(model: 'test-model');
      final LlmResponse response = LlmResponse();

      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: request,
      );
      final String requestId = callbackContext.state[llmRequestIdKey] as String;
      expect(requestId, isNotEmpty);

      await plugin.afterModelCallback(
        callbackContext: callbackContext,
        llmResponse: response,
      );
      expect(response.customMetadata?[llmRequestIdKey], requestId);
      expect(plugin.getModelRequest(response), same(request));
    },
  );

  test('request lookup returns null when metadata is absent', () {
    final RequestIntercepterPlugin plugin = RequestIntercepterPlugin();
    expect(plugin.getModelRequest(LlmResponse()), isNull);
  });
}
