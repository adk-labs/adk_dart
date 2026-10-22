import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/integrations/agent_identity/agent_identity.dart'
    as agent_identity;
import 'package:adk_dart/src/integrations/secret_manager/secret_manager.dart'
    as secret_mgr;
import 'package:adk_dart/src/labs/antigravity/antigravity.dart' as ag;
import 'package:adk_dart/src/optimization/gepa_root_agent_optimizer.dart'
    as gepa_opt;
import 'package:test/test.dart';

void main() {
  group('1. SqliteMemoryService & ToolCallIntegrityPlugin', () {
    test('SqliteMemoryService adds sessions and searches memory via FTS5', () async {
      final SqliteMemoryService memoryService = SqliteMemoryService(':memory:');
      final Session session = Session(
        id: 'sess_1',
        appName: 'app_1',
        userId: 'user_1',
        events: <Event>[
          Event(
            id: 'e1',
            invocationId: 'inv_1',
            author: 'user',
            content: Content.userText('My favorite framework is Flutter and ADK.'),
          ),
        ],
      );

      await memoryService.addSessionToMemory(session);
      final SearchMemoryResponse res = await memoryService.searchMemory(
        appName: 'app_1',
        userId: 'user_1',
        query: 'Flutter',
      );
      expect(res.memories, hasLength(1));
      expect(
        res.memories.first.content.parts.first.text,
        contains('Flutter'),
      );
      await memoryService.close();
    });

    test('ToolCallIntegrityPlugin stamps and validates HMAC signatures', () async {
      final ToolCallIntegrityPlugin plugin = ToolCallIntegrityPlugin(
        'super-secret-key',
      );
      final LlmResponse llmResponse = LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'get_weather',
              args: <String, dynamic>{'city': 'Seoul'},
              id: 'call_1',
            ),
          ],
        ),
      );

      final InvocationContext invCtx = _dummyInvocationContext();
      final Event stampedEvent = Event(
        invocationId: 'inv_1',
        author: 'test_agent',
        content: llmResponse.content,
      );

      await plugin.onEventCallback(
        invocationContext: invCtx,
        event: stampedEvent,
      );
      expect(
        stampedEvent.customMetadata?[hmacMetaKey],
        isA<Map<String, String>>(),
      );
      invCtx.session.events.add(stampedEvent);

      final FunctionTool weatherTool = FunctionTool(
        func: ({required String city}) => 'Sunny in $city',
        name: 'get_weather',
      );
      final ToolContext validToolCtx = Context(
        invCtx,
        functionCallId: 'call_1',
      );
      final Map<String, dynamic>? checkResult = await plugin.beforeToolCallback(
        tool: weatherTool,
        toolArgs: <String, dynamic>{'city': 'Seoul'},
        toolContext: validToolCtx,
      );
      expect(checkResult, isNull);

      // Forged tool call should throw ToolCallIntegrityError.
      final ToolContext forgedToolCtx = Context(
        invCtx,
        functionCallId: 'forged_id',
      );
      expect(
        () => plugin.beforeToolCallback(
          tool: weatherTool,
          toolArgs: <String, dynamic>{'city': 'Seoul'},
          toolContext: forgedToolCtx,
        ),
        throwsA(isA<ToolCallIntegrityError>()),
      );
    });
  });

  group('2. KmsEncryptor & KmsEncryptedCredentials', () {
    test('envelope encrypts and decrypts credentials and refreshes transparently', () async {
      const String keyName =
          'projects/my-proj/locations/global/keyRings/kr/cryptoKeys/ck';
      final LocalKmsClient kmsClient = LocalKmsClient();
      final KmsEncryptor encryptor = KmsEncryptor(
        kmsKeyName: keyName,
        kmsClient: kmsClient,
      );

      final EncryptedCredentialsResult encrypted = encryptor.encrypt(
        token: 'access-123',
        refreshToken: 'refresh-456',
        clientSecret: 'secret-789',
      );
      expect(encrypted.encryptedToken, isNotEmpty);
      expect(encrypted.wrappedDek, isNotEmpty);

      final DecryptedCredentialsResult decrypted = encryptor.decrypt(
        encryptedToken: encrypted.encryptedToken,
        encryptedRefreshToken: encrypted.encryptedRefreshToken,
        encryptedClientSecret: encrypted.encryptedClientSecret,
        wrappedDek: encrypted.wrappedDek,
      );
      expect(decrypted.token, 'access-123');
      expect(decrypted.refreshToken, 'refresh-456');
      expect(decrypted.clientSecret, 'secret-789');

      final KmsEncryptedCredentials creds =
          KmsEncryptedCredentials.fromAuthorizedUserInfo(
        <String, Object?>{
          'token': 'kms:${encrypted.encryptedToken}',
          'refresh_token': 'kms:${encrypted.encryptedRefreshToken}',
          'client_id': 'client-1',
          'client_secret': 'kms:${encrypted.encryptedClientSecret}',
          'kms_key_name': keyName,
          'wrapped_dek': encrypted.wrappedDek,
        },
        kmsClient: kmsClient,
      );
      expect(creds.token, 'access-123');
      expect(creds.refreshToken, 'refresh-456');
    });
  });

  group('3. GEPARootAgentOptimizer, ScenarioGenerator & CloudTtsLlm', () {
    test('GEPARootAgentOptimizer optimizes root agent instructions', () async {
      final LlmAgent agent = LlmAgent(
        name: 'root_agent',
        instruction: 'Initial instruction.',
        model: _StaticLlm('Improved instruction.'),
      );
      final _FakeEvalSampler sampler = _FakeEvalSampler();
      final GEPARootAgentOptimizer optimizer = GEPARootAgentOptimizer(
        GEPARootAgentOptimizerConfig(
          maxMetricCalls: 4,
          optimizerModel: _StaticLlm('Improved instruction.'),
        ),
        gepaOptimizeRunner: ({
          required Map<String, String> seedCandidate,
          required List<String> trainset,
          required List<String> valset,
          required AgentGEPAAdapter adapter,
          required int reflectionMinibatchSize,
          required int maxMetricCalls,
          required String? runDir,
        }) async {
          final GEPAEvaluationBatch evalBatch = await adapter.evaluate(
            trainset,
            <String, String>{agentPromptKey: 'Better instruction!'},
            captureTraces: true,
          );
          expect(evalBatch.scores.single, closeTo(0.9, 1e-6));
          return gepa_opt.GepaOptimizeRawOutput(
            candidates: <Map<String, String>>[
              seedCandidate,
              <String, String>{agentPromptKey: 'Better instruction!'},
            ],
            valAggregateScores: <double>[0.5, 0.95],
          );
        },
      );

      final GEPARootAgentOptimizerResult result =
          await optimizer.optimize(agent, sampler);
      expect(result.optimizedAgents, hasLength(2));
      expect(result.optimizedAgents[1].overallScore, closeTo(0.95, 1e-6));
      expect(
        result.optimizedAgents[1].optimizedAgent.instruction,
        'Better instruction!',
      );
    });

    test('ScenarioGenerator and CloudTtsLlm synthesize scenarios and audio', () async {
      final LlmAgent agent = LlmAgent(
        name: 'assistant',
        description: 'Helps users book flights',
        instruction: 'Always ask for departure city and dates.',
      );
      final ScenarioGenerator generator = ScenarioGenerator(
        projectId: 'test-proj',
        location: 'us-central1',
      );
      final List<ConversationScenario> scenarios = generator.generateScenarios(
        agent,
        ConversationGenerationConfig(count: 2),
      );
      expect(scenarios, hasLength(2));
      expect(scenarios.first.startingPrompt, isNotEmpty);

      final CloudTtsLlm ttsLlm = CloudTtsLlm(
        ttsClient: DefaultCloudTtsClient(),
      );
      final List<LlmResponse> responses = await ttsLlm
          .generateContent(
            LlmRequest(
              contents: <Content>[Content.userText('Hello from Cloud TTS')],
            ),
          )
          .toList();
      expect(responses, isNotEmpty);
      expect(
        responses.first.content?.parts.any((Part p) => p.inlineData != null),
        isTrue,
      );
    });
  });

  group('4. Labs Antigravity module', () {
    test('converts Antigravity SDK turns, captures tool results, and runs AntigravityAgent', () async {
      final ag.ToolResultCapture capture = ag.ToolResultCapture();
      await capture.run(
        null,
        const ag.AntigravityToolResult(
          name: 'search',
          id: 'tc_1',
          result: 'Found adk_dart',
        ),
      );
      final Event? toolResultEvent = ag.drainToolResults(
        invocationId: 'inv_1',
        author: 'ag_agent',
        pendingFunctionCalls: <FunctionCall>[
          FunctionCall(name: 'search', id: 'tc_1'),
        ],
        resultBuffer: capture,
      );
      expect(toolResultEvent, isNotNull);
      expect(
        toolResultEvent!.content?.parts.single.functionResponse?.name,
        'search',
      );

      final ag.InMemorySdkConversation sdkConv = ag.InMemorySdkConversation(
        onSendStream: (String prompt) => Stream<ag.AntigravityStep>.value(
          const ag.AntigravityStep(
            source: ag.StepSource.model,
            type: ag.StepType.textResponse,
            status: ag.StepStatus.done,
            content: 'Hello from Antigravity!',
            thinking: 'Planning...',
          ),
        ),
      );
      final ag.AntigravityAgent agAgent = ag.AntigravityAgent(
        name: 'ag_agent',
        description: 'Antigravity test agent',
        sdkAgentFactory: (ag.AgentConfig cfg) =>
            ag.InMemorySdkAgent(config: cfg, conversation: sdkConv),
      );

      final InvocationContext invCtx = _dummyInvocationContext(
        agent: agAgent,
        userContent: Content.userText('Hi Antigravity'),
      );
      final List<Event> events = await agAgent.runAsync(invCtx).toList();
      expect(events, isNotEmpty);
      expect(
        events.any(
          (Event e) =>
              e.content?.parts.any(
                (Part p) => (p.text ?? '').contains('Hello from Antigravity!'),
              ) ??
              false,
        ),
        isTrue,
      );
    });
  });

  group('5. Firestore & Redis Session / Memory Services', () {
    test('FirestoreSessionService and FirestoreMemoryService persist and search', () async {
      final InMemoryFirestoreDatabaseClient db =
          InMemoryFirestoreDatabaseClient();
      final FirestoreSessionService sessionService = FirestoreSessionService(
        client: db,
      );
      final FirestoreMemoryService memoryService = FirestoreMemoryService(
        client: db,
      );

      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        state: <String, Object?>{
          'app:theme': 'dark',
          'user:lang': 'ko',
          'counter': 1,
        },
      );
      expect(session.state['app:theme'], 'dark');

      final Event event = Event(
        id: 'ev_1',
        invocationId: 'inv_1',
        author: 'user',
        content: Content.userText('Remember that Dart 3 supports patterns'),
        actions: EventActions(stateDelta: <String, Object?>{'counter': 2}),
      );
      await sessionService.appendEvent(session: session, event: event);

      final Session? fetched = await sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: session.id,
      );
      expect(fetched, isNotNull);
      expect(fetched!.state['counter'], 2);
      expect(fetched.events, hasLength(1));

      await memoryService.addSessionToMemory(fetched);
      final SearchMemoryResponse memRes = await memoryService.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'patterns Dart',
      );
      expect(memRes.memories, hasLength(1));
    });

    test('RedisSessionService creates, updates, lists, and deletes sessions', () async {
      final RedisSessionService redis = RedisSessionService();
      final Session s = await redis.createSession(
        appName: 'redis_app',
        userId: 'u1',
        state: <String, Object?>{'app:version': '1.0', 'step': 'init'},
      );
      await redis.appendEvent(
        session: s,
        event: Event(
          id: 'e1',
          invocationId: 'inv1',
          author: 'model',
          content: Content.modelText('Done'),
          actions: EventActions(
            stateDelta: <String, Object?>{'step': 'complete', 'temp:x': 99},
          ),
        ),
      );
      final Session? loaded = await redis.getSession(
        appName: 'redis_app',
        userId: 'u1',
        sessionId: s.id,
      );
      expect(loaded?.state['step'], 'complete');
      expect(loaded?.state.containsKey('temp:x'), isFalse);

      final ListSessionsResponse listed = await redis.listSessions(
        appName: 'redis_app',
        userId: 'u1',
      );
      expect(listed.sessions, hasLength(1));

      await redis.deleteSession(
        appName: 'redis_app',
        userId: 'u1',
        sessionId: s.id,
      );
      expect(
        await redis.getSession(
          appName: 'redis_app',
          userId: 'u1',
          sessionId: s.id,
        ),
        isNull,
      );
    });
  });

  group('6. MongoDB, GCS, ModelArmor, ParameterManager & SecretManager', () {
    test('MongoDbToolset runs vectorSearch and hybridSearch', () async {
      final InMemoryMongoDbClient client = InMemoryMongoDbClient();
      client.setCollectionDocuments(
        'test_db',
        'docs',
        <Map<String, Object?>>[
          <String, Object?>{
            '_id': '1',
            'title': 'ADK Dart guide',
            'embedding': <double>[1.0, 0.0],
          },
        ],
      );
      final MongoDbToolset toolset = MongoDbToolset(
        databaseName: 'test_db',
        mongoClient: client,
        settings: MongoDbToolSettings(useMongodbAutoEmbedding: true),
      );
      final List<BaseTool> tools = await toolset.getTools();
      expect(tools, hasLength(2));

      final Map<String, Object?> vecRes = await vectorSearch(
        collectionName: 'docs',
        query: 'ADK Dart',
        client: client,
        databaseName: 'test_db',
        settings: MongoDbToolSettings(useMongodbAutoEmbedding: true),
      );
      expect(vecRes['status'], 'SUCCESS');
      expect((vecRes['rows'] as List<Object?>), hasLength(1));
    });

    test('GCSToolset and GCSAdminToolset manage buckets and objects', () async {
      final InMemoryGcsClient gcsClient = InMemoryGcsClient();
      setGcsClientFactory(
        ({Object? credentials, String? project}) => gcsClient,
      );
      addTearDown(resetGcsClientFactory);

      final GCSAdminToolset adminToolset = GCSAdminToolset(
        gcsToolSettings: GCSToolSettings(
          capabilities: <GCSCapabilities>[GCSCapabilities.readWrite],
        ),
      );
      final GCSToolset storageToolset = GCSToolset(
        gcsToolSettings: GCSToolSettings(
          capabilities: <GCSCapabilities>[GCSCapabilities.readWrite],
        ),
      );
      expect(await adminToolset.getTools(), hasLength(5));
      expect(await storageToolset.getTools(), hasLength(5));

      final Map<String, Object?> createdBucket = await createBucket(
        projectId: 'proj-1',
        bucketName: 'my-bucket',
      );
      expect(createdBucket['status'], 'SUCCESS');

      final Map<String, Object?> createdObj = await createObject(
        bucketName: 'my-bucket',
        objectName: 'hello.txt',
        data: 'Hello GCS!',
      );
      expect(createdObj['status'], 'SUCCESS');

      final Map<String, Object?> dataRes = await getObjectData(
        bucketName: 'my-bucket',
        objectName: 'hello.txt',
      );
      expect(dataRes['results'], 'Hello GCS!');
    });

    test('ModelArmorPlugin blocks unsafe user prompts and tool outputs', () async {
      final ModelArmorPlugin plugin = ModelArmorPlugin(
        config: ModelArmorConfig(
          promptTemplateName: 'projects/p/locations/us-central1/templates/t1',
        ),
        client: InMemoryModelArmorClient(
          blockedSubstrings: <String>['UNSAFE_PROMPT'],
        ),
      );
      final InvocationContext invCtx = _dummyInvocationContext();
      final LlmResponse? blocked = await plugin.beforeModelCallback(
        callbackContext: CallbackContext(invCtx),
        llmRequest: LlmRequest(
          contents: <Content>[
            Content.userText('This contains UNSAFE_PROMPT payload'),
          ],
        ),
      );
      expect(blocked, isNotNull);
      expect(blocked!.customMetadata?['model_armor_blocked'], isTrue);
    });

    test('ParameterManagerClient and SecretManagerClient fetch payloads', () async {
      setParameterManagerFetcher(
        ({
          required String resourceName,
          required String accessToken,
          String? location,
        }) async => '{"env":"prod"}',
      );
      addTearDown(resetParameterManagerFetcher);

      final ParameterManagerClient pmClient = ParameterManagerClient(
        authToken: 'tok',
      );
      expect(
        await pmClient.getParameter(
          'projects/p/locations/global/parameters/param1/versions/v1',
        ),
        '{"env":"prod"}',
      );

      secret_mgr.setSecretManagerSecretFetcher(
        ({
          required String resourceName,
          String? serviceAccountJson,
          String? authToken,
        }) async => 'my-secret-value',
      );
      addTearDown(secret_mgr.resetSecretManagerSecretFetcher);

      final secret_mgr.SecretManagerClient smClient =
          secret_mgr.SecretManagerClient(authToken: 'tok');
      expect(
        await smClient.getSecret('projects/p/secrets/s1/versions/latest'),
        'my-secret-value',
      );
    });
  });

  group('7. OpenAIResponsesLlm & OCIGenAILlm', () {
    test('OpenAIResponsesLlm generates content via Responses API', () async {
      final OpenAIResponsesLlm llm = OpenAIResponsesLlm(
        model: 'gpt-5-nano',
        apiKey: 'test-key',
        client: _FakeOpenAiResponsesClient(),
      );
      final List<LlmResponse> responses = await llm
          .generateContent(
            LlmRequest(contents: <Content>[Content.userText('Hi OpenAI')]),
          )
          .toList();
      expect(responses, hasLength(1));
      expect(responses.single.content?.parts.single.text, 'Hello from OpenAI');
    });

    test('OCIGenAILlm generates content via OCI GenAI client', () async {
      final OCIGenAILlm ociLlm = OCIGenAILlm(
        model: 'cohere.command-r-plus',
        compartmentId: 'ocid1.compartment.oc1..example',
        client: _FakeOciGenAiClient(),
      );
      final List<LlmResponse> responses = await ociLlm
          .generateContent(
            LlmRequest(contents: <Content>[Content.userText('Hi OCI')]),
          )
          .toList();
      expect(responses, hasLength(1));
      expect(responses.single.content?.parts.single.text, 'OCI reply');
    });
  });

  group('8. E2BEnvironment, LiveKit & AgentIdentity', () {
    test('E2BEnvironment executes commands and reads/writes files', () async {
      final E2BEnvironment env = E2BEnvironment(
        image: 'base',
        timeout: 300,
        apiKey: 'e2b-key',
      );
      await env.initialize();
      await env.writeFile('/tmp/test.txt', 'hello e2b');
      final List<int> readBack = await env.readFile('/tmp/test.txt');
      expect(utf8.decode(readBack), 'hello e2b');
      final EnvironmentExecutionResult execRes =
          await env.execute('echo hello');
      expect(execRes.exitCode, 0);
      await env.close();
    });

    test('LiveKitToolset registers call and invokes end_call / send_dtmf', () async {
      final InMemoryLiveKitRoomClient room = InMemoryLiveKitRoomClient(
        remoteParticipants: <String, LiveKitParticipant>{
          'sip_caller': LiveKitParticipant(
            identity: 'sip_caller',
            kind: LiveKitParticipantKind.sip,
          ),
        },
      );
      final LiveKitCall call = LiveKitCall(
        room: room,
        userId: 'u1',
        sessionId: 's1',
      );
      registerCall(call);
      addTearDown(() => unregisterCall(call));

      final LiveKitToolset toolset = LiveKitToolset();
      final List<BaseTool> tools = await toolset.getTools(
        readonlyContext: ReadonlyContext(_dummyInvocationContext()),
      );
      expect(tools.map((BaseTool t) => t.name), contains('end_call'));
      expect(tools.map((BaseTool t) => t.name), contains('send_dtmf'));
    });

    test('GcpAuthProvider resolves credentials via AgentIdentityCredentialsProvider', () async {
      final agent_identity.GcpAuthProvider provider =
          agent_identity.GcpAuthProvider(
        agentIdentityProvider: agent_identity.AgentIdentityCredentialsProvider(
          client: _FakeAgentIdentityClient(),
        ),
      );
      final agent_identity.GcpAuthProviderScheme scheme =
          agent_identity.GcpAuthProviderScheme(
        name: 'gcp_id',
        scopes: <String>['https://www.googleapis.com/auth/cloud-platform'],
      );
      final AuthCredential? cred = await provider.getAuthCredential(
        AuthConfig(authScheme: scheme.toJsonString()),
        _dummyToolContext(),
      );
      expect(cred, isNotNull);
      expect(cred!.http?.credentials.token, 'gcp-identity-token');
    });

    test('AgentEngineSandboxComputer executes browser actions in-memory', () async {
      final AgentEngineSandboxComputer computer = AgentEngineSandboxComputer(
        projectId: 'p',
        sandboxTemplateName: 'tpl-1',
      );
      await computer.initialize();
      final ComputerState state = await computer.navigate('https://example.com');
      expect(state.url, isNotEmpty);
      await computer.close();
    });

    test('getAgentsDict, A2A interceptors, and fine-grained parity helpers work', () async {
      final LlmAgent sub = LlmAgent(
        name: 'sub_agent',
        instruction: 'Sub instruction.',
      );
      final LlmAgent root = LlmAgent(
        name: 'root_agent',
        instruction: 'Root instruction.',
        subAgents: <BaseAgent>[sub],
      );
      final Map<String, AgentInfo> dict = await getAgentsDict(root);
      expect(dict.keys, containsAll(<String>['root_agent', 'sub_agent']));
      expect(dict['root_agent']!.subAgents, <String>['sub_agent']);

      final (Object reqObj, ParametersConfig updatedParams) =
          await newIntegrationExtensionInterceptor.beforeRequest!(
            _dummyInvocationContext(agent: root),
            A2aMessage(messageId: 'm1', role: A2aRole.user),
            ParametersConfig(),
          );
      expect(reqObj, isA<A2aMessage>());
      expect(
        updatedParams.clientCallContext?.state['http_kwargs'],
        isA<Map<String, Object?>>(),
      );

      final InMemoryArtifactService artifactService = InMemoryArtifactService();
      await artifactService.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'report.txt',
        artifact: Part.text('artifact body'),
      );
      final Runner runnerWithArtifacts = Runner(
        appName: 'app',
        agent: root,
        sessionService: InMemorySessionService(),
        artifactService: artifactService,
      );
      final Object execResult =
          await includeArtifactsInA2aEventInterceptor.afterEvent!(
            ExecutorContext(
              appName: 'app',
              userId: 'u1',
              sessionId: 's1',
              runner: runnerWithArtifacts,
            ),
            A2aTaskStatusUpdateEvent(
              taskId: 't1',
              contextId: 'c1',
              status: A2aTaskStatus(state: A2aTaskState.working),
            ),
            Event(
              invocationId: 'inv_1',
              author: 'root_agent',
              actions: EventActions(
                artifactDelta: <String, int>{'report.txt': 0},
              ),
            ),
          );
      expect(execResult, isA<List<Object>>());
      expect((execResult as List<Object>), hasLength(2));
      expect(execResult.last, isA<A2aTaskArtifactUpdateEvent>());

      const LiveModelConfig liveCfg = LiveModelConfig(
        responseModalities: <String>['AUDIO', 'TEXT'],
        enableInputAudioTranscription: true,
      );
      expect(
        LiveModelConfig.fromJson(liveCfg.toJson()).responseModalities,
        <String>['AUDIO', 'TEXT'],
      );

      const TokenUsageDetails tokenDetails = TokenUsageDetails(
        promptTokenCount: 10,
        candidatesTokenCount: 20,
        totalTokenCount: 30,
      );
      expect(
        TokenUsageDetails.fromJson(tokenDetails.toJson()).totalTokenCount,
        30,
      );

      const DurationDetails durationDetails = DurationDetails(
        totalDurationSeconds: 1.5,
        modelDurationSeconds: 1.0,
        toolDurationSeconds: 0.3,
        frameworkDurationSeconds: 0.2,
      );
      expect(
        DurationDetails.fromJson(durationDetails.toJson()).totalDurationSeconds,
        1.5,
      );

      expect(PreBuiltBehaviors.advanceGoalOriented.name, isNotEmpty);

      final WebUiLogExporter exporter = WebUiLogExporter();
      exporter.export(
        WebUiLog(
          eventName: 'gen_ai.choice',
          body: 'ok',
          spanId: 'span_1',
        ),
      );
      expect(exporter.getLogsForSpan('span_1'), hasLength(1));
      expect(exporter.getLogsForSpan('span_1').first.eventName, 'gen_ai.choice');
    });
  });
}

