import 'dart:async';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/models/gemini_rest_api_client.dart';
import 'package:test/test.dart';

class _TestFlow extends BaseLlmFlow {}

class _NoopIngress extends LiveIngress {
  const _NoopIngress();

  @override
  Stream<IngressEvent> call(Stream<InlineData> audio) =>
      const Stream<IngressEvent>.empty();
}

class _NoopEgress extends LiveEgress {
  const _NoopEgress();

  @override
  Stream<EgressEvent> call(
    Stream<String> text, {
    required CancelSignal cancel,
  }) => const Stream<EgressEvent>.empty();
}

class _RecordingBaseLlm extends BaseLlm {
  _RecordingBaseLlm({
    required super.model,
    this.errorToThrow,
  });

  final Object? errorToThrow;
  LlmRequest? seenRequest;
  List<bool> seenTransientFlags = <bool>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    seenRequest = request;
    seenTransientFlags = <bool>[
      for (final Content c in request.contents)
        isTransientUserContent(request, c),
    ];
    if (errorToThrow != null) {
      // Mutate request before failing to verify snapshot rollback.
      request.contents.add(Content.userText('mutated by failed model'));
      request.setTransientUserContents(const <Content>[]);
      throw errorToThrow!;
    }
    yield LlmResponse(content: Content.modelText('ok from $model'));
  }
}

InvocationContext _createInvocationContext({
  required BaseAgent agent,
  LiveRequestQueue? liveRequestQueue,
  RunConfig? runConfig,
}) {
  return InvocationContext(
    invocationId: 'inv-nov24',
    agent: agent,
    session: Session(
      id: 'sess-nov24',
      appName: 'app-nov24',
      userId: 'user-nov24',
    ),
    sessionService: InMemorySessionService(),
    liveRequestQueue: liveRequestQueue,
    runConfig: runConfig,
  );
}

CallbackContext _createCallbackContext(BaseAgent agent) {
  return CallbackContext(_createInvocationContext(agent: agent));
}

String _addedTool() => 'added';

