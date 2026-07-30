import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

InvocationContext _createTestInvocationContext() {
  return InvocationContext(
    invocationId: 'inv_1',
    sessionService: InMemorySessionService(),
    agent: LlmAgent(name: 'test_agent', model: 'gemini-pro'),
    session: Session(
      id: 's1',
      appName: 'app',
      userId: 'u1',
    ),
  );
}

void main() {
  group('ReflectAndRetryModelPlugin', () {
    test('provides adkHandleModelError function tool', () async {
      final ReflectAndRetryModelPlugin plugin = ReflectAndRetryModelPlugin(
        maxRetries: 2,
      );
      final LlmRequest request = LlmRequest(model: 'gemini-pro');

      final InvocationContext invocationContext = _createTestInvocationContext();
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );

      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: request,
      );

      expect(request.toolsDict.containsKey('adkHandleModelError'), isTrue);

      final Map<String, dynamic> result = plugin.adkHandleModelError(
        responseType: 'ERROR_HANDLED_BY_REFLECT_AND_RETRY_PLUGIN',
        errorType: 'MALFORMED_FUNCTION_CALL',
        errorDetails: 'Invalid function arguments',
        finishReason: 'MALFORMED_FUNCTION_CALL',
        retryCount: 1,
      );

      expect(result.containsKey('reflection_guidance'), isTrue);
      expect(result['reflection_guidance'], contains('attempt **1** of **2**'));
    });

    test('intercepts model error and generates retry response', () async {
      final ReflectAndRetryModelPlugin plugin = ReflectAndRetryModelPlugin(
        maxRetries: 2,
      );
      final InvocationContext invocationContext = _createTestInvocationContext();
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );

      final LlmResponse responseWithError = LlmResponse(
        errorCode: 'MALFORMED_FUNCTION_CALL',
        errorMessage: 'Invalid arguments',
        finishReason: 'MALFORMED_FUNCTION_CALL',
      );

      final LlmResponse? retryResponse = await plugin.afterModelCallback(
        callbackContext: callbackContext,
        llmResponse: responseWithError,
      );

      expect(retryResponse, isNotNull);
      final List<FunctionCall> calls = retryResponse!.getFunctionCalls();
      expect(calls.length, equals(1));
      expect(calls.first.name, equals('adkHandleModelError'));
      expect(calls.first.args['retry_count'], equals(1));
    });

    test('detects reserved tool call and warns model', () async {
      final ReflectAndRetryModelPlugin plugin = ReflectAndRetryModelPlugin(
        maxRetries: 2,
      );
      final InvocationContext invocationContext = _createTestInvocationContext();
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );

      final LlmResponse reservedCallResponse = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'adkHandleModelError',
              args: <String, dynamic>{},
            ),
          ],
        ),
      );

      final LlmResponse? retryResponse = await plugin.afterModelCallback(
        callbackContext: callbackContext,
        llmResponse: reservedCallResponse,
      );

      expect(retryResponse, isNotNull);
      final List<FunctionCall> calls = retryResponse!.getFunctionCalls();
      expect(calls.length, equals(1));
      expect(calls.first.name, equals('adkHandleModelError'));
      expect(calls.first.args['error_type'], equals('RESERVED_TOOL_CALL'));
    });
  });
}
