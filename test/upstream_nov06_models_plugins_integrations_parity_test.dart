import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/code_executors/agent_engine_sandbox_code_executor.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/event_actions.dart';
import 'package:adk_dart/src/integrations/agent_registry/agent_registry.dart';
import 'package:adk_dart/src/integrations/eventarc/eventarc.dart';
import 'package:adk_dart/src/integrations/firestore/firestore.dart';
import 'package:adk_dart/src/integrations/openai/openai.dart';
import 'package:adk_dart/src/integrations/redis/redis.dart';
import 'package:adk_dart/src/integrations/slack/slack_runner.dart';
import 'package:adk_dart/src/integrations/typesafe/typesafe_classifier.dart';
import 'package:adk_dart/src/labs/classifiers/base_classifier.dart';
import 'package:adk_dart/src/labs/classifiers/types.dart';
import 'package:adk_dart/src/memory/base_memory_service.dart';
import 'package:adk_dart/src/memory/mongodb_memory_service.dart';
import 'package:adk_dart/src/memory/sqlite_memory_service.dart';
import 'package:adk_dart/src/memory/vertex_ai_memory_bank_service.dart';
import 'package:adk_dart/src/models/anthropic_llm.dart';
import 'package:adk_dart/src/models/apigee_llm.dart';
import 'package:adk_dart/src/models/interactions_utils.dart';
import 'package:adk_dart/src/models/lite_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/plugins/auto_tracing_plugin.dart';
import 'package:adk_dart/src/plugins/bigquery_agent_analytics_plugin.dart';
import 'package:adk_dart/src/plugins/reflect_retry_tool_plugin.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/telemetry/_experimental_semconv.dart'
    as experimental_semconv;
import 'package:adk_dart/src/telemetry/metrics.dart';
import 'package:adk_dart/src/telemetry/sqlite_span_exporter.dart';
import 'package:adk_dart/src/telemetry/tracing.dart';
import 'package:adk_dart/src/tools/function_tool.dart';
import 'package:adk_dart/src/tools/tool_context.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:adk_dart/src/utils/client_labels_utils.dart';
import 'package:adk_dart/src/utils/error_reporting.dart';
import 'package:adk_dart/src/utils/google_client_headers.dart';
import 'package:adk_dart/src/utils/schema_utils.dart' as schema_utils;
import 'package:adk_dart/src/utils/streaming_utils.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _FakeCredentials implements AgentRegistryCredentials {
  _FakeCredentials({required this.valid, required this.token});

  @override
  bool valid;

  @override
  String? token;

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
    valid = true;
    token = 'refreshed-token-$refreshCalls';
  }
}

class _FakeEventarcPublisher extends EventarcPublisherClient {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FakeSlackApiClient implements SlackApiClient {
  @override
  Future<void> chatDelete({required String channel, required String ts}) async {}

  @override
  Future<void> chatUpdate({
    required String channel,
    required String ts,
    required String text,
  }) async {}
}

class _FakeSlackApp implements SlackAppAdapter {
  @override
  final SlackApiClient client = _FakeSlackApiClient();

  @override
  void onEvent(String eventName, SlackEventHandler handler) {}
}

class _FakeEmbedGenaiClient {
  final List<List<String>> calls = <List<String>>[];

  Future<Map<String, Object?>> embedContent({
    required String model,
    required List<String> contents,
    int? outputDimensionality,
    Map<String, Object?>? config,
  }) async {
    calls.add(List<String>.from(contents));
    final int dim =
        outputDimensionality ?? (config?['output_dimensionality'] as int?) ?? 3;
    return <String, Object?>{
      'embeddings': <Map<String, Object?>>[
        for (int i = 0; i < contents.length; i += 1)
          <String, Object?>{
            'values': List<double>.filled(dim, (i + 1).toDouble()),
          },
      ],
    };
  }
}

class _FakeClassifier extends BaseClassifier {
  _FakeClassifier() : super(model: 'fake-model');

  @override
  String get clientLabelKind => 'fake';

  List<String> capturedLabels = <String>[];

