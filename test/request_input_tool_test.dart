import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('RequestInputTool parity', () {
    test('exposes the ADK request-input function declaration', () {
      final FunctionDeclaration declaration = requestInput.getDeclaration();

      expect(requestInput.name, requestInputFunctionCallName);
      expect(requestInput.isLongRunning, isTrue);
      expect(declaration.name, requestInputFunctionCallName);
      expect(declaration.parameters['type'], 'object');
      expect(declaration.parameters['required'], <String>['message']);

      final Map<String, Object?> properties =
          declaration.parameters['properties'] as Map<String, Object?>;
      expect(properties['message'], isA<Map<String, Object?>>());
      expect(properties['response_schema'], isA<Map<String, Object?>>());
    });

    test('processLlmRequest appends the request-input tool', () async {
      final Context context = _newToolContext();
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

      await requestInput.processLlmRequest(
        toolContext: context,
        llmRequest: request,
      );

      expect(request.toolsDict[requestInputFunctionCallName], requestInput);
      expect(request.config.tools, hasLength(1));
      expect(
        request.config.tools!.single.functionDeclarations.single.name,
        requestInputFunctionCallName,
      );
    });

    test('run is a placeholder for long-running user response', () async {
      final Object? result = await requestInput.run(
        args: <String, dynamic>{'message': 'Need more details'},
        toolContext: _newToolContext(),
      );

      expect(result, isNull);
    });

    test('event helpers create request-input function call and response', () {
      final RequestInput request = RequestInput(
        interruptId: 'interrupt_1',
        payload: <String, Object?>{'step': 'approval'},
        message: 'Need approval',
        responseSchema: <String, Object?>{'type': 'object'},
      );

      final Event event = createRequestInputEvent(
        request,
        invocationId: 'inv_request',
        author: 'workflow',
      );
      final FunctionCall call = event.getFunctionCalls().single;

      expect(event.invocationId, 'inv_request');
      expect(event.author, 'workflow');
      expect(event.longRunningToolIds, <String>{'interrupt_1'});
      expect(call.name, requestInputFunctionCallName);
      expect(call.id, 'interrupt_1');
      expect(call.args['interruptId'], 'interrupt_1');
      expect(call.args['payload'], <String, Object?>{'step': 'approval'});
      expect(call.args['message'], 'Need approval');
      expect(call.args['response_schema'], <String, Object?>{'type': 'object'});
      expect(hasRequestInputFunctionCall(event), isTrue);
      expect(getRequestInputInterruptIds(event), <String>['interrupt_1']);

      final RequestInput decoded = RequestInput.fromJson(call.args);
      expect(decoded.interruptId, 'interrupt_1');
      expect(decoded.message, 'Need approval');
      expect(decoded.responseSchema, <String, Object?>{'type': 'object'});

      final Part response = createRequestInputResponse(
        'interrupt_1',
        <String, dynamic>{'answer': 'approved'},
      );
      expect(response.functionResponse?.name, requestInputFunctionCallName);
      expect(response.functionResponse?.id, 'interrupt_1');
      expect(response.functionResponse?.response, <String, dynamic>{
        'answer': 'approved',
      });
    });
  });
}

Context _newToolContext() {
  return Context(
    InvocationContext(
      sessionService: InMemorySessionService(),
      invocationId: 'inv_request_input',
      agent: LlmAgent(name: 'root'),
      session: Session(id: 's_request_input', appName: 'app', userId: 'user'),
    ),
  );
}
