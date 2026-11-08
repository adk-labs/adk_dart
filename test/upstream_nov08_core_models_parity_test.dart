import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _GatherNode extends BaseNode {
  _GatherNode({required super.name})
    : super(waitForOutput: true, rerunOnResume: false);

  final int batch = 2;
  final List<Object?> calls = <Object?>[];

  @override
  Future<Object?> run(WorkflowContext context, Object? nodeInput) async {
    calls.add(nodeInput);
    final List<Object?> seen = <Object?>[
      ...((context.state['seen'] as List?) ?? const <Object?>[]),
      nodeInput,
    ];
    context.state['seen'] = seen;
    if (seen.length % batch == 0) {
      return Event(
        invocationId: context.invocationContext?.invocationId ?? '',
        author: name,
        output: seen.sublist(seen.length - batch),
      );
    }
    return null;
  }
}

class _LapRouterNode extends BaseNode {
  _LapRouterNode({required super.name, this.laps = 3});

  final int laps;

  @override
  Future<Object?> run(WorkflowContext context, Object? nodeInput) async {
    final int lap = ((context.state['lap'] as int?) ?? 0) + 1;
    context.state['lap'] = lap;
    return Event(
      invocationId: context.invocationContext?.invocationId ?? '',
      author: name,
      output: lap,
      route: lap < laps ? 'loop' : 'stop',
    );
  }
}

class _SlowFakeExchanger extends BaseCredentialExchanger {
  _SlowFakeExchanger({
    required this.exchangeEntered,
    required this.allowFinish,
  });

  final Completer<void> exchangeEntered;
  final Completer<void> allowFinish;
  int callCount = 0;

  @override
  Future<ExchangeResult> exchange({
    required AuthCredential authCredential,
    String? authScheme,
  }) async {
    final String? existingToken = authCredential.oauth2?.accessToken;
    if (existingToken != null && existingToken.isNotEmpty) {
      return ExchangeResult(credential: authCredential, wasExchanged: false);
    }
    callCount += 1;
    if (!exchangeEntered.isCompleted) {
      exchangeEntered.complete();
    }
    await allowFinish.future;
    final AuthCredential exchanged = authCredential.copyWith();
    exchanged.oauth2 ??= OAuth2Auth();
    exchanged.oauth2!.accessToken = 'exchanged-access-token';
    exchanged.oauth2!.expiresIn = 3600;
    return ExchangeResult(credential: exchanged, wasExchanged: true);
  }
}

class _FakeGenAiApiClient {
  _FakeGenAiApiClient({
    required this.vertexai,
    this.project,
    this.location,
  });

  final bool vertexai;
  final String? project;
  final String? location;
}

class _FakeGenAiClient {
  _FakeGenAiClient(this._apiClient);

  // ignore: unused_field
  final _FakeGenAiApiClient _apiClient;

  _FakeGenAiApiClient get apiClient => _apiClient;
}

