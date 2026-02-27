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

class _CaptureModel extends BaseLlm {
  _CaptureModel() : super(model: 'capture-model');

  int callCount = 0;
  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount += 1;
    lastRequest = request;
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

class _CaptureGeminiModel extends BaseLlm {
  _CaptureGeminiModel() : super(model: 'gemini-2.5-flash');

  int callCount = 0;
  LlmRequest? lastRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount += 1;
    lastRequest = request;
    yield LlmResponse(content: Content.modelText('native schema response'));
  }
}

class _OutputSchemaModel extends BaseLlm {
  _OutputSchemaModel() : super(model: 'output-schema-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: 'set_model_response',
            args: <String, dynamic>{'answer': 'done'},
          ),
        ],
      ),
    );
  }
}

class _CodeExecutionLoopModel extends BaseLlm {
  _CodeExecutionLoopModel() : super(model: 'code-execution-loop');

  int callCount = 0;
  LlmRequest? secondRequest;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    callCount += 1;
    if (callCount == 1) {
      yield LlmResponse(
        content: Content.modelText('Run command:\n```sh\necho hello\n```'),
      );
      return;
    }

    secondRequest = request;
    final String mergedContext = request.contents
        .expand((Content content) => content.parts)
        .map((Part part) => part.text ?? '')
        .join('\n');
    if (mergedContext.contains('Code execution result:') &&
        mergedContext.contains('hello')) {
      yield LlmResponse(content: Content.modelText('final: hello observed'));
      return;
    }
    yield LlmResponse(content: Content.modelText('final: missing result'));
  }
}

class _AuthRequiredToolset extends BaseToolset {
  bool getToolsCalled = false;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    getToolsCalled = true;
    return <BaseTool>[];
  }

  @override
  AuthConfig? getAuthConfig() {
    return AuthConfig(
      authScheme: 'oauth2_authorization_code',
      rawAuthCredential: AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(clientId: 'client-id', clientSecret: 'secret'),
      ),
      credentialKey: 'toolset-auth-key',
    );
  }
}

class _MalformedAuthToolset extends BaseToolset {
  bool getToolsCalled = false;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    getToolsCalled = true;
    return <BaseTool>[];
  }

  @override
  AuthConfig? getAuthConfig() {
    return AuthConfig(
      authScheme: 'oauth2_authorization_code',
      rawAuthCredential: AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(),
      ),
      credentialKey: 'toolset-auth-invalid',
    );
  }
}

Future<List<Event>> _collect(Stream<Event> stream) => stream.toList();

