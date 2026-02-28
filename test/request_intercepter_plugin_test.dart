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
      expect(
        plugin.getModelRequest(response),
        isNull,
        reason: 'lookup should evict the cached request',
      );
    },
  );

  test('request lookup returns null when metadata is absent', () {
    final RequestIntercepterPlugin plugin = RequestIntercepterPlugin();
    expect(plugin.getModelRequest(LlmResponse()), isNull);
  });

  test('evicts oldest entries when cache exceeds max size', () async {
    final RequestIntercepterPlugin plugin = RequestIntercepterPlugin(
      maxCachedRequests: 2,
    );
    final Context callbackContext = Context(_newInvocationContext());

    final LlmRequest request1 = LlmRequest(model: 'model-1');
    final LlmResponse response1 = LlmResponse();
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: request1,
    );
    await plugin.afterModelCallback(
      callbackContext: callbackContext,
      llmResponse: response1,
    );

    final LlmRequest request2 = LlmRequest(model: 'model-2');
    final LlmResponse response2 = LlmResponse();
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: request2,
    );
    await plugin.afterModelCallback(
      callbackContext: callbackContext,
      llmResponse: response2,
    );

    final LlmRequest request3 = LlmRequest(model: 'model-3');
    final LlmResponse response3 = LlmResponse();
    await plugin.beforeModelCallback(
      callbackContext: callbackContext,
      llmRequest: request3,
    );
    await plugin.afterModelCallback(
      callbackContext: callbackContext,
      llmResponse: response3,
    );

    expect(plugin.getModelRequest(response1), isNull);
    expect(plugin.getModelRequest(response2), same(request2));
    expect(plugin.getModelRequest(response3), same(request3));
  });
}