class _MinimalAgent extends BaseAgent {
  _MinimalAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

ToolDeclaration _sampleTool() {
  return ToolDeclaration(
    functionDeclarations: <FunctionDeclaration>[
      FunctionDeclaration(
        name: 'a_tool',
        description: 'Look up the weather in a city.',
        parameters: <String, dynamic>{
          'type': 'OBJECT',
          'properties': <String, dynamic>{
            'city': <String, dynamic>{'type': 'STRING'},
          },
        },
      ),
    ],
  );
}

LlmRequest _sampleRequest({GenerateContentConfig? config}) {
  return LlmRequest(
    model: 'gemini-2.5-flash',
    contents: <Content>[
      Content(role: 'user', parts: <Part>[Part.text('hi')]),
    ],
    config: config,
  );
}

GenerateContentConfig _fullVertexConfig() {
  return GenerateContentConfig(
    systemInstruction: 'You are a research agent.',
    tools: <ToolDeclaration>[_sampleTool()],
    toolConfig: LlmToolConfig(
      functionCallingConfig: FunctionCallingConfig(
        mode: FunctionCallingConfigMode.auto,
      ),
    ),
    safetySettings: <Object?>[
      <String, Object?>{
        'category': 'HARM_CATEGORY_HATE_SPEECH',
        'threshold': 'BLOCK_ONLY_HIGH',
      },
    ],
    cachedContent: 'projects/p/locations/us-central1/cachedContents/123',
    labels: <String, String>{'team': 'research'},
    httpOptions: HttpOptions(headers: <String, String>{'x-test': '1'}),
    automaticFunctionCalling: AutomaticFunctionCallingConfig(disable: true),
    shouldReturnHttpResponse: true,
    temperature: 0.2,
    topP: 0.9,
    topK: 40,
    candidateCount: 1,
    maxOutputTokens: 8192,
    stopSequences: <String>['STOP'],
    responseLogprobs: true,
    logprobs: 3,
    presencePenalty: 0.1,
    frequencyPenalty: 0.1,
    seed: 42,
    responseMimeType: 'application/json',
    responseSchema: <String, Object?>{
      'type': 'OBJECT',
      'properties': <String, Object?>{
        'answer': <String, Object?>{'type': 'STRING'},
      },
    },
    routingConfig: <String, Object?>{
      'autoMode': <String, Object?>{'modelRoutingPreference': 'BALANCED'},
    },
    modelSelectionConfig: <String, Object?>{
      'featureSelectionPreference': 'BALANCED',
    },
    responseModalities: <String>['TEXT'],
    mediaResolution: 'MEDIA_RESOLUTION_MEDIUM',
    speechConfig: <String, Object?>{
      'voiceConfig': <String, Object?>{
        'prebuiltVoiceConfig': <String, Object?>{'voiceName': 'Kore'},
      },
    },
    audioTimestamp: true,
    thinkingConfig: <String, Object?>{
      'includeThoughts': true,
      'thinkingBudget': 4096,
    },
    imageConfig: <String, Object?>{'aspectRatio': '1:1'},
    modelArmorConfig: <String, Object?>{
      'prompt_template_name': 'projects/p/locations/us-central1/templates/t',
    },
    serviceTier: 'standard',
    audioTranscriptionConfig: <String, Object?>{},
    continuationToken: Uint8List.fromList(utf8.encode('token')),
    automaticContinuation: true,
    generationOutputConfig: <String, Object?>{
      'outputUriPrefix': 'gs://bucket/prefix/',
    },
  );
}

void main() {
  group('1. version.dart (5c4fa9285)', () {
    test('adkVersion is bumped to 2.14.0', () {
      expect(adkVersion, '2.14.0');
    });
  });

  group('2. schema_utils, Event & LlmAgent validation aliases (72663e5f0)', () {
    test('topLevelInputKeys extracts field names, alias, and top-level validationAlias', () {
      final Map<String, Object?> fields = <String, Object?>{
        'plain': const FieldInfo(),
        'aliased': const FieldInfo(alias: 'by_alias'),
        'str_val': const FieldInfo(validationAlias: 'by_val_str'),
        'path_val': FieldInfo(
          validationAlias: AliasPath('nested_root', 'leaf'),
        ),
        'choices_val': FieldInfo(
          validationAlias: AliasChoices(
            'choice_a',
            AliasPath('choice_path_root', 'ignored_leaf'),
          ),
        ),
      };
      final Set<String> keys = topLevelInputKeys(fields);
      expect(
        keys,
        containsAll(<String>[
          'plain',
          'aliased',
          'by_alias',
          'str_val',
          'by_val_str',
          'path_val',
          'nested_root',
          'choices_val',
          'choice_a',
          'choice_path_root',
        ]),
      );
      expect(keys, isNot(contains('leaf')));
      expect(keys, isNot(contains('ignored_leaf')));
    });

    for (final String keyword in <String>[
      'message',
      'state',
      'route',
      'node_path',
    ]) {
      for (final String aliasKind in <String>[
        'string',
        'choices',
        'path',
        'choices_with_path',
      ]) {
        test(
          'Event subclass validation_alias ($aliasKind) takes convenience kwarg ($keyword)',
          () {
            late final Object alias;
            Object value = 'custom_value';
            if (aliasKind == 'string') {
              alias = keyword;
            } else if (aliasKind == 'choices') {
              alias = AliasChoices('other', keyword);
            } else if (aliasKind == 'path') {
              alias = AliasPath(keyword, 'value');
              value = <String, String>{'value': 'custom_value'};
            } else {
              alias = AliasChoices('other', AliasPath(keyword, 'value'));
              value = <String, String>{'value': 'custom_value'};
            }

            final Map<String, Object?> modelFields = <String, Object?>{
              'custom_value': FieldInfo(validationAlias: alias),
            };
            final Event event = Event(
              modelFields: modelFields,
              extraData: <String, Object?>{keyword: value},
              message: keyword == 'message' ? value : null,
              state: keyword == 'state' ? value : null,
              route: keyword == 'route' ? value : null,
              nodePath: keyword == 'node_path' && value is String ? value : null,
            );

            expect(event.customFields['custom_value'], 'custom_value');
            expect(event.content, isNull);
            expect(event.actions.stateDelta, isEmpty);
            expect(event.actions.route, isNull);
            expect(event.nodeInfo.path, '');
          },
        );
      }
    }

    test('Event nested validation_alias does not take top-level route', () {
      final Event event = Event(
        route: 'next',
        modelFields: <String, Object?>{
          'custom_value': FieldInfo(
            validationAlias: AliasPath('payload', 'route'),
          ),
        },
        extraData: <String, Object?>{
          'payload': <String, Object?>{'route': 'custom_value'},
        },
      );
      expect(event.customFields['custom_value'], 'custom_value');
      expect(event.actions.route, 'next');
    });

    test('Event validation_alias on route does not route workflow', () async {
      final BaseNode emitEvent = node(
        (WorkflowContext ctx, Object? input) => Event(
          route: 'domain_destination',
          output: 'ready',
          modelFields: <String, Object?>{
            'destination': const FieldInfo(validationAlias: 'route'),
          },
        ),
        name: 'emit_event',
      );
      final BaseNode consume = node(
        (WorkflowContext ctx, Object? input) => '$input processed',
        name: 'consume',
      );
      final Workflow wf = Workflow(
        name: 'wf',
        nodes: <BaseNode>[emitEvent, consume],
        edges: <Edge>[
          Edge(fromNode: START, toNode: emitEvent),
          Edge(fromNode: emitEvent, toNode: consume),
        ],
      );

      final WorkflowResult result = await wf.runWorkflow();
      expect(result.outputs['consume'], 'ready processed');
      expect(result.nodeStates['emit_event']?.route, isNull);
    });

    test('LlmAgent rejects misplaced GenerateContentConfig fields with helpful error', () {
      for (final MapEntry<String, Object?> entry in <String, Object?>{
        'temperature': 0.2,
        'top_p': 0.9,
        'max_output_tokens': 1024,
        'seed': 42,
        'stop_sequences': <String>['STOP'],
        'presence_penalty': 0.5,
        'frequency_penalty': 0.5,
      }.entries) {
        expect(
          () => LlmAgent.modelValidate(<String, Object?>{
            'name': 'test',
            entry.key: entry.value,
          }),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message,
              'message',
              allOf(
                contains("'${entry.key}' belongs on GenerateContentConfig"),
                contains('generate_content_config=types.GenerateContentConfig('),
              ),
            ),
          ),
        );
      }

      expect(
        () => LlmAgent.modelValidate(<String, Object?>{
          'name': 'test',
          'temperature': 0.2,
          'max_output_tokens': 1024,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            allOf(
              contains("'max_output_tokens', 'temperature' belong on GenerateContentConfig"),
              contains('max_output_tokens=1024, temperature=0.2'),
            ),
          ),
        ),
      );
    });

    for (final String aliasKind in <String>[
      'string',
      'choices',
      'path',
      'choices_with_path',
    ]) {
      test(
        'LlmAgent subclass validation_alias ($aliasKind) on temperature is not flagged as misplaced',
        () {
          late final Object alias;
          Object value = 0.5;
          if (aliasKind == 'string') {
            alias = 'temperature';
          } else if (aliasKind == 'choices') {
            alias = AliasChoices('temp', 'temperature');
          } else if (aliasKind == 'path') {
            alias = AliasPath('temperature', 'value');
            value = <String, Object?>{'value': 0.5};
          } else {
            alias = AliasChoices('temp', AliasPath('temperature', 'value'));
            value = <String, Object?>{'value': 0.5};
          }

          final LlmAgent agent = LlmAgent.modelValidate(
            <String, Object?>{'name': 'test', 'temperature': value},
            modelFields: <String, Object?>{
              'sampling_temp': FieldInfo(validationAlias: alias),
            },
          );
          expect(agent.customFields['sampling_temp'], 0.5);
        },
      );
    }

    test('LlmAgent nested validation_alias does not suppress misplaced top-level temperature', () {
      expect(
        () => LlmAgent.modelValidate(
          <String, Object?>{
            'name': 'test',
            'nested': <String, Object?>{'temperature': 0.5},
            'temperature': 0.2,
          },
          modelFields: <String, Object?>{
            'sampling_temp': FieldInfo(
              validationAlias: AliasPath('nested', 'temperature'),
            ),
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains("'temperature' belongs on GenerateContentConfig"),
          ),
        ),
      );
    });
  });

  group('3. FileArtifactService preserves line endings (1fa00445f)', () {
    for (final String text in <String>[
      'hello, world\n',
      'line1\r\nline2\r\n',
      'line1\rline2\r',
      'unix\nwindows\r\nclassic_mac\rend',
    ]) {
      test('round-trips text artifact with exact line endings: ${jsonEncode(text)}', () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'adk_file_artifact_eol_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final FileArtifactService service = FileArtifactService(tempDir.path);
        final Part artifact = Part.text(text);
        await service.saveArtifact(
          appName: 'app',
          userId: 'user',
          sessionId: 's1',
          filename: 'notes.txt',
          artifact: artifact,
        );

        final Part? loaded = await service.loadArtifact(
          appName: 'app',
          userId: 'user',
          sessionId: 's1',
          filename: 'notes.txt',
        );
        expect(loaded, isNotNull);
        expect(loaded!.text, equals(text));
      });
    }
  });

  group('4. AuthHandler.getAuthResponseAsync & CredentialManager non-blocking exchange (f8ba96a25)', () {
    test('redeeming an OAuth code from session state keeps the event loop responsive', () async {
      final String authScheme = jsonEncode(<String, Object?>{
        'type': 'oauth2',
        'flows': <String, Object?>{
          'authorizationCode': <String, Object?>{
            'authorizationUrl': 'https://example.com/oauth/authorize',
            'tokenUrl': 'https://example.com/oauth/token',
            'scopes': <String, String>{'read': 'Read access'},
          },
        },
      });
      final AuthConfig authConfig = AuthConfig(
        authScheme: authScheme,
        rawAuthCredential: AuthCredential(
          authType: AuthCredentialType.oauth2,
          oauth2: OAuth2Auth(
            clientId: 'test_client_id',
            clientSecret: 'test_client_secret',
            redirectUri: 'https://example.com/callback',
          ),
        ),
      );

      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'test_app',
        userId: 'user_a',
      );
      final InvocationContext invocationContext = InvocationContext(
        sessionService: sessionService,
        invocationId: 'invocation_a',
        agent: LlmAgent(name: 'root_agent', model: 'gemini-2.5-flash'),
        session: session,
      );
      final Context context = Context(invocationContext);

      final AuthConfig requested = AuthHandler(
        authConfig: authConfig,
      ).generateAuthRequest();
      final String issuedState =
          requested.exchangedAuthCredential!.oauth2!.state!;

      final String responseStateKey = authResponseStateKey(
        authConfig.credentialKey,
      );
      session.state[responseStateKey] = AuthCredential(
        authType: AuthCredentialType.oauth2,
        oauth2: OAuth2Auth(
          state: issuedState,
          redirectUri: 'https://example.com/callback',
          authResponseUri:
              'https://example.com/callback?code=auth-code&state=$issuedState',
          authCode: 'auth-code',
        ),
      );

      final Completer<void> exchangeEntered = Completer<void>();
      final Completer<void> allowFinish = Completer<void>();
      final _SlowFakeExchanger slowExchanger = _SlowFakeExchanger(
        exchangeEntered: exchangeEntered,
        allowFinish: allowFinish,
      );

      final CredentialManager manager = CredentialManager(
        authConfig: authConfig.copyWith(),
      )..registerCredentialExchanger(AuthCredentialType.oauth2, slowExchanger);

      bool eventLoopProgressedWhileWaiting = false;
      final Future<AuthCredential?> credentialFuture = manager
          .getAuthCredential(context);

      await exchangeEntered.future;
      // Schedule another microtask/timer while the exchange is suspended.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      eventLoopProgressedWhileWaiting = true;
      allowFinish.complete();

      final AuthCredential? result = await credentialFuture;
      expect(eventLoopProgressedWhileWaiting, isTrue);
      expect(result, isNotNull);
      expect(result!.oauth2?.accessToken, 'exchanged-access-token');
      expect(slowExchanger.callCount, 1);

      // Verify state stores the exchanged credential with clientSecret stripped.
      final AuthCredential storedInState =
          session.state[responseStateKey] as AuthCredential;
      expect(storedInState.oauth2?.accessToken, 'exchanged-access-token');
      expect(storedInState.oauth2?.clientSecret, isNull);

      // Second call uses the already-exchanged token from state without re-exchanging.
      final CredentialManager secondManager = CredentialManager(
        authConfig: authConfig.copyWith(),
      )..registerCredentialExchanger(AuthCredentialType.oauth2, slowExchanger);
      final AuthCredential? secondResult = await secondManager
          .getAuthCredential(context);
      expect(secondResult?.oauth2?.accessToken, 'exchanged-access-token');
      expect(slowExchanger.callCount, 1);
    });
  });

  group('5. toGenerateContentBody & LlmRequest.toGenerateContentBody (9be86308a)', () {
    const Set<String> topLevelKeys = <String>{
      'cachedContent',
      'continuationToken',
      'labels',
      'modelArmorConfig',
      'outputConfig',
      'safetySettings',
      'serviceTier',
      'systemInstruction',
      'toolConfig',
      'tools',
    };
    const Set<String> clientOnlyKeys = <String>{
      'automaticContinuation',
      'automaticFunctionCalling',
      'httpOptions',
      'shouldReturnHttpResponse',
    };

    test('tools are top-level and temperature stays in generationConfig', () {
      final Map<String, dynamic> body = toGenerateContentBody(
        _sampleRequest(
          config: GenerateContentConfig(
            temperature: 0.2,
            tools: <ToolDeclaration>[_sampleTool()],
          ),
        ),
      );
      expect(body.containsKey('tools'), isTrue);
      final Map<String, dynamic> genConfig =
          body['generationConfig'] as Map<String, dynamic>;
      expect(genConfig.containsKey('tools'), isFalse);
      expect(genConfig['temperature'], closeTo(0.2, 1e-6));
      expect(body.containsKey('temperature'), isFalse);
    });

    test('client-only fields and _url/model never reach the wire', () {
      final Map<String, dynamic> body = toGenerateContentBody(
        _sampleRequest(
          config: GenerateContentConfig(
            temperature: 0.2,
            httpOptions: HttpOptions(headers: <String, String>{'a': 'b'}),
            automaticFunctionCalling: AutomaticFunctionCallingConfig(
              disable: true,
            ),
            shouldReturnHttpResponse: true,
            automaticContinuation: true,
          ),
        ),
      );
      final Set<String> emitted = <String>{
        ...body.keys,
        ...((body['generationConfig'] as Map<String, dynamic>?)?.keys ??
            const <String>[]),
      };
      expect(emitted.intersection(clientOnlyKeys), isEmpty);
      expect(body.containsKey('_url'), isFalse);
      expect(body.containsKey('model'), isFalse);
    });

    test('body survives a JSON round-trip and base64-encodes inline bytes', () {
      final Uint8List pngBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]);
      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.text('What is in this image?'),
              Part.fromInlineData(mimeType: 'image/png', data: pngBytes),
            ],
          ),
        ],
        config: GenerateContentConfig(
          tools: <ToolDeclaration>[_sampleTool()],
          safetySettings: <Object?>[
            <String, Object?>{
              'category': 'HARM_CATEGORY_HATE_SPEECH',
              'threshold': 'BLOCK_ONLY_HIGH',
            },
          ],
          thinkingConfig: <String, Object?>{'thinkingBudget': 128},
        ),
      );

      final Map<String, dynamic> body = toGenerateContentBody(request);
      expect(jsonDecode(jsonEncode(body)), equals(body));

      final String encodedData =
          (((body['contents'] as List).first as Map)['parts'] as List)[1]
                  ['inlineData']['data']
              as String;
      expect(base64Decode(encodedData), equals(pngBytes));
    });

    test('full field set splits top-level, generationConfig (22 keys), and client-only', () {
      final Map<String, dynamic> body = toGenerateContentBody(
        _sampleRequest(config: _fullVertexConfig()),
        vertexai: true,
      );
      final Set<String> top = body.keys.toSet()
        ..removeAll(<String>['contents', 'generationConfig']);
      final Map<String, dynamic> generation =
          body['generationConfig'] as Map<String, dynamic>;

      expect(top, equals(topLevelKeys));
      expect(top.intersection(generation.keys.toSet()), isEmpty);
      expect(
        clientOnlyKeys.intersection(top.union(generation.keys.toSet())),
        isEmpty,
      );
      expect(generation.length, 22);
      expect(generation.containsKey('modelConfig'), isTrue);
      expect(generation.containsKey('modelSelectionConfig'), isFalse);
    });

    test('backend-exclusive fields raise annotated ArgumentError and succeed on supported backend', () {
      final LlmRequest devOnlyReq = _sampleRequest(
        config: GenerateContentConfig(enableEnhancedCivicAnswers: true),
      );
      expect(
        () => toGenerateContentBody(devOnlyReq, vertexai: true),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(
              contains('enable_enhanced_civic_answers'),
              contains('LlmRequest.config.enable_enhanced_civic_answers'),
              contains('Vertex AI'),
            ),
          ),
        ),
      );
      final Map<String, dynamic> devBody = toGenerateContentBody(
        devOnlyReq,
        vertexai: false,
      );
      expect(
        (devBody['generationConfig'] as Map)['enableEnhancedCivicAnswers'],
        isTrue,
      );

      final Map<String, dynamic> storeBody = toGenerateContentBody(
        _sampleRequest(config: GenerateContentConfig(store: true)),
        vertexai: false,
      );
      expect(storeBody['store'], isTrue);
      expect(
        (storeBody['generationConfig'] as Map?)?.containsKey('store') ?? false,
        isFalse,
      );

      final LlmRequest vertexOnlyReq = _sampleRequest(
        config: GenerateContentConfig(
          modelArmorConfig: <String, Object?>{
            'prompt_template_name': 'projects/p/locations/us-central1/templates/t',
          },
        ),
      );
      expect(
        () => toGenerateContentBody(vertexOnlyReq, vertexai: false),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(
              contains('model_armor_config'),
              contains('LlmRequest.config.model_armor_config'),
              contains('the Gemini Developer API'),
            ),
          ),
        ),
      );
    });

    test('vertexai defaults to Developer API and switches to Vertex AI in enterprise mode', () {
      final LlmRequest devReq = _sampleRequest(
        config: GenerateContentConfig(enableEnhancedCivicAnswers: true),
      );
      final Map<String, dynamic> devBody = toGenerateContentBody(
        devReq,
        environment: const <String, String>{},
      );
      expect(
        (devBody['generationConfig'] as Map)['enableEnhancedCivicAnswers'],
        isTrue,
      );
      expect(
        devReq.toGenerateContentBody(environment: const <String, String>{}),
        equals(devBody),
      );

      const String template = 'projects/p/locations/us-central1/templates/t';
      final LlmRequest vertexReq = _sampleRequest(
        config: GenerateContentConfig(
          modelArmorConfig: <String, Object?>{'prompt_template_name': template},
        ),
      );
      final Map<String, dynamic> vertexBody = toGenerateContentBody(
        vertexReq,
        environment: const <String, String>{'GOOGLE_GENAI_USE_ENTERPRISE': '1'},
      );
      expect(
        vertexBody['modelArmorConfig'],
        equals(<String, Object?>{'prompt_template_name': template}),
      );
      expect(
        vertexReq.toGenerateContentBody(
          environment: const <String, String>{
            'GOOGLE_GENAI_USE_ENTERPRISE': '1',
          },
        ),
        equals(vertexBody),
      );
    });

    test('apiClient expands short cachedContent on Vertex AI and errors when missing', () {
      final _FakeGenAiApiClient baseClient = _FakeGenAiApiClient(
        vertexai: true,
        project: 'my-proj',
        location: 'us-central1',
      );
      final _FakeGenAiClient wrappedClient = _FakeGenAiClient(baseClient);
      final LlmRequest request = _sampleRequest(
        config: GenerateContentConfig(cachedContent: 'cachedContents/123'),
      );

      for (final Object client in <Object>[wrappedClient, baseClient]) {
        final Map<String, dynamic> body = request.toGenerateContentBody(
          apiClient: client,
        );
        expect(
          body['cachedContent'],
          'projects/my-proj/locations/us-central1/cachedContents/123',
        );
      }

      for (final String shortName in <String>['cachedContents/123', '123']) {
        expect(
          () => toGenerateContentBody(
            _sampleRequest(
              config: GenerateContentConfig(cachedContent: shortName),
            ),
            vertexai: true,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => '${e.message}',
              'message',
              allOf(
                contains('LlmRequest.config.cached_content'),
                contains('api_client'),
              ),
            ),
          ),
        );
      }

      final Map<String, dynamic> devCachedBody = toGenerateContentBody(
        _sampleRequest(config: GenerateContentConfig(cachedContent: '123')),
        vertexai: false,
      );
      expect(devCachedBody['cachedContent'], 'cachedContents/123');
    });

    test('string systemInstruction becomes a Content block and method matches function', () {
      final Map<String, dynamic> body = toGenerateContentBody(
        _sampleRequest(
          config: GenerateContentConfig(systemInstruction: 'Be terse.'),
        ),
      );
      expect(
        ((body['systemInstruction'] as Map)['parts'] as List).first['text'],
        'Be terse.',
      );

      final LlmRequest fullReq = _sampleRequest(config: _fullVertexConfig());
      expect(
        fullReq.toGenerateContentBody(vertexai: true),
        equals(toGenerateContentBody(fullReq, vertexai: true)),
      );
    });
  });

  group('6. AnthropicLlm preserves empty thinking blocks (946ca7722)', () {
    for (final String thinkingText in <String>['My reasoning steps.', '']) {
      test('partToMessageBlock round-trips thinking part with text=${jsonEncode(thinkingText)}', () {
        final Part part = Part.text(
          thinkingText,
          thought: true,
          thoughtSignature: utf8.encode('roundtrip_sig'),
        );
        final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(part);
        expect(block['type'], 'thinking');
        expect(block['thinking'], thinkingText);
        expect(block['signature'], 'roundtrip_sig');
      });
    }

    for (final List<String> thinkingDeltas in <List<String>>[
      <String>['Reason.'],
      <String>[],
    ]) {
      test('streaming thinking captures signature_delta with deltas=$thinkingDeltas', () async {
        final AnthropicLlm llm = AnthropicLlm(
          model: 'claude-sonnet-4-20250514',
          streamInvoker: ({required Map<String, Object?> request}) async* {
            yield <String, Object?>{
              'type': 'message_start',
              'message': <String, Object?>{
                'model': 'claude-sonnet-4-20250514',
                'usage': <String, Object?>{
                  'input_tokens': 10,
                  'output_tokens': 0,
                },
              },
            };
            yield <String, Object?>{
              'type': 'content_block_start',
              'index': 0,
              'content_block': <String, Object?>{
                'type': 'thinking',
                'thinking': '',
                'signature': '',
              },
            };
            for (final String deltaText in thinkingDeltas) {
              yield <String, Object?>{
                'type': 'content_block_delta',
                'index': 0,
                'delta': <String, Object?>{
                  'type': 'thinking_delta',
                  'thinking': deltaText,
                },
              };
            }
            yield <String, Object?>{
              'type': 'content_block_delta',
              'index': 0,
              'delta': <String, Object?>{
                'type': 'signature_delta',
                'signature': 'sig_stream_123',
              },
            };
            yield <String, Object?>{'type': 'content_block_stop', 'index': 0};
            yield <String, Object?>{
              'type': 'message_delta',
              'delta': <String, Object?>{'stop_reason': 'end_turn'},
              'usage': <String, Object?>{'output_tokens': 5},
            };
            yield <String, Object?>{'type': 'message_stop'};
          },
        );

        final List<LlmResponse> responses = await llm
            .generateContent(
              LlmRequest(
                model: 'claude-sonnet-4-20250514',
                contents: <Content>[Content.userText('hi')],
              ),
              stream: true,
            )
            .toList();

        final LlmResponse finalResponse = responses.last;
        expect(finalResponse.partial, isFalse);
        expect(finalResponse.content, isNotNull);
        final Part thinkingPart = finalResponse.content!.parts.first;
        expect(thinkingPart.thought, isTrue);
        expect(thinkingPart.text, thinkingDeltas.join());
        expect(
          utf8.decode(thinkingPart.thoughtSignature!),
          'sig_stream_123',
        );

        final Map<String, Object?> block = AnthropicLlm.partToMessageBlock(
          thinkingPart,
        );
        expect(block['type'], 'thinking');
        expect(block['thinking'], thinkingDeltas.join());
        expect(block['signature'], 'sig_stream_123');
        expect(
          AnthropicLlm.contentToMessageParam(finalResponse.content!),
          equals(<String, Object?>{
            'role': 'assistant',
            'content': <Object?>[block],
          }),
        );
      });
    }
  });

  group('7. Workflow waitForOutput & replay interception on resume (ba142cf8e)', () {
    for (final bool isStatic in <bool>[true, false]) {
      test('checkInterception Case 6 treats plain wait_for_output node like plain node (isStatic=$isStatic)', () {
        final ChildScanState recovered = ChildScanState(runId: '1');
        final BaseNode testNode = node(
          (WorkflowContext _, Object? _) => null,
          name: 'node',
          waitForOutput: true,
        );
        final DynamicNodeRun run = DynamicNodeRun(
          state: NodeState(runId: '1'),
          recoveredState: recovered,
          isStatic: isStatic,
        );

        final InterceptionResult result = checkInterception(
          node: testNode,
          recovered: recovered,
          currentRun: run,
        );
        expect(result.shouldRun, equals(!isStatic));
      });
    }

    test('checkInterception Case 6 reruns waiting agent or rerun_on_resume node', () {
      final ChildScanState recovered = ChildScanState(runId: '1');
      final BaseNode rerunNode = node(
        (WorkflowContext _, Object? _) => null,
        name: 'node',
        waitForOutput: true,
        rerunOnResume: true,
      );
      final AgentNode agentNode = AgentNode(
        agent: _MinimalAgent(name: 'agent'),
        waitForOutput: true,
      );

      for (final Object candidate in <Object>[
        rerunNode,
        agentNode,
        _MinimalAgent(name: 'raw_agent'),
      ]) {
        final DynamicNodeRun run = DynamicNodeRun(
          state: NodeState(runId: '1'),
          recoveredState: recovered,
          isStatic: true,
        );
        final InterceptionResult result = checkInterception(
          node: candidate,
          recovered: recovered,
          currentRun: run,
        );
        expect(result.shouldRun, isTrue);
      }
    });

    for (final bool resumable in <bool>[false, true]) {
      test('resume does not rerun superseded waiting run (resumable=$resumable)', () async {
        final _GatherNode gather = _GatherNode(name: 'Gather');
        final BaseNode ask = node(
          (WorkflowContext _, Object? _) =>
              RequestInput(interruptId: 'ask_1', message: 'Continue?'),
          name: 'Ask',
        );
        final List<Object?> doneInputs = <Object?>[];
        final BaseNode done = node((WorkflowContext _, Object? input) {
          doneInputs.add(input);
          return input;
        }, name: 'Done');
        final BaseNode nodeA = node(
          (WorkflowContext _, Object? _) => 'a',
          name: 'A',
        );
        final BaseNode nodeB = node(
          (WorkflowContext _, Object? _) => 'b',
          name: 'B',
        );

        final Workflow wf = Workflow(
          name: 'test_agent',
          nodes: <BaseNode>[nodeA, nodeB, gather, ask, done],
          edges: <Edge>[
            Edge(fromNode: START, toNode: nodeA),
            Edge(fromNode: nodeA, toNode: gather),
            Edge(fromNode: START, toNode: nodeB),
            Edge(fromNode: nodeB, toNode: gather),
            Edge(fromNode: gather, toNode: ask),
            Edge(fromNode: ask, toNode: done),
          ],
        );

        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'u1',
        );
        final InvocationContext ctx1 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_1',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );

        final List<Event> events1 = await wf.runAsync(ctx1).toList();
        session.events.addAll(events1);
        expect(
          List<String>.from(gather.calls.cast<String>())..sort(),
          <String>['a', 'b'],
        );

        session.events.add(
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                createRequestInputResponse('ask_1', <String, Object?>{
                  'yes': true,
                }),
              ],
            ),
          ),
        );

        final InvocationContext ctx2 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_1',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );
        await wf.runAsync(ctx2).toList();

        expect(
          List<String>.from(gather.calls.cast<String>())..sort(),
          <String>['a', 'b'],
        );
        expect(doneInputs, <Object?>[
          <String, Object?>{'yes': true},
        ]);
        expect(
          List<String>.from((session.state['seen'] as List).cast<String>())
            ..sort(),
          <String>['a', 'b'],
        );
      });

      test('resume does not rerun waiting run before its next trigger (resumable=$resumable)', () async {
        final _GatherNode gather = _GatherNode(name: 'Gather');
        final BaseNode ask = node(
          (WorkflowContext _, Object? _) =>
              RequestInput(interruptId: 'ask_2', message: 'Continue?'),
          name: 'Ask',
        );
        final List<Object?> doneInputs = <Object?>[];
        final BaseNode done = node((WorkflowContext _, Object? input) {
          doneInputs.add(input);
          return input;
        }, name: 'Done');
        final BaseNode nodeA = node(
          (WorkflowContext _, Object? _) => 'a',
          name: 'A',
        );
        final BaseNode nodeB = node(
          (WorkflowContext _, Object? _) => 'b',
          name: 'B',
        );

        final Workflow wf = Workflow(
          name: 'test_agent',
          nodes: <BaseNode>[nodeA, ask, nodeB, gather, done],
          edges: <Edge>[
            Edge(fromNode: START, toNode: nodeA),
            Edge(fromNode: nodeA, toNode: gather),
            Edge(fromNode: START, toNode: ask),
            Edge(fromNode: ask, toNode: nodeB),
            Edge(fromNode: nodeB, toNode: gather),
            Edge(fromNode: gather, toNode: done),
          ],
        );

        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'u1',
        );
        final InvocationContext ctx1 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_2',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );

        final List<Event> events1 = await wf.runAsync(ctx1).toList();
        session.events.addAll(events1);
        expect(gather.calls, <Object?>['a']);

        session.events.add(
          Event(
            invocationId: 'inv_2',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                createRequestInputResponse('ask_2', <String, Object?>{
                  'yes': true,
                }),
              ],
            ),
          ),
        );

        final InvocationContext ctx2 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_2',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );
        await wf.runAsync(ctx2).toList();

        expect(gather.calls, <Object?>['a', 'b']);
        expect(doneInputs, <Object?>[
          <Object?>['a', 'b'],
        ]);
        expect(session.state['seen'], <Object?>['a', 'b']);
      });

      test('resume does not rerun waiting runs from earlier loop laps (resumable=$resumable)', () async {
        final _GatherNode gather = _GatherNode(name: 'Gather');
        final BaseNode nodeA = node(
          (WorkflowContext _, Object? _) => 'a',
          name: 'A',
        );
        final BaseNode nodeB = node(
          (WorkflowContext _, Object? _) => 'b',
          name: 'B',
        );
        final _LapRouterNode router = _LapRouterNode(name: 'Router', laps: 3);
        final BaseNode ask = node(
          (WorkflowContext _, Object? _) =>
              RequestInput(interruptId: 'ask_3', message: 'Finish?'),
          name: 'Ask',
        );
        final List<Object?> doneInputs = <Object?>[];
        final BaseNode done = node((WorkflowContext _, Object? input) {
          doneInputs.add(input);
          return input;
        }, name: 'Done');

        final Workflow wf = Workflow(
          name: 'test_agent',
          nodes: <BaseNode>[nodeA, nodeB, gather, router, ask, done],
          edges: <Edge>[
            Edge(fromNode: START, toNode: nodeA),
            Edge(fromNode: nodeA, toNode: gather),
            Edge(fromNode: nodeA, toNode: nodeB),
            Edge(fromNode: nodeB, toNode: gather),
            Edge(fromNode: gather, toNode: router),
            Edge(fromNode: router, toNode: nodeA, route: 'loop'),
            Edge(fromNode: router, toNode: ask, route: 'stop'),
            Edge(fromNode: ask, toNode: done),
          ],
        );

        final InMemorySessionService sessionService = InMemorySessionService();
        final Session session = await sessionService.createSession(
          appName: 'app',
          userId: 'u1',
        );
        final InvocationContext ctx1 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_3',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );

        final List<Event> events1 = await wf.runAsync(ctx1).toList();
        session.events.addAll(events1);
        expect(gather.calls, <Object?>['a', 'b', 'a', 'b', 'a', 'b']);

        session.events.add(
          Event(
            invocationId: 'inv_3',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                createRequestInputResponse('ask_3', <String, Object?>{
                  'yes': true,
                }),
              ],
            ),
          ),
        );

        final InvocationContext ctx2 = InvocationContext(
          sessionService: sessionService,
          invocationId: 'inv_3',
          agent: wf,
          session: session,
          userContent: Content.userText('go'),
          resumabilityConfig: resumable
              ? ResumabilityConfig(isResumable: true)
              : null,
        );
        final List<Event> events2 = await wf.runAsync(ctx2).toList();

        expect(gather.calls, <Object?>['a', 'b', 'a', 'b', 'a', 'b']);
        expect(doneInputs, <Object?>[
          <String, Object?>{'yes': true},
        ]);
        expect(events2.where(hasRequestInputFunctionCall), isEmpty);
        expect(session.state['lap'], 3);
      });
    }
  });
}