void main() {
  test(
    'request confirmation processor resumes tool with user decision',
    () async {
      String dangerousTool({required String value}) => 'approved:$value';

      final Agent agent = Agent(
        name: 'root_agent',
        model: _NoopModel(),
        tools: <Object>[
          FunctionTool(
            func: dangerousTool,
            name: 'dangerous_tool',
            requireConfirmation: true,
          ),
        ],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      final Session session = Session(
        id: 's_confirm',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_confirm',
            author: 'root_agent',
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'dangerous_tool',
                  id: 'tool_call_1',
                  args: <String, dynamic>{'value': 'x'},
                ),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_confirm',
            author: 'root_agent',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: requestConfirmationFunctionCallName,
                  id: 'confirm_req_1',
                  args: <String, dynamic>{
                    'originalFunctionCall': <String, dynamic>{
                      'name': 'dangerous_tool',
                      'id': 'tool_call_1',
                      'args': <String, dynamic>{'value': 'x'},
                    },
                    'toolConfirmation': <String, dynamic>{'hint': 'approve?'},
                  },
                ),
              ],
            ),
          ),
          Event(
            invocationId: 'inv_confirm',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: requestConfirmationFunctionCallName,
                  id: 'confirm_req_1',
                  response: <String, dynamic>{'confirmed': true},
                ),
              ],
            ),
          ),
        ],
      );

      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_confirm',
        agent: agent,
        session: session,
      );

      final RequestConfirmationLlmRequestProcessor processor =
          RequestConfirmationLlmRequestProcessor();
      final List<Event> resumedEvents = await processor
          .runAsync(invocationContext, LlmRequest())
          .toList();

      expect(resumedEvents, hasLength(1));
      final List<FunctionResponse> responses = resumedEvents.first
          .getFunctionResponses();
      expect(responses, hasLength(1));
      expect(responses.first.name, 'dangerous_tool');
      expect(responses.first.id, 'tool_call_1');
      expect(responses.first.response['result'], 'approved:x');
    },
  );

  test(
    'single flow request processors populate model and instructions',
    () async {
      final _CaptureModel model = _CaptureModel();
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        instruction: 'dynamic instruction',
        globalInstruction: 'global instruction',
        staticInstruction: 'static instruction',
        outputSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'answer': <String, dynamic>{'type': 'string'},
          },
        },
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_instruction',
      );

      await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hello'),
        ),
      );

      expect(model.callCount, 1);
      final LlmRequest? request = model.lastRequest;
      expect(request, isNotNull);
      expect(request!.model, 'capture-model');
      expect(request.config.responseSchema, isNotNull);
      final String systemInstruction = request.config.systemInstruction ?? '';
      expect(systemInstruction, contains('global instruction'));
      expect(systemInstruction, contains('static instruction'));
      expect(systemInstruction, contains('dynamic instruction'));
      expect(
        systemInstruction,
        contains('You are an agent. Your internal name is "root_agent".'),
      );
    },
  );

  test('basic processor mirrors runConfig into liveConnectConfig', () async {
    final _CaptureModel model = _CaptureModel();
    final Agent agent = Agent(
      name: 'root_agent',
      model: model,
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );

    final InMemoryRunner runner = InMemoryRunner(agent: agent);
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'user_1',
      sessionId: 's_live_cfg',
    );

    await _collect(
      runner.runAsync(
        userId: 'user_1',
        sessionId: session.id,
        newMessage: Content.userText('hello'),
        runConfig: RunConfig(
          responseModalities: <String>['AUDIO'],
          speechConfig: <String, Object?>{'voice': 'alloy'},
          outputAudioTranscription: <String, Object?>{'enabled': true},
          inputAudioTranscription: <String, Object?>{'enabled': true},
          realtimeInputConfig: <String, Object?>{'chunkMs': 100},
          enableAffectiveDialog: true,
          proactivity: <String, Object?>{'mode': 'auto'},
          sessionResumption: <String, Object?>{'enabled': true},
          contextWindowCompression: <String, Object?>{'enabled': true},
        ),
      ),
    );

    final LlmRequest request = model.lastRequest!;
    expect(request.liveConnectConfig.responseModalities, <String>['AUDIO']);
    expect(request.liveConnectConfig.speechConfig, isNotNull);
    expect(request.liveConnectConfig.outputAudioTranscription, isNotNull);
    expect(request.liveConnectConfig.inputAudioTranscription, isNotNull);
    expect(request.liveConnectConfig.realtimeInputConfig, isNotNull);
    expect(request.liveConnectConfig.enableAffectiveDialog, isTrue);
    expect(request.liveConnectConfig.proactivity, isNotNull);
    expect(request.liveConnectConfig.sessionResumption, isNotNull);
    expect(request.liveConnectConfig.contextWindowCompression, isNotNull);
  });

  test(
    'toolset auth is resolved before listing tools and yields auth event',
    () async {
      final _CaptureModel model = _CaptureModel();
      final _AuthRequiredToolset toolset = _AuthRequiredToolset();
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[toolset],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_toolset_auth',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hello'),
        ),
      );

      expect(model.callCount, 0);
      expect(toolset.getToolsCalled, isFalse);
      expect(events, hasLength(1));
      final List<FunctionCall> calls = events.first.getFunctionCalls();
      expect(calls, hasLength(1));
      expect(calls.first.name, requestEucFunctionCallName);
      expect(
        '${calls.first.args['function_call_id']}',
        startsWith(toolsetAuthCredentialIdPrefix),
      );
    },
  );

  test(
    'toolset auth resolution skips malformed auth request configs without blocking model execution',
    () async {
      final _CaptureModel model = _CaptureModel();
      final _MalformedAuthToolset toolset = _MalformedAuthToolset();
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        tools: <Object>[toolset],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_toolset_auth_invalid',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('hello'),
        ),
      );

      expect(model.callCount, 1);
      expect(toolset.getToolsCalled, isTrue);
      final List<FunctionCall> functionCalls = events
          .expand((Event event) => event.getFunctionCalls())
          .toList();
      expect(
        functionCalls.where(
          (FunctionCall call) => call.name == requestEucFunctionCallName,
        ),
        isEmpty,
      );
    },
  );

  test(
    'output schema with tools uses native response schema on Vertex Gemini 2+',
    () async {
      String noopTool({required String query}) => query;

      final _CaptureGeminiModel model = _CaptureGeminiModel();
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        outputSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'answer': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['answer'],
        },
        tools: <Object>[FunctionTool(func: noopTool, name: 'noop_tool')],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_output_schema_vertex_native',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('answer this'),
        ),
      );

      expect(model.callCount, 1);
      final LlmRequest request = model.lastRequest!;
      expect(request.config.responseSchema, isNotNull);
      expect(request.config.responseMimeType, 'application/json');

      final List<String> toolNames =
          request.config.tools
              ?.expand(
                (ToolDeclaration declaration) =>
                    declaration.functionDeclarations,
              )
              .map((FunctionDeclaration declaration) => declaration.name)
              .toList() ??
          <String>[];
      expect(toolNames, contains('noop_tool'));
      expect(toolNames, isNot(contains('set_model_response')));

      final String systemInstruction = request.config.systemInstruction ?? '';
      expect(systemInstruction, isNot(contains('set_model_response')));
      expect(
        events.any(
          (Event event) => event.getFunctionCalls().any(
            (FunctionCall call) => call.name == 'set_model_response',
          ),
        ),
        isFalse,
      );
    },
    skip: !isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI')
        ? 'requires GOOGLE_GENAI_USE_VERTEXAI=true'
        : false,
  );

  test(
    'output schema processor converts set_model_response into final text event',
    () async {
      String noopTool({required String query}) => query;

      final Agent agent = Agent(
        name: 'root_agent',
        model: _OutputSchemaModel(),
        outputSchema: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'answer': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['answer'],
        },
        tools: <Object>[FunctionTool(func: noopTool, name: 'noop_tool')],
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_output_schema',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('answer this'),
        ),
      );

      expect(events.length, greaterThanOrEqualTo(3));
      expect(events[0].getFunctionCalls().first.name, 'set_model_response');
      expect(events[1].getFunctionResponses().first.name, 'set_model_response');
      expect(events[2].content?.parts.first.text, contains('"answer":"done"'));
    },
  );

  test(
    'context cache and interactions processors fill request cache fields',
    () async {
      final Agent agent = Agent(
        name: 'root_agent',
        model: _NoopModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final Session session = Session(
        id: 's_cache',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'prev_invocation',
            author: 'root_agent',
            interactionId: 'interaction_123',
            usageMetadata: <String, Object?>{'prompt_token_count': 42},
            cacheMetadata: <String, Object?>{
              'cache_name': 'cache_a',
              'invocations_used': 3,
            },
          ),
        ],
      );
      final InvocationContext invocationContext = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'new_invocation',
        agent: agent,
        session: session,
        contextCacheConfig: <String, Object?>{'enabled': true},
      );
      final LlmRequest request = LlmRequest();

      await ContextCacheRequestProcessor()
          .runAsync(invocationContext, request)
          .toList();
      await InteractionsRequestProcessor()
          .runAsync(invocationContext, request)
          .toList();

      expect(request.cacheConfig, isA<Map<String, Object?>>());
      expect(request.cacheMetadata, isA<Map<String, dynamic>>());
      expect(request.cacheableContentsTokenCount, 42);
      expect(request.previousInteractionId, 'interaction_123');

      final Map<String, dynamic> metadata =
          request.cacheMetadata! as Map<String, dynamic>;
      expect(metadata['invocations_used'], 4);
    },
  );

  test('single flow includes code execution processors', () {
    final SingleFlow flow = SingleFlow();
    expect(
      flow.requestProcessors.any(
        (BaseLlmRequestProcessor processor) =>
            processor is CodeExecutionRequestProcessor,
      ),
      isTrue,
    );
    expect(
      flow.responseProcessors.any(
        (BaseLlmResponseProcessor processor) =>
            processor is CodeExecutionResponseProcessor,
      ),
      isTrue,
    );
  });

  test(
    'code execution processor runs fenced command and continues loop',
    () async {
      final _CodeExecutionLoopModel model = _CodeExecutionLoopModel();
      final Agent agent = Agent(
        name: 'root_agent',
        model: model,
        codeExecutor: UnsafeLocalCodeExecutor(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'user_1',
        sessionId: 's_code_exec_loop',
      );

      final List<Event> events = await _collect(
        runner.runAsync(
          userId: 'user_1',
          sessionId: session.id,
          newMessage: Content.userText('please run command'),
        ),
      );

      expect(model.callCount, 2);
      expect(
        events.any((Event event) => event.hasTrailingCodeExecutionResult()),
        isTrue,
      );
      expect(
        events.any(
          (Event event) =>
              event.content?.parts.first.text == 'final: hello observed',
        ),
        isTrue,
      );
    },
  );
}