void main() {
  group('17c4a10af: live user input screening copies config and tools', () {
    test(
      'screenLiveUserContent does not mutate live LlmRequest config or tools',
      () async {
        final _TestFlow flow = _TestFlow();
        final ToolDeclaration toolDecl = ToolDeclaration(
          functionDeclarations: <FunctionDeclaration>[
            FunctionDeclaration(name: 'lookup', description: 'Lookup data'),
          ],
        );
        final FunctionTool lookupTool = FunctionTool(
          func: () => 'ok',
          name: 'lookup',
        );
        final LlmRequest liveRequest = LlmRequest(
          model: 'gemini-2.5-flash',
          config: GenerateContentConfig(
            tools: <ToolDeclaration>[toolDecl],
            stopSequences: <String>['STOP'],
            labels: <String, String>{'env': 'live'},
            httpOptions: HttpOptions(headers: <String, String>{'x-a': '1'}),
          ),
          toolsDict: <String, BaseTool>{'lookup': lookupTool},
        );

        final LlmAgent agent = LlmAgent(
          name: 'live_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
          beforeModelCallback:
              (CallbackContext callbackContext, LlmRequest request) async {
                request.config.systemInstruction = 'changed';
                request.config.stopSequences.add('EXTRA');
                request.config.labels['mutated'] = 'yes';
                request.config.httpOptions?.headers['x-b'] = '2';
                request.appendTools(<BaseTool>[
                  FunctionTool(func: _addedTool, name: 'added_tool'),
                ]);
                request.config.tools?.clear();
                request.toolsDict.clear();
                return null;
              },
        );

        final Event? blocked = await flow.screenLiveUserContent(
          _createInvocationContext(agent: agent),
          Content.userText('hello live'),
          liveRequest,
        );

        expect(blocked, isNull);
        expect(liveRequest.config.systemInstruction, isNull);
        expect(liveRequest.config.stopSequences, equals(<String>['STOP']));
        expect(liveRequest.config.labels, equals(<String, String>{'env': 'live'}));
        expect(
          liveRequest.config.httpOptions?.headers,
          equals(<String, String>{'x-a': '1'}),
        );
        expect(liveRequest.config.tools, hasLength(1));
        expect(
          liveRequest.config.tools!.first.functionDeclarations
              .map((FunctionDeclaration d) => d.name)
              .toList(),
          equals(<String>['lookup']),
        );
        expect(liveRequest.toolsDict.keys.toList(), equals(<String>['lookup']));
      },
    );

    test(
      'screenLiveUserContent returns blocked event when callback short-circuits',
      () async {
        final _TestFlow flow = _TestFlow();
        final LlmAgent agent = LlmAgent(
          name: 'live_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
          beforeModelCallback:
              (CallbackContext callbackContext, LlmRequest request) async {
                return LlmResponse(content: Content.modelText('Blocked!'));
              },
        );
        final Event? blocked = await flow.screenLiveUserContent(
          _createInvocationContext(agent: agent),
          Content.userText('bad input'),
          LlmRequest(model: 'gemini-2.5-flash'),
        );

        expect(blocked, isNotNull);
        expect(blocked!.turnComplete, isTrue);
        expect(blocked.content?.parts.first.text, equals('Blocked!'));
      },
    );

    test(
      'BasicLlmRequestProcessor copies request-scoped config fields',
      () async {
        final GenerateContentConfig agentConfig = GenerateContentConfig(
          labels: <String, String>{'a': '1'},
          stopSequences: <String>['END'],
        );
        final LlmAgent agent = LlmAgent(
          name: 'basic_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
          generateContentConfig: agentConfig,
        );
        final LlmRequest request = LlmRequest();
        await BasicLlmRequestProcessor()
            .runAsync(_createInvocationContext(agent: agent), request)
            .drain<void>();

        request.config.labels['b'] = '2';
        request.config.stopSequences.add('OTHER');

        expect(agentConfig.labels, equals(<String, String>{'a': '1'}));
        expect(agentConfig.stopSequences, equals(<String>['END']));
      },
    );
  });

  group('9c22a89fe: LlmRequest transient user content tracking', () {
    test(
      'tracks inserted transient user contents and skips static prefix',
      () {
        final LlmRequest request = LlmRequest(
          contents: <Content>[Content.userText('hello')],
          hasStaticInstruction: true,
        );

        // First call with hasStaticInstruction places static prefix at 0;
        // must NOT be marked transient.
        request.insertTransientUserContent(<Content>[
          Content.userText('static prefix'),
        ]);
        expect(request.contents, hasLength(2));
        expect(isTransientUserContent(request, request.contents[0]), isFalse);
        expect(isTransientUserContent(request, request.contents[1]), isFalse);

        // Second call inserts transient instruction before active user turn.
        request.insertTransientUserContent(<Content>[
          Content.userText('dynamic tool instruction'),
        ]);
        expect(request.contents, hasLength(3));
        expect(isTransientUserContent(request, request.contents[0]), isFalse);
        expect(isTransientUserContent(request, request.contents[1]), isTrue);
        expect(isTransientUserContent(request, request.contents[2]), isFalse);
        expect(
          lastNonTransientContent(request)?.parts.first.text,
          equals('hello'),
        );
      },
    );

    test('lastNonTransientContent skips trailing transient content', () {
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content.userText('question'),
          Content.modelText('answer'),
        ],
      );
      request.insertTransientUserContent(<Content>[
        Content.userText('transient instructions'),
      ]);

      expect(request.contents.last.role, equals('user'));
      expect(isTransientUserContent(request, request.contents.last), isTrue);
      expect(
        lastNonTransientContent(request)?.role,
        equals('model'),
      );
    });

    test('sanitizedForModelCall preserves transient identities', () {
      final LlmRequest request = LlmRequest(
        contents: <Content>[Content.userText('real user')],
      );
      request.insertTransientUserContent(<Content>[
        Content.userText('transient'),
      ]);

      final LlmRequest cloned = request.sanitizedForModelCall();
      expect(cloned.contents, hasLength(2));
      expect(isTransientUserContent(cloned, cloned.contents[0]), isTrue);
      expect(isTransientUserContent(cloned, cloned.contents[1]), isFalse);
    });
  });

  group('9c22a89fe: BaseLlm, AnthropicLlm, and LiteLlm transient handling', () {
    test(
      'BaseLlm.maybeAppendUserContent appends fallback when only transient content exists',
      () {
        final _RecordingBaseLlm llm = _RecordingBaseLlm(model: 'test-model');
        final LlmRequest request = LlmRequest();
        request.insertTransientUserContent(<Content>[
          Content.userText('tool hint'),
        ]);

        llm.maybeAppendUserContent(request);

        expect(request.contents, hasLength(2));
        expect(
          request.contents.last.parts.first.text,
          equals('Handle the requests as specified in the System Instruction.'),
        );
      },
    );

    test(
      'BaseLlm.maybeAppendUserContent appends continuation when model turn is followed by transient content',
      () {
        final _RecordingBaseLlm llm = _RecordingBaseLlm(model: 'test-model');
        final LlmRequest request = LlmRequest(
          contents: <Content>[
            Content.userText('hi'),
            Content.modelText('working'),
          ],
        );
        request.insertTransientUserContent(<Content>[
          Content.userText('tool hint'),
        ]);

        llm.maybeAppendUserContent(request);

        expect(request.contents, hasLength(4));
        expect(
          request.contents.last.parts.first.text,
          contains('Continue processing previous requests as instructed.'),
        );
      },
    );

    test(
      'AnthropicLlm appends continuation prompt when model turn is followed by transient user content',
      () async {
        Map<String, Object?>? capturedPayload;
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-5-20250929',
          apiInvoker: ({
            required Map<String, Object?> request,
            required bool stream,
          }) async {
            capturedPayload = request;
            return <Map<String, Object?>>[
              <String, Object?>{
                'id': 'msg_1',
                'type': 'message',
                'role': 'assistant',
                'model': 'claude-sonnet-4-5-20250929',
                'content': <Map<String, Object?>>[
                  <String, Object?>{'type': 'text', 'text': 'done'},
                ],
                'stop_reason': 'end_turn',
                'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
              },
            ];
          },
        );

        final LlmRequest request = LlmRequest(
          contents: <Content>[
            Content.userText('start'),
            Content.modelText('intermediate'),
          ],
        );
        request.insertTransientUserContent(<Content>[
          Content.userText('dynamic instructions'),
        ]);

        await llm.generateContent(request).toList();

        expect(capturedPayload, isNotNull);
        final List<Object?> messages =
            capturedPayload!['messages']! as List<Object?>;
        expect(messages, hasLength(4));
        final Map<String, Object?> lastMessage =
            messages.last! as Map<String, Object?>;
        expect(lastMessage['role'], equals('user'));
        final List<Object?> lastBlocks =
            lastMessage['content']! as List<Object?>;
        expect(
          (lastBlocks.first! as Map<String, Object?>)['text'],
          contains('Continue processing previous requests as instructed.'),
        );
      },
    );

    test(
      'AnthropicLlm appends empty-messages fallback when only transient user content exists',
      () async {
        Map<String, Object?>? capturedPayload;
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-5-20250929',
          apiInvoker: ({
            required Map<String, Object?> request,
            required bool stream,
          }) async {
            capturedPayload = request;
            return <Map<String, Object?>>[
              <String, Object?>{
                'id': 'msg_2',
                'type': 'message',
                'role': 'assistant',
                'model': 'claude-sonnet-4-5-20250929',
                'content': <Map<String, Object?>>[
                  <String, Object?>{'type': 'text', 'text': 'done'},
                ],
                'stop_reason': 'end_turn',
                'usage': <String, Object?>{'input_tokens': 1, 'output_tokens': 1},
              },
            ];
          },
        );

        final LlmRequest request = LlmRequest();
        request.insertTransientUserContent(<Content>[
          Content.userText('dynamic instructions'),
        ]);

        await llm.generateContent(request).toList();

        final List<Object?> messages =
            capturedPayload!['messages']! as List<Object?>;
        expect(messages, hasLength(2));
        final Map<String, Object?> lastMessage =
            messages.last! as Map<String, Object?>;
        final List<Object?> lastBlocks =
            lastMessage['content']! as List<Object?>;
        expect(
          (lastBlocks.first! as Map<String, Object?>)['text'],
          equals('Handle the requests as specified in the System Instruction.'),
        );
      },
    );

    test(
      'LiteLlm ignores transient user content when appending fallback user content',
      () async {
        Map<String, Object?>? capturedPayload;
        final LiteLlm llm = LiteLlm(
          model: 'openai/gpt-4o',
          completionsInvoker: ({
            required Map<String, Object?> payload,
            required bool stream,
          }) async {
            capturedPayload = payload;
            return <Map<String, Object?>>[
              <String, Object?>{
                'model': 'openai/gpt-4o',
                'choices': <Map<String, Object?>>[
                  <String, Object?>{
                    'message': <String, Object?>{
                      'role': 'assistant',
                      'content': 'ok',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              },
            ];
          },
        );

        final LlmRequest request = LlmRequest();
        request.insertTransientUserContent(<Content>[
          Content.userText('transient only'),
        ]);

        await llm.generateContent(request).toList();

        final List<Object?> messages =
            capturedPayload!['messages']! as List<Object?>;
        expect(messages, hasLength(2));
        expect(
          (messages.last! as Map<String, Object?>)['content'],
          equals('Handle the requests as specified in the System Instruction.'),
        );
      },
    );

    test('LiteLlm dynamic instruction routing provider allowlist', () {
      // Allowlisted providers
      expect(
        LiteLlm(model: 'openai/gpt-4o').supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(model: 'azure/gpt-4o').supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'anthropic/claude-3-5-sonnet',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'litellm_proxy/openai/gpt-4o',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'bedrock_converse/claude-3-5-sonnet',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'vertex_ai/claude-3-5-sonnet',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'vertex_ai_beta/gemini-2.5-flash',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'gemini/gemini-2.5-flash',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );
      expect(
        LiteLlm(
          model: 'litellm_proxy/custom-deployment',
          customProvider: 'openai',
        ).supportsDynamicInstructionRouting,
        isTrue,
      );

      // Non-allowlisted / strict template providers
      expect(
        LiteLlm(
          model: 'mistral/mistral-large-latest',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(model: 'perplexity/sonar-pro').supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(
          model: 'deepseek/deepseek-reasoner',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(
          model: 'ollama_chat/llama3.2',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(
          model: 'bedrock/meta.llama3-70b-instruct-v1:0',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(
          model: 'vertex_ai/meta/llama-3.1-405b',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
      expect(
        LiteLlm(
          model: 'gemini/gemma-3-27b-it',
        ).supportsDynamicInstructionRouting,
        isFalse,
      );
    });
  });

  group('9c22a89fe: dynamic instruction routing gating and model delegates', () {
    test(
      'finalizeDynamicInstructions falls back to systemInstruction in live sessions',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'live_agent',
          model: Gemini(model: 'gemini-2.5-flash'),
        );
        final LlmRequest request = LlmRequest(
          contents: <Content>[Content.userText('hello')],
        )..appendDynamicInstructions(<String>['Use tool X carefully.']);

        await finalizeDynamicInstructions(
          _createInvocationContext(
            agent: agent,
            liveRequestQueue: LiveRequestQueue(),
          ),
          request,
        );

        expect(request.config.systemInstruction, contains('Use tool X carefully.'));
        expect(request.contents, hasLength(1));
      },
    );

    test(
      'finalizeDynamicInstructions falls back to systemInstruction when supportCfc is true',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'cfc_agent',
          model: Gemini(model: 'gemini-2.5-flash'),
        );
        final LlmRequest request = LlmRequest(
          contents: <Content>[Content.userText('hello')],
        )..appendDynamicInstructions(<String>['CFC tool instruction.']);

        await finalizeDynamicInstructions(
          _createInvocationContext(
            agent: agent,
            runConfig: RunConfig(supportCfc: true),
          ),
          request,
        );

        expect(request.config.systemInstruction, contains('CFC tool instruction.'));
        expect(request.contents, hasLength(1));
      },
    );

    test(
      'finalizeDynamicInstructions falls back to systemInstruction for Gemini Interactions API and strict LiteLLM',
      () async {
        final LlmAgent interactionsAgent = LlmAgent(
          name: 'interactions_agent',
          model: Gemini(model: 'gemini-2.5-flash', useInteractionsApi: true),
        );
        final LlmRequest interactionsReq = LlmRequest(
          contents: <Content>[Content.userText('hello')],
        )..appendDynamicInstructions(<String>['Interactions hint.']);

        await finalizeDynamicInstructions(
          _createInvocationContext(agent: interactionsAgent),
          interactionsReq,
        );
        expect(
          interactionsReq.config.systemInstruction,
          contains('Interactions hint.'),
        );
        expect(interactionsReq.contents, hasLength(1));

        final LlmAgent mistralAgent = LlmAgent(
          name: 'mistral_agent',
          model: LiteLlm(model: 'mistral/mistral-large-latest'),
        );
        final LlmRequest mistralReq = LlmRequest(
          contents: <Content>[Content.userText('hello')],
        )..appendDynamicInstructions(<String>['Mistral hint.']);

        await finalizeDynamicInstructions(
          _createInvocationContext(agent: mistralAgent),
          mistralReq,
        );
        expect(mistralReq.config.systemInstruction, contains('Mistral hint.'));
        expect(mistralReq.contents, hasLength(1));
      },
    );

    test(
      'CascadeLive delegates supportsDynamicInstructionRouting to underlying model',
      () {
        final CascadeLive interactionsCascade = CascadeLive(
          model: Gemini(model: 'gemini-2.5-flash', useInteractionsApi: true),
          stt: const _NoopIngress(),
          tts: const _NoopEgress(),
        );
        final CascadeLive normalCascade = CascadeLive(
          model: Gemini(model: 'gemini-2.5-flash'),
          stt: const _NoopIngress(),
          tts: const _NoopEgress(),
        );

        expect(interactionsCascade.supportsDynamicInstructionRouting, isFalse);
        expect(normalCascade.supportsDynamicInstructionRouting, isTrue);
      },
    );

    test(
      'FallbackModel gates routing on all models and preserves transient identities across rollback',
      () async {
        final FallbackModel allSupported = FallbackModel(
          models: <Object>[
            Gemini(model: 'gemini-2.5-flash'),
            'openai/gpt-4o',
          ],
        );
        expect(allSupported.supportsDynamicInstructionRouting, isTrue);

        final FallbackModel backupUnsupported = FallbackModel(
          models: <Object>[
            Gemini(model: 'gemini-2.5-flash'),
            'mistral/mistral-large-latest',
          ],
        );
        expect(backupUnsupported.supportsDynamicInstructionRouting, isFalse);

        final FallbackModel primaryUnsupported = FallbackModel(
          models: <Object>[
            Gemini(model: 'gemini-2.5-flash', useInteractionsApi: true),
            'openai/gpt-4o',
          ],
        );
        expect(primaryUnsupported.supportsDynamicInstructionRouting, isFalse);

        final _RecordingBaseLlm failingPrimary = _RecordingBaseLlm(
          model: 'primary',
          errorToThrow: GeminiRestApiException(503, 'temporarily unavailable'),
        );
        final _RecordingBaseLlm succeedingBackup = _RecordingBaseLlm(
          model: 'backup',
        );
        final FallbackModel fallback = FallbackModel(
          models: <Object>[failingPrimary, succeedingBackup],
        );

        final LlmRequest request = LlmRequest(
          contents: <Content>[Content.userText('real user prompt')],
        );
        request.insertTransientUserContent(<Content>[
          Content.userText('transient tool instruction'),
        ]);

        final List<LlmResponse> responses =
            await fallback.generateContent(request).toList();
        expect(responses, hasLength(1));
        expect(
          succeedingBackup.seenTransientFlags,
          equals(<bool>[true, false]),
        );
        expect(succeedingBackup.seenRequest!.contents, hasLength(2));
      },
    );
  });

  group('9c22a89fe: plugins ignore transient user contents', () {
    test(
      'ModelArmorPlugin skips transient user contents and screens the real user prompt',
      () async {
        final InMemoryModelArmorClient client = InMemoryModelArmorClient(
          blockedSubstrings: <String>['secret'],
        );
        final ModelArmorPlugin plugin = ModelArmorPlugin(
          config: ModelArmorConfig(
            promptTemplateName:
                'projects/p/locations/us-central1/templates/prompt-tmpl',
          ),
          client: client,
        );
        final LlmAgent agent = LlmAgent(
          name: 'armor_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
        );
        final LlmRequest request = LlmRequest(
          contents: <Content>[
            Content.userText('tell me the secret'),
            Content.modelText('calling tool'),
          ],
        );
        request.insertTransientUserContent(<Content>[
          Content.userText('benign dynamic instruction'),
        ]);

        final LlmResponse? response = await plugin.beforeModelCallback(
          callbackContext: _createCallbackContext(agent),
          llmRequest: request,
        );

        expect(response, isNotNull);
        expect(response!.customMetadata?['model_armor_blocked'], isTrue);
        expect(client.userPromptCalls, hasLength(1));
        expect(client.userPromptCalls.first.text, equals('tell me the secret'));
      },
    );

    test(
      'ContextFilterPlugin ignores transient user contents when counting invocations and preserves preceding transient content',
      () async {
        final ContextFilterPlugin plugin = ContextFilterPlugin(
          numInvocationsToKeep: 1,
        );
        final LlmAgent agent = LlmAgent(
          name: 'filter_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
        );
        final LlmRequest request = LlmRequest(
          contents: <Content>[
            Content.userText('turn 1 user'),
            Content.modelText('turn 1 model'),
            Content.userText('turn 2 user'),
          ],
        );
        // Inserts right before 'turn 2 user' (index 2).
        request.insertTransientUserContent(<Content>[
          Content.userText('dynamic instructions for turn 2'),
        ]);

        await plugin.beforeModelCallback(
          callbackContext: _createCallbackContext(agent),
          llmRequest: request,
        );

        expect(
          request.contents.map((Content c) => c.parts.first.text).toList(),
          equals(<String>['dynamic instructions for turn 2', 'turn 2 user']),
        );
      },
    );

    test(
      'MultimodalToolResultsPlugin attaches parts to last non-transient content in both retention modes',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'mm_agent',
          model: _RecordingBaseLlm(model: 'gemini-2.5-flash'),
        );

        // 1. Default (next_model_call) mode
        final MultimodalToolResultsPlugin defaultPlugin =
            MultimodalToolResultsPlugin();
        final CallbackContext defaultCtx = _createCallbackContext(agent);
        defaultCtx.state[partsReturnedByToolsStateKey] = <Part>[
          Part.text('attached artifact'),
        ];
        final LlmRequest defaultReq = LlmRequest(
          contents: <Content>[
            Content.userText('inspect image'),
            Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'load_img',
                  response: <String, dynamic>{'status': 'ok'},
                ),
              ],
            ),
          ],
        );
        defaultReq.insertTransientUserContent(<Content>[
          Content.userText('trailing transient instruction'),
        ]);

        await defaultPlugin.beforeModelCallback(
          callbackContext: defaultCtx,
          llmRequest: defaultReq,
        );

        expect(defaultReq.contents[1].parts, hasLength(2));
        expect(
          defaultReq.contents[1].parts.last.text,
          equals('attached artifact'),
        );
        expect(defaultReq.contents[2].parts, hasLength(1));

        // 2. Session retention mode
        final MultimodalToolResultsPlugin sessionPlugin =
            MultimodalToolResultsPlugin(retention: 'session');
        final CallbackContext sessionCtx = _createCallbackContext(agent);
        sessionCtx.state[sessionPartsReturnedByToolsStateKey] =
            <Map<String, Object?>>[
              <String, Object?>{'text': 'session artifact'},
            ];
        final LlmRequest sessionReq = LlmRequest(
          contents: <Content>[
            Content.userText('follow up'),
            Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'load_doc',
                  response: <String, dynamic>{'status': 'ok'},
                ),
              ],
            ),
          ],
        );
        sessionReq.insertTransientUserContent(<Content>[
          Content.userText('trailing transient instruction'),
        ]);

        await sessionPlugin.beforeModelCallback(
          callbackContext: sessionCtx,
          llmRequest: sessionReq,
        );

        expect(sessionReq.contents[1].parts, hasLength(2));
        expect(
          sessionReq.contents[1].parts.last.text,
          equals('session artifact'),
        );
        expect(sessionReq.contents[2].parts, hasLength(1));
      },
    );
  });
}
