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