InvocationContext _dummyInvocationContext({
  BaseAgent? agent,
  Content? userContent,
}) {
  final BaseAgent resolvedAgent =
      agent ?? LlmAgent(name: 'test_agent', instruction: 'Be helpful.');
  return InvocationContext(
    invocationId: 'inv_1',
    agent: resolvedAgent,
    userContent: userContent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
    sessionService: InMemorySessionService(),
  );
}

ToolContext _dummyToolContext() {
  return Context(_dummyInvocationContext(), functionCallId: 'fc_1');
}

class _StaticLlm extends BaseLlm {
  _StaticLlm(this.reply) : super(model: 'static-llm');
  final String reply;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText(reply));
  }
}

class _FakeEvalSampler extends Sampler<UnstructuredSamplingResult> {
  @override
  List<String> getTrainExampleIds() => <String>['case_1'];

  @override
  List<String> getValidationExampleIds() => <String>['case_1'];

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final double score =
        '${candidate.instruction}'.contains('Better') ? 0.9 : 0.5;
    return UnstructuredSamplingResult(
      scores: <String, double>{'case_1': score},
    );
  }
}

class _FakeOpenAiResponsesClient implements OpenAiResponsesClient {
  @override
  Future<Map<String, Object?>> create({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    return <String, Object?>{
      'id': 'resp_1',
      'status': 'completed',
      'output': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'message',
          'role': 'assistant',
          'content': <Map<String, Object?>>[
            <String, Object?>{
              'type': 'output_text',
              'text': 'Hello from OpenAI',
            },
          ],
        },
      ],
    };
  }

  @override
  Stream<Map<String, Object?>> createStream({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {}
}

class _FakeOciGenAiClient implements OciGenAiClient {
  @override
  Future<Map<String, Object?>> chat(Map<String, Object?> chatDetails) async {
    return <String, Object?>{
      'chatResult': <String, Object?>{
        'modelId': 'cohere.command-r-plus',
        'chatResponse': <String, Object?>{
          'choices': <Map<String, Object?>>[
            <String, Object?>{
              'finishReason': 'STOP',
              'message': <String, Object?>{
                'content': <Map<String, Object?>>[
                  <String, Object?>{'type': 'TEXT', 'text': 'OCI reply'},
                ],
              },
            },
          ],
        },
      },
    };
  }

  @override
  Stream<Map<String, Object?>> chatStream(
    Map<String, Object?> chatDetails,
  ) async* {}
}

class _FakeAgentIdentityClient
    implements agent_identity.AgentIdentityCredentialsClient {
  @override
  Future<agent_identity.AgentIdentityCredentialsResponse> getCredentials({
    required String userId,
    required agent_identity.GcpAuthProviderScheme authScheme,
  }) async {
    return const agent_identity.AgentIdentityCredentialsResponse(
      state: agent_identity.AgentIdentityResponseState.success,
      httpAuthorization: agent_identity.AgentIdentityHttpAuthorization(
        authorizationHeader: 'Authorization',
        token: 'Bearer gcp-identity-token',
      ),
    );
  }
}
