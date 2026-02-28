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

void main() {
  test(
    'AuthLlmRequestProcessor stores auth response and resumes tool call',
    () async {
      Map<String, Object?> secureTool({ToolContext? toolContext}) {
        final String key = authResponseStateKey('cred_1');
        final Object? credential = toolContext?.state[key];
        if (credential is! AuthCredential) {
          return <String, Object?>{'ok': false};
        }
        return <String, Object?>{
          'ok': true,
          'token': credential.oauth2?.accessToken ?? '',
        };
      }

      final LlmAgent agent = LlmAgent(
        name: 'root_agent',
        model: _NoopModel(),
        tools: <Object>[
          FunctionTool(
            func: secureTool,
            name: 'secure_tool',
            description: 'Tool requiring auth',
          ),
        ],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'secure_tool',
                  id: 'tool_call_1',
                  args: <String, dynamic>{},
                ),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_1',
            author: 'root_agent',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'adk_request_credential',
                  id: 'auth_call_1',
                  args: <String, dynamic>{
                    'function_call_id': 'tool_call_1',
                    'auth_config': AuthConfig(
                      authScheme: 'oauth2',
                      credentialKey: 'cred_1',
                    ),
                  },
                ),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'adk_request_credential',
                  id: 'auth_call_1',
                  response: <String, Object?>{
                    'authScheme': 'oauth2',
                    'credentialKey': 'cred_1',
                    'exchangedAuthCredential': <String, Object?>{
                      'authType': 'oauth2',
                      'oauth2': <String, Object?>{
                        'accessToken': 'token-abc',
                        'id_token': 'id-token-xyz',
                      },
                    },
                  },
                ),
              ],
            ),
          ),
        ],
      );

      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_1',
        agent: agent,
        session: session,
      );

      final AuthLlmRequestProcessor processor = AuthLlmRequestProcessor();
      final List<Event> resumedEvents = await processor
          .runAsync(invocationContext, LlmRequest())
          .toList();

      expect(resumedEvents, hasLength(1));
      final Event resumed = resumedEvents.first;
      final List<FunctionResponse> responses = resumed.getFunctionResponses();
      expect(responses, hasLength(1));
      expect(responses.first.name, 'secure_tool');
      expect(responses.first.response['ok'], isTrue);
      expect(responses.first.response['token'], 'token-abc');

      final Object? saved = session.state[authResponseStateKey('cred_1')];
      expect(saved, isA<AuthCredential>());
      expect((saved as AuthCredential).oauth2?.accessToken, 'token-abc');
      expect(saved.oauth2?.idToken, 'id-token-xyz');
    },
  );

  test('LlmAgent llmFlow includes AuthLlmRequestProcessor', () {
    final LlmAgent agent = LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );

    final BaseLlmFlow flow = agent.llmFlow;
    expect(
      flow.requestProcessors.any(
        (BaseLlmRequestProcessor processor) =>
            processor is AuthLlmRequestProcessor,
      ),
      isTrue,
    );
  });
}