  @override
  Future<ClassifierResponse> classify({
    required Object input,
    required Map<String, ClassifierQuestion> questions,
  }) {
    return runWithClientLabelContext(() async {
      capturedLabels = getClientLabels();
      return ClassifierResponse(answers: const <String, ClassifierAnswer>{});
    });
  }
}

Future<InvocationContext> _createInvocationContext({
  String sessionId = 's1',
  String invocationId = 'inv_1',
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'user1',
    sessionId: sessionId,
  );
  return InvocationContext(
    sessionService: sessionService,
    invocationId: invocationId,
    agent: LlmAgent(name: 'root_agent', instruction: 'Test agent'),
    session: session,
  );
}

void main() {
  group('code_executors: AgentEngineSandboxCodeExecutor state & cloning', () {
    test('clone and getState/setState create a fresh lock and preserve fields', () {
      final AgentEngineSandboxCodeExecutor executor =
          AgentEngineSandboxCodeExecutor(
            agentEngineResourceName:
                'projects/my-proj/locations/us-central1/reasoningEngines/42',
          );
      final Object originalLock = executor.agentEngineCreationLock;

      final AgentEngineSandboxCodeExecutor cloned = executor.clone();
      expect(
        cloned.agentEngineResourceName,
        'projects/my-proj/locations/us-central1/reasoningEngines/42',
      );
      expect(
        cloned.sandboxResourceName,
        'projects/my-proj/locations/us-central1/reasoningEngines/42/sandboxEnvironments/0',
      );
      expect(identical(cloned.agentEngineCreationLock, originalLock), isFalse);

      final Map<String, Object?> state = executor.getState();
      expect(state.containsKey('_agent_engine_creation_lock'), isFalse);
      expect(
        state['agent_engine_resource_name'],
        'projects/my-proj/locations/us-central1/reasoningEngines/42',
      );

      cloned.setState(<String, Object?>{
        'sandbox_resource_name':
            'projects/other/locations/europe-west1/reasoningEngines/99/sandboxEnvironments/1',
        'agent_engine_resource_name':
            'projects/other/locations/europe-west1/reasoningEngines/99',
        '__pydantic_private__': <String, Object?>{
          '_project_id': 'other',
          '_location': 'europe-west1',
        },
      });
      expect(
        cloned.agentEngineResourceName,
        'projects/other/locations/europe-west1/reasoningEngines/99',
      );
      expect(
        cloned.sandboxResourceName,
        'projects/other/locations/europe-west1/reasoningEngines/99/sandboxEnvironments/1',
      );
    });
  });

  group('utils: error_reporting, client_labels, headers, schema, streaming', () {
    test('error_reporting redacts by default and exposes detail in debug mode', () {
      final String id = newErrorId();
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(id), isTrue);

      final String redacted = redactError(
        StateError('secret database failure'),
        summary: 'Internal server error',
        errorId: 'abc123def456',
        environment: const <String, String>{},
      );
      expect(
        redacted,
        'Internal server error (error_id: abc123def456)',
      );

      final String debugMsg = redactError(
        StateError('secret database failure'),
        summary: 'Internal server error',
        errorId: 'abc123def456',
        environment: const <String, String>{'ADK_DEBUG_ERRORS': '1'},
      );
      expect(debugMsg, contains('secret database failure'));
      expect(debugMsg, contains('error_id: abc123def456'));
    });

    test('classifierClientLabel and mergeTrackingHttpOptions', () {
      expect(
        classifierClientLabel('llm'),
        startsWith('google-adk-classifier/'),
      );
      expect(classifierClientLabel('llm'), endsWith('+llm'));

      final Object mergedFromNull = mergeTrackingHttpOptions();
      expect(mergedFromNull, isA<HttpOptions>());
      expect(
        (mergedFromNull as HttpOptions).headers['x-goog-api-client'],
        contains('google-adk/'),
      );

      final Map<String, Object?> rawMap = <String, Object?>{
        'headers': <String, String>{'X-Custom': 'val'},
      };
      final Object mergedMap = mergeTrackingHttpOptions(httpOptions: rawMap);
      expect(mergedMap, same(rawMap));
      final Map<String, String> headers =
          rawMap['headers'] as Map<String, String>;
      expect(headers['X-Custom'], 'val');
      expect(headers['user-agent'], contains('google-adk/'));
    });

    test('enforceStrictOpenAiSchema inlines root \$ref beside \$defs for recursive schemas', () {
      final Map<String, dynamic> recursiveSchema = <String, dynamic>{
        r'$ref': r'#/$defs/Node',
        r'$defs': <String, dynamic>{
          'Node': <String, dynamic>{
            'type': 'OBJECT',
            'properties': <String, dynamic>{
              'name': <String, dynamic>{'type': 'STRING'},
              'child': <String, dynamic>{r'$ref': r'#/$defs/Node'},
            },
          },
        },
      };

      schema_utils.lowercaseSchemaTypes(recursiveSchema);
      schema_utils.enforceStrictOpenAiSchema(recursiveSchema);
      expect(recursiveSchema.containsKey(r'$ref'), isFalse);
      expect(recursiveSchema['type'], 'object');
      expect(recursiveSchema['additionalProperties'], isFalse);
      expect(recursiveSchema['required'], containsAll(<String>['name', 'child']));
      final Map<String, dynamic> defs =
          recursiveSchema[r'$defs'] as Map<String, dynamic>;
      final Map<String, dynamic> nodeDef = defs['Node'] as Map<String, dynamic>;
      expect(nodeDef['additionalProperties'], isFalse);
      expect(
        (nodeDef['properties'] as Map<String, dynamic>)['child'],
        equals(<String, dynamic>{r'$ref': r'#/$defs/Node'}),
      );
    });

    test('JsonPathTracker ignores >4300-digit ints and leaves non-finite numbers valueless', () {
      final JsonPathTracker tracker = JsonPathTracker();
      final String hugeDigits = '9' * 4500;
      expect(tracker.handleChunk('{"big": $hugeDigits}'), isEmpty);

      final JsonPathTracker tracker2 = JsonPathTracker();
      final List<PartialArg> nonFinite = tracker2.handleChunk('{"inf": 1e500}');
      expect(nonFinite, hasLength(1));
      expect(nonFinite.first.jsonPath, r'$.inf');
      expect(nonFinite.first.numberValue, isNull);
      expect(nonFinite.first.stringValue, isNull);
      expect(nonFinite.first.boolValue, isNull);
    });
  });

