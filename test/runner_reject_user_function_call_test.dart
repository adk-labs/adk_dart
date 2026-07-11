// Tests that the runner rejects user-authored messages containing function
// calls, preventing model bypass. Ported from google/adk-python
// tests/unittests/test_runners.py::test_run_async_rejects_user_function_call
// (commit 283e92ef).

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

void main() {
  test('runAsync rejects user-authored messages with function calls', () async {
    final Agent agent = Agent(name: 'test_agent', model: _NoopModel());
    final InMemoryRunner runner = InMemoryRunner(agent: agent);
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'user_1',
      sessionId: 'session_reject',
    );

    final Content maliciousMessage = Content(
      role: 'user',
      parts: <Part>[
        Part(
          functionCall: FunctionCall(
            name: 'some_tool',
            args: <String, dynamic>{'key': 'value'},
          ),
        ),
      ],
    );

    await expectLater(
      runner
          .runAsync(
            userId: 'user_1',
            sessionId: session.id,
            newMessage: maliciousMessage,
          )
          .toList(),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          contains('cannot contain function calls'),
        ),
      ),
    );
  });

  test('runAsync accepts user messages with function responses', () async {
    // A function response (not a call) is legitimate and must not be rejected.
    final Agent agent = Agent(name: 'test_agent', model: _NoopModel());
    final InMemoryRunner runner = InMemoryRunner(agent: agent);
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'user_1',
      sessionId: 'session_accept',
    );

    final Content responseMessage = Content(
      role: 'user',
      parts: <Part>[
        Part(
          functionResponse: FunctionResponse(
            name: 'some_tool',
            id: 'call_1',
            response: <String, dynamic>{'result': 'ok'},
          ),
        ),
      ],
    );

    // Should not throw the function-call rejection.
    await runner
        .runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: responseMessage,
        )
        .toList();
  });
}