  group('labs & integrations: classifiers client labeling', () {
    test('BaseClassifier sets classifier label and preserves outer label if set', () async {
      final _FakeClassifier classifier = _FakeClassifier();
      await classifier.classify(
        input: 'hello',
        questions: const <String, ClassifierQuestion>{},
      );
      expect(
        classifier.capturedLabels.any(
          (String l) =>
              l.startsWith('google-adk-classifier/') && l.endsWith('+fake'),
        ),
        isTrue,
      );

      await clientLabelContext('eval-harness/1.0', () async {
        await classifier.classify(
          input: 'hello',
          questions: const <String, ClassifierQuestion>{},
        );
      });
      expect(
        classifier.capturedLabels.any((String l) => l.contains('eval-harness/1.0')),
        isTrue,
      );
    });

    test('OpenAiDecisionsClassifier and TypesafeClassifier send User-Agent header', () async {
      String? openAiUserAgent;
      final OpenAiDecisionsClassifier openAiClassifier =
          OpenAiDecisionsClassifier(
            apiKey: 'sk-test',
            httpClient: MockClient((http.Request req) async {
              openAiUserAgent =
                  req.headers['User-Agent'] ?? req.headers['user-agent'];
              return http.Response(
                jsonEncode(<String, Object?>{
                  'model': 'gpt-decisions-1',
                  'decisions': <String, Object?>{
                    'q1': <String, Object?>{
                      'type': 'choice',
                      'selected': 'yes',
                      'choice': 'yes',
                      'probabilities': <String, double>{
                        'yes': 0.9,
                        'no': 0.1,
                      },
                    },
                  },
                }),
                200,
              );
            }),
          );

      await openAiClassifier.classify(
        input: 'test',
        questions: <String, ClassifierQuestion>{
          'q1': Choice(
            instructions: 'Is it safe?',
            criteria: const <String, Object?>{'yes': null, 'no': null},
          ),
        },
      );
      expect(
        openAiUserAgent,
        contains('+openai'),
      );

      String? typeSafeUserAgent;
      final TypesafeClassifier typeSafeClassifier = TypesafeClassifier(
        apiKey: 'ts-key',
        httpTransport: ({
          required Uri url,
          required Map<String, String> headers,
          required Map<String, Object?> body,
          required Duration timeout,
        }) async {
          typeSafeUserAgent = headers['User-Agent'] ?? headers['user-agent'];
          return TypesafeHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'model': 'jev-latest',
              'answers': <String, Object?>{
                'q1': <String, Object?>{
                  'type': 'choice',
                  'choice': 'yes',
                  'confidence': 0.9,
                  'probabilities': <String, double>{
                    'yes': 0.9,
                    'no': 0.1,
                  },
                },
              },
            }),
          );
        },
      );
      await typeSafeClassifier.classify(
        input: 'test',
        questions: <String, ClassifierQuestion>{
          'q1': Choice(
            instructions: 'Is it safe?',
            criteria: const <String, Object?>{'yes': null, 'no': null},
          ),
        },
      );
      expect(
        typeSafeUserAgent,
        contains('+typesafe'),
      );
    });
  });

  group('integrations: AgentRegistry, Eventarc, Firestore, OpenAI, Redis, Slack', () {
    test('AgentRegistry refreshes credentials lazily only when invalid', () async {
      final _FakeCredentials creds = _FakeCredentials(
        valid: true,
        token: 'initial-valid-token',
      );
      final AgentRegistry registry = AgentRegistry(
        projectId: 'my-proj',
        location: 'us-central1',
        credentials: creds,
      );

      final Map<String, String> headers1 = await registry.getAuthHeaders();
      expect(creds.refreshCalls, 0);
      expect(headers1['Authorization'], 'Bearer initial-valid-token');

      creds.valid = false;
      final Map<String, String> headers2 = await registry.getAuthHeaders();
      expect(creds.refreshCalls, 1);
      expect(headers2['Authorization'], 'Bearer refreshed-token-1');
    });

    test('Eventarc scopes cached publisher clients per EventarcLoopScope', () async {
      final List<_FakeEventarcPublisher> created = <_FakeEventarcPublisher>[];
      setEventarcPublisherClientFactory(({Object? credentials, String? userAgent}) {
        final _FakeEventarcPublisher client = _FakeEventarcPublisher();
        created.add(client);
        return client;
      });
      addTearDown(resetEventarcPublisherClientFactory);

      final EventarcLoopScope scope1 = EventarcLoopScope();
      final EventarcLoopScope scope2 = EventarcLoopScope();

      final EventarcPublisherClient c1 = await runWithEventarcLoopScope(
        scope1,
        () => getPublisherClient(),
      );
      final EventarcPublisherClient c1Again = await runWithEventarcLoopScope(
        scope1,
        () => getPublisherClient(),
      );
      final EventarcPublisherClient c2 = await runWithEventarcLoopScope(
        scope2,
        () => getPublisherClient(),
      );

      expect(identical(c1, c1Again), isTrue);
      expect(identical(c1, c2), isFalse);

      await runWithEventarcLoopScope(scope1, () => cleanupClients());
      expect((c1 as _FakeEventarcPublisher).closed, isTrue);
      expect((c2 as _FakeEventarcPublisher).closed, isFalse);
    });

    test('Firestore wraps nested state arrays and serializes event_data as JSON string', () async {
      final InMemoryFirestoreDatabaseClient db =
          InMemoryFirestoreDatabaseClient();
      final FirestoreSessionService service = FirestoreSessionService(
        client: db,
      );

      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_nested',
        state: <String, Object?>{
          'matrix': <Object?>[
            <Object?>[1, 2],
            <Object?>[3, 4],
          ],
          'literal_marker': <String, Object?>{'_adk_list': 'not-a-wrapper'},
        },
      );
      expect(
        session.state['matrix'],
        equals(<Object?>[
          <Object?>[1, 2],
          <Object?>[3, 4],
        ]),
      );

      await service.appendEvent(
        session: session,
        event: Event(
          id: 'ev1',
          invocationId: 'inv1',
          author: 'agent',
          content: Content.modelText('hello'),
          actions: EventActions(
            stateDelta: <String, Object?>{
              'user:nested': <Object?>[
                <Object?>['a', 'b'],
              ],
            },
          ),
        ),
      );

      final Session? loaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_nested',
      );
      expect(loaded, isNotNull);
      expect(
        loaded!.state['matrix'],
        equals(<Object?>[
          <Object?>[1, 2],
          <Object?>[3, 4],
        ]),
      );
      expect(
        loaded.state['literal_marker'],
        equals(<String, Object?>{'_adk_list': 'not-a-wrapper'}),
      );
      expect(
        loaded.state['user:nested'],
        equals(<Object?>[
          <Object?>['a', 'b'],
        ]),
      );
      expect(loaded.events, hasLength(1));
      expect(loaded.events.first.content?.parts.first.text, 'hello');
    });

    test('OpenAI Responses keeps sibling keys beside result in function_call_output', () {
      final OpenAIResponsesLlm llm = OpenAIResponsesLlm(
        model: 'gpt-4.1',
        apiKey: 'sk-test',
      );
      final Map<String, Object?> kwargs = llm.buildResponseCreateKwargs(
        LlmRequest(
          model: 'gpt-4.1',
          contents: <Content>[
            Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: 'call_1',
                  name: 'my_tool',
                  response: <String, dynamic>{'result': 'only_val'},
                ),
                Part.fromFunctionResponse(
                  id: 'call_2',
                  name: 'my_tool',
                  response: <String, dynamic>{
                    'result': 'main_val',
                    'status': 'ok',
                  },
                ),
              ],
            ),
          ],
        ),
        stream: false,
      );
      final List<Map<String, Object?>> inputItems =
          kwargs['input'] as List<Map<String, Object?>>;
      expect(inputItems[0]['output'], 'only_val');
      expect(
        jsonDecode(inputItems[1]['output'] as String),
        equals(<String, Object?>{'result': 'main_val', 'status': 'ok'}),
      );
    });

    test('RedisSessionService skips storage writes for partial events', () async {
      final RedisSessionService service = RedisSessionService();
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_redis',
      );
      final double initialUpdateTime = session.lastUpdateTime;

      final Event partialEvent = Event(
        id: 'ev_partial',
        invocationId: 'inv1',
        author: 'agent',
        partial: true,
        timestamp: initialUpdateTime + 100,
        content: Content.modelText('chunk'),
      );
      await service.appendEvent(session: session, event: partialEvent);
      expect(session.lastUpdateTime, initialUpdateTime);

      final Session? reloaded = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_redis',
      );
      expect(reloaded!.events, isEmpty);
    });

    test('SlackRunner deduplicates identical (channel, ts) events within TTL', () {
      final _FakeSlackApp slackApp = _FakeSlackApp();
      final SlackRunner slackRunner = SlackRunner(
        InMemoryRunner(agent: LlmAgent(name: 'slack_agent', instruction: 'hi')),
        slackApp,
      );

      expect(slackRunner.isDuplicateEvent('C1', '123.456'), isFalse);
      expect(slackRunner.isDuplicateEvent('C1', '123.456'), isTrue);
      expect(slackRunner.isDuplicateEvent('C2', '123.456'), isFalse);
      expect(slackRunner.isDuplicateEvent('C1', null), isFalse);
    });
  });

  group('memory: MongoDbMemoryService, SqliteMemoryService, VertexAiMemoryBankService', () {
    test('MongoDbMemoryService supports vector retrieval mode and TTL index', () async {
      final _FakeEmbedGenaiClient embedClient = _FakeEmbedGenaiClient();
      final MongoDbMemoryService service = MongoDbMemoryService(
        databaseName: 'test_db',
        connectionString: 'mongodb://localhost:27017',
        retrievalMode: 'vector',
        genaiClient: embedClient,
        embeddingOutputDimensionality: 3,
        memoryTtlDays: 7,
      );

      final Session session = Session(
        id: 'sess1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'e1',
            invocationId: 'inv1',
            author: 'user',
            timestamp: 1000,
            content: Content.userText('Dart vector search memory'),
          ),
        ],
      );

      await service.addSessionToMemory(session);
      expect(embedClient.calls, hasLength(1));

      final SearchMemoryResponse response = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'vector search',
      );
      expect(response.memories, hasLength(1));
      expect(
        response.memories.first.content.parts.first.text,
        'Dart vector search memory',
      );
    });

    test('SqliteMemoryService finds CJK, Japanese, Korean, and Thai substrings via LIKE', () async {
      final SqliteMemoryService service = SqliteMemoryService(':memory:');
      addTearDown(service.close);

      final Session session = Session(
        id: 's_cjk',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            id: 'e1',
            invocationId: 'inv1',
            author: 'user',
            timestamp: 1000,
            content: Content.userText('今天天气真好，我们去公园散步吧'),
          ),
          Event(
            id: 'e2',
            invocationId: 'inv1',
            author: 'user',
            timestamp: 1001,
            content: Content.userText('วันนี้อากาศดีมาก'),
          ),
        ],
      );
      await service.addSessionToMemory(session);

      final SearchMemoryResponse cjkResult = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: '公园',
      );
      expect(cjkResult.memories, hasLength(1));

      final SearchMemoryResponse thaiResult = await service.searchMemory(
        appName: 'app',
        userId: 'u1',
        query: 'อากาศ',
      );
      expect(thaiResult.memories, hasLength(1));
    });

    test('VertexAiMemoryBankHttpApiClient attaches tracking headers', () {
      final VertexAiMemoryBankHttpApiClient client =
          VertexAiMemoryBankHttpApiClient(
            project: 'proj',
            location: 'us-central1',
          );
      expect(client.httpOptions, isA<HttpOptions>());
      final HttpOptions opts = client.httpOptions as HttpOptions;
      expect(opts.headers['x-goog-api-client'], contains('google-adk/'));
      expect(opts.headers['user-agent'], contains('google-adk/'));
    });
  });

  group('models: Anthropic, Apigee, Interactions, LiteLLM', () {
    test('Claude downloads gs:// file parts as inline base64 and ends request on user turn', () async {
      Map<String, Object?>? capturedRequest;
      final Claude claude = Claude(
        model: 'claude-sonnet-4-20250514',
        apiInvoker: ({
          required Map<String, Object?> request,
          required bool stream,
        }) async {
          capturedRequest = request;
          return <Map<String, Object?>>[
            <String, Object?>{
              'model': 'claude-sonnet-4-20250514',
              'stop_reason': 'end_turn',
              'content': <Map<String, Object?>>[
                <String, Object?>{'type': 'text', 'text': 'Done'},
              ],
            },
          ];
        },
        gcsDownloader: (String bucket, String blobName) {
          expect(bucket, 'my-bucket');
          expect(blobName, 'docs/spec.pdf');
          return AnthropicGcsObject(
            bytes: utf8.encode('PDF-BYTES'),
            contentType: 'application/pdf',
          );
        },
      );

      final LlmRequest request = LlmRequest(
        model: 'claude-sonnet-4-20250514',
        contents: <Content>[
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFileData(
                fileUri: 'gs://my-bucket/docs/spec.pdf',
                mimeType: 'application/pdf',
              ),
            ],
          ),
          Content.modelText('Partial assistant message'),
        ],
      );

      final List<LlmResponse> responses = await claude
          .generateContent(request)
          .toList();
      expect(responses, hasLength(1));
      expect(capturedRequest, isNotNull);
      final List<Object?> messages =
          capturedRequest!['messages'] as List<Object?>;
      expect(messages, hasLength(3));
      final Map<String, Object?> firstMsg =
          messages.first as Map<String, Object?>;
      final List<Object?> firstBlocks = firstMsg['content'] as List<Object?>;
      final Map<String, Object?> docBlock =
          firstBlocks.first as Map<String, Object?>;
      expect(docBlock['type'], 'document');
      expect(
        (docBlock['source'] as Map<String, Object?>)['data'],
        base64Encode(utf8.encode('PDF-BYTES')),
      );

      final Map<String, Object?> lastMsg =
          messages.last as Map<String, Object?>;
      expect(lastMsg['role'], 'user');
    });

    test('ApigeeLlm sends max_completion_tokens for reasoning models and wraps json_schema', () {
      final LlmRequest request = LlmRequest(
        model: 'apigee/openai/v1/o3-mini',
        contents: <Content>[Content.userText('Solve')],
        config: GenerateContentConfig(
          maxOutputTokens: 512,
          temperature: 0.7,
          topP: 0.9,
          responseJsonSchema: <String, Object?>{
            'title': 'Math Answer!',
            'type': 'OBJECT',
            'properties': <String, Object?>{
              'answer': <String, Object?>{'type': 'INTEGER'},
            },
          },
        ),
      );

      final Map<String, Object?> capturedPayload =
          ApigeeLlm.buildChatCompletionsPayload(request, stream: false);
      expect(capturedPayload['max_completion_tokens'], 512);
      expect(capturedPayload.containsKey('max_tokens'), isFalse);
      expect(capturedPayload.containsKey('temperature'), isFalse);
      expect(capturedPayload.containsKey('top_p'), isFalse);

      final Map<String, Object?> responseFormat =
          capturedPayload['response_format'] as Map<String, Object?>;
      expect(responseFormat['type'], 'json_schema');
      final Map<String, Object?> jsonSchema =
          responseFormat['json_schema'] as Map<String, Object?>;
      expect(jsonSchema['name'], 'Math_Answer_');
      expect(
        (jsonSchema['schema'] as Map<String, Object?>)['type'],
        'object',
      );
    });

    test('Interactions utilities send multimodal functionResponse parts, thinking_level, and read errors list', () {
      final Part fnRespPart = Part.fromFunctionResponse(
        id: 'call_1',
        name: 'render_chart',
        response: <String, dynamic>{'ok': true},
        parts: <Part>[
          Part.fromInlineData(
            mimeType: 'image/png',
            data: <int>[1, 2, 3],
          ),
        ],
      );
      final Map<String, Object?>? converted = convertPartToInteractionContent(
        fnRespPart,
      );
      expect(converted, isNotNull);
      expect(converted!['type'], 'function_result');
      final List<Object?> resultItems = converted['result'] as List<Object?>;
      expect(resultItems, hasLength(2));
      expect((resultItems[1] as Map<String, Object?>)['type'], 'image');

      final Map<String, Object?> genConfig = buildGenerationConfig(
        GenerateContentConfig(
          thinkingConfig: <String, Object?>{
            'thinking_level': 'HIGH',
            'include_thoughts': true,
          },
        ),
      );
      expect(genConfig['thinking_level'], 'high');
      expect(genConfig['thinking_summaries'], 'auto');

      final LlmResponse failedResp = convertInteractionToLlmResponse(
        <String, Object?>{
          'id': 'int_1',
          'status': 'failed',
          'errors': <Map<String, Object?>>[
            <String, Object?>{
              'code': 'RATE_LIMIT',
              'message': 'Quota exceeded',
            },
          ],
        },
      );
      expect(failedResp.errorCode, 'RATE_LIMIT');
      expect(failedResp.errorMessage, 'Quota exceeded');
    });

    test('LiteLlm reports malformed tool call args and truncated stream without finish_reason', () async {
      final LiteLlm badToolLlm = LiteLlm(
        model: 'openai/gpt-4o',
        completionsInvoker: ({
          required Map<String, Object?> payload,
          required bool stream,
        }) async {
          return <Map<String, Object?>>[
            <String, Object?>{
              'choices': <Map<String, Object?>>[
                <String, Object?>{
                  'finish_reason': 'tool_calls',
                  'message': <String, Object?>{
                    'role': 'assistant',
                    'tool_calls': <Map<String, Object?>>[
                      <String, Object?>{
                        'id': 'tc_1',
                        'function': <String, Object?>{
                          'name': 'my_tool',
                          'arguments': '{not valid json',
                        },
                      },
                    ],
                  },
                },
              ],
            },
          ];
        },
      );

      final List<LlmResponse> badToolRes = await badToolLlm
          .generateContent(
            LlmRequest(
              model: 'openai/gpt-4o',
              contents: <Content>[Content.userText('hi')],
            ),
          )
          .toList();
      expect(badToolRes, hasLength(1));
      expect(badToolRes.single.finishReason, 'MALFORMED_FUNCTION_CALL');
      expect(badToolRes.single.errorCode, 'MALFORMED_FUNCTION_CALL');

      final LiteLlm truncatedStreamLlm = LiteLlm(
        model: 'openai/gpt-4o',
        completionsInvoker: ({
          required Map<String, Object?> payload,
          required bool stream,
        }) async {
          return <Map<String, Object?>>[
            <String, Object?>{
              'choices': <Map<String, Object?>>[
                <String, Object?>{
                  'finish_reason': null,
                  'delta': <String, Object?>{'content': 'partial answer'},
                },
              ],
            },
          ];
        },
      );
      final List<LlmResponse> streamRes = await truncatedStreamLlm
          .generateContent(
            LlmRequest(
              model: 'openai/gpt-4o',
              contents: <Content>[Content.userText('hi')],
            ),
            stream: true,
          )
          .toList();
      expect(streamRes.last.finishReason, 'OTHER');
      expect(streamRes.last.errorCode, 'OTHER');
      expect(
        streamRes.last.errorMessage,
        'The stream ended without a finish reason; the response may be truncated.',
      );
    });
  });

  group('plugins: ReflectAndRetryToolPlugin, AutoTracingPlugin, BigQueryAgentAnalyticsPlugin', () {
    test('ReflectAndRetryToolPlugin supports custom reflectionGuidance and retryExceededGuidance', () async {
      final InvocationContext invCtx = await _createInvocationContext();
      final ToolContext toolCtx = ToolContext(invCtx);
      final FunctionTool tool = FunctionTool(
        name: 'failing_tool',
        description: 'Always fails',
        func: () => throw Exception('boom'),
      );

      final ReflectAndRetryToolPlugin plugin = ReflectAndRetryToolPlugin(
        maxRetries: 1,
        throwExceptionIfRetryExceeded: false,
        reflectionGuidance: (ToolReflectionContext ctx) =>
            'Check arg ${ctx.toolArgs["x"]} on retry ${ctx.retryCount}/${ctx.maxRetries}',
        retryExceededGuidance: 'Stop calling failing_tool and ask user.',
      );

      final Map<String, dynamic>? retryResp = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: <String, dynamic>{'x': 42},
        toolContext: toolCtx,
        error: Exception('boom'),
      );
      expect(retryResp, isNotNull);
      expect(
        retryResp!['reflection_guidance'],
        contains('**Custom Guidance:**\nCheck arg 42 on retry 1/1'),
      );

      final Map<String, dynamic>? exceededResp =
          await plugin.onToolErrorCallback(
            tool: tool,
            toolArgs: <String, dynamic>{'x': 42},
            toolContext: toolCtx,
            error: Exception('boom'),
          );
      expect(exceededResp, isNotNull);
      expect(
        exceededResp!['reflection_guidance'],
        contains('**Custom Guidance:**\nStop calling failing_tool and ask user.'),
      );
    });

    test('AutoTracingPlugin closes wrapped sync and async generators on early break', () async {
      final AdkTracer localTracer = AdkTracer();
      final AutoTracingPlugin plugin = AutoTracingPlugin(tracer: localTracer);

      bool syncClosed = false;
      final CloseableSyncIterable<int> wrappedSync = plugin.wrapSyncGenerator<int>(
        'test.sync_gen',
        () sync* {
          yield 1;
          yield 2;
          yield 3;
        },
        onClose: () {
          syncClosed = true;
        },
      );
      try {
        for (final int value in wrappedSync) {
          if (value == 1) {
            break;
          }
        }
      } finally {
        wrappedSync.close();
      }
      expect(syncClosed, isTrue);
      expect(localTracer.finishedSpans.any((TraceSpanRecord s) => s.name == 'test.sync_gen'), isTrue);

      bool asyncFinallyRan = false;
      final Stream<int> wrappedAsync = plugin.wrapAsyncGenerator<int>(
        'test.async_gen',
        () async* {
          try {
            yield 10;
            yield 20;
          } finally {
            asyncFinallyRan = true;
          }
        },
      );
      await for (final int value in wrappedAsync) {
        if (value == 10) {
          break;
        }
      }
      expect(asyncFinallyRan, isTrue);
      expect(
        localTracer.finishedSpans.any((TraceSpanRecord s) => s.name == 'test.async_gen'),
        isTrue,
      );
    });

    test('BigQueryAgentAnalyticsPlugin disables GCS offload when content_parts is not persisted and builds eval SQL', () async {
      int uploadCalls = 0;
      final InMemoryBigQueryEventSink sink = InMemoryBigQueryEventSink();
      final BigQueryAgentAnalyticsPlugin plugin = BigQueryAgentAnalyticsPlugin(
        projectId: 'my-proj',
        datasetId: 'my_dataset',
        sink: sink,
        config: BigQueryLoggerConfig(
          logMultiModalContent: false,
          gcsBucketName: 'my-bucket',
          gcsUploadProvider: ({
            required List<int> data,
            required String contentType,
            required String path,
          }) async {
            uploadCalls += 1;
            return 'gs://my-bucket/$path';
          },
        ),
      );

      final InvocationContext invCtx = await _createInvocationContext();
      await plugin.onUserMessageCallback(
        invocationContext: invCtx,
        userMessage: Content(
          role: 'user',
          parts: <Part>[
            Part.text('A' * 40000),
            Part.fromInlineData(mimeType: 'image/png', data: <int>[1, 2, 3]),
          ],
        ),
      );
      expect(uploadCalls, 0);
      expect(sink.rows, hasLength(1));
      expect(sink.rows.first['content_parts'], isEmpty);

      final String sessionSql = buildEvalSessionQuerySql(
        'my-proj.my_dataset.agent_events',
        deniedColumns: const <String>['content_parts', 'attributes'],
        rawWhereClause: 'WHERE timestamp >= @lookback_start; -- comment',
        whereClause: 'WHERE eval_ready;',
      );
      expect(sessionSql, contains('TOOL_ERROR'));
      expect(sessionSql, contains('has_truncated_content'));
      expect(sessionSql, contains('timestamp >= @lookback_start'));
      expect(sessionSql, contains('WHERE\n  (\n    eval_ready\n  )'));

      final String turnViewSql = buildEvalTurnViewSql(
        'my-proj.my_dataset.agent_events',
        viewPrefix: 'custom_v',
      );
      expect(
        turnViewSql,
        startsWith(
          'CREATE OR REPLACE VIEW `my-proj.my_dataset.custom_v_eval_turn` AS\nWITH',
        ),
      );
    });
  });

  group('telemetry: experimental semconv streaming, 0.7b2 metrics, SqliteSpanExporter', () {
    test('setOperationDetailsAttributesFromResponse merges streamed output parts and recordInferenceChunk skips non-partial', () {
      final Map<String, Object?> details = <String, Object?>{};
      final Map<String, Object?> common = <String, Object?>{};

      experimental_semconv.setOperationDetailsAttributesFromResponse(
        LlmResponse(
          content: Content.modelText('Hello '),
          partial: false,
        ),
        details,
        common,
      );
      experimental_semconv.setOperationDetailsAttributesFromResponse(
        LlmResponse(
          content: Content.modelText('world!'),
          finishReason: 'STOP',
          partial: false,
        ),
        details,
        common,
      );

      final List<Map<String, Object?>> messages =
          details[experimental_semconv.genAiOutputMessages]
              as List<Map<String, Object?>>;
      expect(messages, hasLength(1));
      final List<Object?> parts = messages.first['parts'] as List<Object?>;
      expect(parts, hasLength(2));
      expect(messages.first['finish_reason'], 'stop');

      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      final GenerateContentSpan gcSpan = GenerateContentSpan(
        TraceSpanRecord('generate_content'),
        startTimeMicros: 1000,
      );
      recordInferenceChunk(
        gcSpan,
        LlmResponse(content: Content.modelText('final'), partial: false),
        nowMicros: 2000,
        recorder: recorder,
      );
      expect(recorder.records, isEmpty);
    });

    test('shouldEmitInferenceTokenMetrics emits under google-genai instrumentor 0.7b2', () {
      expect(
        shouldEmitInferenceTokenMetrics(
          system: 'gcp.gemini',
          hasGenAiInstrumentor: true,
          instrumentorVersion: '0.7b2',
          environment: const <String, String>{
            'ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION': 'v1',
          },
        ),
        isTrue,
      );
      expect(
        shouldEmitInferenceTokenMetrics(
          system: 'gcp.gemini',
          hasGenAiInstrumentor: true,
          instrumentorVersion: '0.8.0',
          environment: const <String, String>{
            'ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION': 'v1',
          },
        ),
        isFalse,
      );
    });

    test('SqliteSpanExporter persists and restores span status and events', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_sqlite_span_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final String dbPath = '${tempDir.path}/spans.db';
      final SqliteSpanExporter exporter = SqliteSpanExporter(dbPath: dbPath);
      addTearDown(exporter.shutdown);

      final ReadableSpan span = ReadableSpan(
        name: 'execute_tool',
        context: const SpanContext(
          traceId: 0x1234,
          spanId: 0x5678,
          isRemote: false,
          traceFlags: TraceFlags.sampled,
          traceState: TraceState(),
        ),
        attributes: <String, Object?>{
          'gcp.vertex.agent.session_id': 'sess_1',
          'gcp.vertex.agent.event_id': 'ev_1',
        },
        status: const SpanStatus(
          statusCode: StatusCode.error,
          description: 'Tool crashed',
        ),
        events: <SpanEvent>[
          SpanEvent(
            name: 'exception',
            timestampUnixNano: 123456789,
            attributes: <String, Object?>{'exception.message': 'Tool crashed'},
          ),
        ],
      );

      expect(exporter.export(<ReadableSpan>[span]), SpanExportResult.success);

      final List<ReadableSpan> loaded = exporter.getAllSpansForSession('sess_1');
      expect(loaded, hasLength(1));
      expect(loaded.single.status.statusCode, StatusCode.error);
      expect(loaded.single.status.description, 'Tool crashed');
      expect(loaded.single.events, hasLength(1));
      expect(loaded.single.events.single.name, 'exception');
      expect(loaded.single.events.single.timestamp, 123456789);
      expect(
        loaded.single.events.single.attributes['exception.message'],
        'Tool crashed',
      );

      final Map<String, Object?>? byEvent = exporter.getTraceByEventId('ev_1');
      expect(byEvent, isNotNull);
      expect(
        byEvent!['status'],
        equals(<String, Object?>{
          'status_code': 'ERROR',
          'description': 'Tool crashed',
        }),
      );
      expect(byEvent['events'], isA<List<Object?>>());
    });
  });
}
