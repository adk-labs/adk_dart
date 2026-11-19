import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _RecordingLlm extends BaseLlm {
  _RecordingLlm(String model, this.responseText) : super(model: model);

  final String responseText;
  final List<LlmRequest> requests = <LlmRequest>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    yield LlmResponse(
      content: Content(role: 'model', parts: <Part>[Part.text(responseText)]),
      turnComplete: true,
    );
  }
}

class _ScopedFakeEnvironment extends BaseEnvironment {
  _ScopedFakeEnvironment(this._scope);

  final EnvironmentScope _scope;
  final Map<String, Completer<void>> blockers = <String, Completer<void>>{};
  final List<String> events = <String>[];
  int activeInits = 0;
  int maxConcurrentInits = 0;
  bool closed = false;

  @override
  EnvironmentScope get scope => _scope;

  @override
  Future<void> initialize({Context? ctx}) async {
    final String tag = ctx == null
        ? 'shared'
        : '${ctx.session.userId}:${ctx.session.id}';
    events.add('init_start:$tag');
    activeInits += 1;
    if (activeInits > maxConcurrentInits) {
      maxConcurrentInits = activeInits;
    }
    try {
      final Completer<void>? blocker = blockers[tag];
      if (blocker != null) {
        await blocker.future;
      }
      isInitialized = true;
    } finally {
      activeInits -= 1;
      events.add('init_end:$tag');
    }
  }

  @override
  Future<void> close() async {
    events.add('close_start');
    closed = true;
    isInitialized = false;
    events.add('close_end');
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async => const EnvironmentExecutionResult(exitCode: 0);

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async =>
      const <int>[];

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {}
}

class _InMemorySkillEnvironment extends BaseEnvironment {
  _InMemorySkillEnvironment()
    : super(workingDirectory: Directory('/workspace'));

  final Map<String, List<int>> files = <String, List<int>>{};
  final List<String> writtenPaths = <String>[];
  final List<String> executedCommands = <String>[];

  @override
  Future<void> initialize({Context? ctx}) async {
    isInitialized = true;
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    executedCommands.add(command);
    return const EnvironmentExecutionResult(exitCode: 0, stdout: 'ran ok\n');
  }

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async {
    final String key = '$path';
    final List<int>? data = files[key];
    if (data == null) {
      throw PathNotFoundException(key, const OSError('No such file', 2));
    }
    return data;
  }

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {
    final String key = '$path';
    writtenPaths.add(key);
    files[key] = encodeWriteFileContent(content);
  }
}

class _ConflictOnceS3Fs extends InMemoryFsspecFilesystem {
  _ConflictOnceS3Fs() : super(protocol: 's3');

  bool failNextCreate = true;

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    if (mode == 'create' && failNextCreate) {
      failNextCreate = false;
      throw S3ConditionalRequestConflictException(path);
    }
    super.pipeFile(
      path,
      data,
      mode: mode,
      contentType: contentType,
      metadata: metadata,
    );
  }
}

class _FakeComputer extends BaseComputer {
  @override
  Future<(int, int)> screenSize() async => (1000, 1000);
  @override
  Future<ComputerState> openWebBrowser() async => ComputerState();
  @override
  Future<ComputerState> clickAt(int x, int y) async => ComputerState();
  @override
  Future<ComputerState> hoverAt(int x, int y) async => ComputerState();
  @override
  Future<ComputerState> typeTextAt(
    int x,
    int y,
    String text, {
    bool pressEnter = true,
    bool clearBeforeTyping = true,
  }) async => ComputerState();
  @override
  Future<ComputerState> scrollDocument(String direction) async =>
      ComputerState();
  @override
  Future<ComputerState> scrollAt(
    int x,
    int y,
    String direction,
    int magnitude,
  ) async => ComputerState();
  @override
  Future<ComputerState> wait(int seconds) async => ComputerState();
  @override
  Future<ComputerState> goBack() async => ComputerState();
  @override
  Future<ComputerState> goForward() async => ComputerState();
  @override
  Future<ComputerState> search() async => ComputerState();
  @override
  Future<ComputerState> navigate(String url) async => ComputerState(url: url);
  @override
  Future<ComputerState> keyCombination(List<String> keys) async =>
      ComputerState();
  @override
  Future<ComputerState> dragAndDrop(
    int x,
    int y,
    int destinationX,
    int destinationY,
  ) async => ComputerState();
  @override
  Future<ComputerState> currentState() async => ComputerState();
  @override
  Future<ComputerEnvironment> environment() async =>
      ComputerEnvironment.environmentBrowser;
}

class _DummySampler extends Sampler<UnstructuredSamplingResult> {
  _DummySampler();

  @override
  List<String> getTrainExampleIds() => <String>['ex1'];

  @override
  List<String> getValidationExampleIds() => <String>['ex1'];

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    return UnstructuredSamplingResult(
      scores: <String, double>{'ex1': 0.5},
      data: captureFullEvalData
          ? <String, Map<String, Object?>>{
              'ex1': <String, Object?>{'input': 'hi', 'output': 'hello'},
            }
          : null,
    );
  }
}

InvocationContext _makeInvocationContext({
  String appName = 'app',
  String userId = 'u1',
  String sessionId = 's1',
}) {
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_$sessionId',
    agent: Agent(name: 'root', model: 'gemini-2.5-flash'),
    session: Session(id: sessionId, appName: appName, userId: userId),
  );
}

void main() {
  group('1. Discovery Engine CheckGroundingClient (abcc0205b)', () {
    test('validates constructor arguments and builds regional endpoints', () {
      expect(
        () => CheckGroundingClient(environment: const <String, String>{}),
        throwsArgumentError,
      );
      expect(
        () => CheckGroundingClient(
          projectId: 'p1',
          citationThreshold: 1.5,
        ),
        throwsArgumentError,
      );
      expect(() => GroundingLimits(maxFacts: 0), throwsArgumentError);

      final CheckGroundingClient globalClient = CheckGroundingClient(
        environment: const <String, String>{'GOOGLE_CLOUD_PROJECT': 'proj-1'},
      );
      expect(
        globalClient.endpoint.toString(),
        'https://discoveryengine.googleapis.com/v1/projects/proj-1/locations/global/groundingConfigs/default_grounding_config:check',
      );

      final CheckGroundingClient euClient = CheckGroundingClient(
        projectId: 'proj-2',
        location: 'eu',
        groundingConfig: 'custom_cfg',
      );
      expect(
        euClient.endpoint.toString(),
        'https://eu-discoveryengine.googleapis.com/v1/projects/proj-2/locations/eu/groundingConfigs/custom_cfg:check',
      );
    });

    test('skips empty facts or blank answer without calling transport', () async {
      bool called = false;
      final CheckGroundingClient client = CheckGroundingClient(
        projectId: 'p1',
        transport: ({
          required Uri endpoint,
          required Map<String, Object?> requestBody,
          required Map<String, String> headers,
          required Duration timeout,
        }) async {
          called = true;
          return <String, Object?>{};
        },
      );

      final GroundingResult noFacts = await client.checkGroundingAsync(
        answerCandidate: 'Paris is in France.',
        facts: const <FactChunk>[],
      );
      expect(noFacts.status, GroundingStatus.skippedNoFacts);
      expect(noFacts.numFactsEvaluated, 0);

      final GroundingResult emptyAns = await client.checkGroundingAsync(
        answerCandidate: '   \n\t ',
        facts: <FactChunk>[FactChunk(text: 'Paris is in France.')],
      );
      expect(emptyAns.status, GroundingStatus.skippedEmpty);
      expect(emptyAns.numFactsEvaluated, 0);
      expect(called, isFalse);
    });

    test(
      'maps citations, enforces maxFacts, rejects Unicode digits, and retries transient errors',
      () async {
        int attempts = 0;
        Map<String, Object?>? capturedBody;
        Map<String, String>? capturedHeaders;
        final CheckGroundingClient client = CheckGroundingClient(
          projectId: 'p1',
          limits: GroundingLimits(maxFacts: 2),
          retryInitialDelay: Duration.zero,
          transport: ({
            required Uri endpoint,
            required Map<String, Object?> requestBody,
            required Map<String, String> headers,
            required Duration timeout,
          }) async {
            attempts += 1;
            if (attempts == 1) {
              throw const CheckGroundingApiException(
                statusCode: 503,
                status: 'UNAVAILABLE',
                message: 'temporary blip',
              );
            }
            capturedBody = requestBody;
            capturedHeaders = headers;
            return <String, Object?>{
              'supportScore': 0.87654,
              'citedChunks': <Map<String, Object?>>[
                <String, Object?>{'source': '0'},
                <String, Object?>{
                  'source': '²', // Unicode digit must not index facts!
                  'chunkText': 'Direct chunk text',
                },
              ],
              'claims': <Map<String, Object?>>[
                <String, Object?>{
                  'claimText': 'Paris is the capital.',
                  'startPos': 0,
                  'endPos': 21,
                  'citationIndices': <int>[0, 99],
                  'groundingCheckRequired': true,
                  'score': 0.912345,
                },
                <String, Object?>{
                  'claimText': 'Ignored non-checked claim.',
                  'citationIndices': <int>[0],
                  'groundingCheckRequired': false,
                },
                <String, Object?>{
                  'claimText': 'Fallback score claim.',
                  'citationIndices': <int>[1],
                  'groundingCheckRequired': true,
                },
              ],
            };
          },
        );

        final GroundingResult result = await client.checkGroundingAsync(
          answerCandidate: 'Paris is the capital.',
          facts: <FactChunk>[
            FactChunk(
              text: 'Paris is the capital of France.',
              title: 'France Wiki',
              link: 'https://example.com/france',
              attributes: const <String, String>{'lang': 'en'},
            ),
            FactChunk(text: 'Fact 2'),
            FactChunk(text: 'Fact 3 truncated'),
          ],
        );

        expect(attempts, 2);
        expect(result.status, GroundingStatus.ok);
        expect(result.numFactsEvaluated, 2);
        expect(result.supportScore, closeTo(0.87654, 1e-6));
        expect(result.numClaims, 2);
        expect(capturedHeaders?['User-Agent'], checkGroundingUserAgent);
        expect((capturedBody?['facts'] as List).length, 2);

        final List<Object?> chunks =
            result.metadata!['grounding_chunks']! as List<Object?>;
        expect(chunks.length, 2);
        final Map<String, Object?> firstCtx =
            (chunks[0]! as Map<String, Object?>)['retrieved_context']!
                as Map<String, Object?>;
        expect(firstCtx['text'], 'Paris is the capital of France.');
        expect(firstCtx['title'], 'France Wiki');
        expect(firstCtx['uri'], 'https://example.com/france');

        final List<Object?> supports =
            result.metadata!['grounding_supports']! as List<Object?>;
        expect(supports.length, 2);
        final Map<String, Object?> s0 = supports[0]! as Map<String, Object?>;
        expect(s0['grounding_chunk_indices'], <int>[0]);
        expect(s0['confidence_scores'], <double>[0.9123]);
        final Map<String, Object?> s1 = supports[1]! as Map<String, Object?>;
        expect(s1['confidence_scores'], <double>[0.8765]);
      },
    );

    test('maps token limit InvalidArgument to rejectedTooLong', () async {
      final CheckGroundingClient client = CheckGroundingClient(
        projectId: 'p1',
        transport: ({
          required Uri endpoint,
          required Map<String, Object?> requestBody,
          required Map<String, String> headers,
          required Duration timeout,
        }) async {
          throw const CheckGroundingApiException(
            statusCode: 400,
            status: 'INVALID_ARGUMENT',
            message: 'Answer candidate exceeds token limit of 1024.',
          );
        },
      );

      final GroundingResult res = await client.checkGroundingAsync(
        answerCandidate: 'very long answer',
        facts: <FactChunk>[FactChunk(text: 'fact')],
      );
      expect(res.status, GroundingStatus.rejectedTooLong);
      expect(res.numFactsEvaluated, 1);
      expect(res.error, contains('token limit'));
    });
  });

  group('2. Fsspec per-backend adapters & S3 metadata (90c3a2941, b916291fc)', () {
    setUp(() {
      overrideFeatureEnabled(FeatureName.fsspecArtifactService, true);
    });
    tearDown(() {
      resetFeatureRegistryForTest();
    });

    test('selects GcsBackendAdapter, S3BackendAdapter, GenericBackendAdapter', () {
      expect(
        FsspecBackendAdapter.forFilesystem(
          InMemoryFsspecFilesystem(protocol: 'gs'),
        ),
        isA<GcsBackendAdapter>(),
      );
      expect(
        FsspecBackendAdapter.forFilesystem(
          InMemoryFsspecFilesystem(protocol: 's3'),
        ),
        isA<S3BackendAdapter>(),
      );
      expect(
        FsspecBackendAdapter.forFilesystem(
          InMemoryFsspecFilesystem(protocol: 'memory'),
        ),
        isA<GenericBackendAdapter>(),
      );
    });

    test('S3 persists text, displayName with Unicode, fileData, customMetadata, and retries 409', () async {
      final _ConflictOnceS3Fs s3Fs = _ConflictOnceS3Fs();
      final FsspecArtifactService service = FsspecArtifactService(
        's3://my-bucket/artifacts',
        urlToFsResolver: (String url, [Map<String, Object?>? opts]) =>
            (s3Fs, 'my-bucket/artifacts'),
      );
      expect(service.backend, isA<S3BackendAdapter>());

      // First save hits 409 ConditionalRequestConflict on v0, retries and lands on v1.
      final int v1 = await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'note.txt',
        artifact: Part.text('hello s3'),
        customMetadata: const <String, Object?>{'author': 'alice'},
      );
      expect(v1, 1);

      final Part? loadedText = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'note.txt',
      );
      expect(loadedText?.text, 'hello s3');

      final ArtifactVersion? meta = await service.getArtifactVersion(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'note.txt',
      );
      expect(meta?.customMetadata, <String, Object?>{'author': 'alice'});

      // Unicode displayName round-trips via percent-encoding on S3.
      await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'report.bin',
        artifact: Part.fromInlineData(
          mimeType: 'application/octet-stream',
          data: <int>[1, 2, 3],
          displayName: '보고서 100%.bin',
        ),
      );
      final Part? loadedBin = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'report.bin',
      );
      expect(loadedBin?.inlineData?.displayName, '보고서 100%.bin');

      // List versions reads per-object S3 metadata.
      final List<ArtifactVersion> versions = await service.listArtifactVersions(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'note.txt',
      );
      expect(versions.length, 1);
      expect(versions.single.customMetadata, <String, Object?>{
        'author': 'alice',
      });
    });

    test('S3 rejects non-ASCII caller metadata, reserved keys, and key collisions', () async {
      final InMemoryFsspecFilesystem s3Fs = InMemoryFsspecFilesystem(
        protocol: 's3',
      );
      final FsspecArtifactService service = FsspecArtifactService(
        's3://my-bucket/artifacts',
        urlToFsResolver: (String url, [Map<String, Object?>? opts]) =>
            (s3Fs, 'my-bucket/artifacts'),
      );

      await expectLater(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'a.txt',
          artifact: Part.text('x'),
          customMetadata: const <String, Object?>{'note': 'héllo'},
        ),
        throwsA(isA<FsspecInputValidationError>()),
      );

      await expectLater(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'a.txt',
          artifact: Part.text('x'),
          customMetadata: const <String, Object?>{'ADKISTEXT': 'false'},
        ),
        throwsA(isA<FsspecInputValidationError>()),
      );

      await expectLater(
        () => service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'a.txt',
          artifact: Part.text('x'),
          customMetadata: const <String, Object?>{
            'foo_bar': '1',
            'foo-bar': '2',
          },
        ),
        throwsA(isA<FsspecInputValidationError>()),
      );
    });
  });

  group('3. BigQuery askDataInsights searchScope (9eb6d9d93)', () {
    tearDown(resetBigQueryInsightsStreamProvider);

    test('supports searchScope alone with snake_case normalization', () async {
      Map<String, Object?>? sentPayload;
      setBigQueryInsightsStreamProvider(({
        required Uri url,
        required Map<String, Object?> payload,
        required Map<String, String> headers,
      }) async {
        sentPayload = payload;
        return Stream<String>.fromIterable(<String>[
          '[{"systemMessage":{"text":{"parts":["42 orders"]}}}]',
        ]);
      });

      final Map<String, Object?> result = await askDataInsights(
        projectId: 'my-proj',
        userQueryWithContext: 'How many orders?',
        credentials: const <String, Object?>{'access_token': 'tok-1'},
        searchScope: const <String, Object?>{
          'include_project_ids': <String>[' proj-a '],
          'include_dataset_references': <Map<String, Object?>>[
            <String, Object?>{'project_id': 'proj-b', 'dataset_id': 'sales'},
          ],
        },
      );

      expect(result['status'], 'SUCCESS');
      final Map<String, Object?> inlineCtx =
          sentPayload!['inlineContext']! as Map<String, Object?>;
      final Map<String, Object?> bq =
          (inlineCtx['datasourceReferences']! as Map<String, Object?>)['bq']!
              as Map<String, Object?>;
      expect(bq.containsKey('tableReferences'), isFalse);
      expect(bq['searchScope'], <String, Object?>{
        'includeProjectIds': <String>['proj-a'],
        'includeDatasetReferences': <Map<String, String>>[
          <String, String>{'projectId': 'proj-b', 'datasetId': 'sales'},
        ],
      });
    });

    test('validates searchScope errors cleanly', () async {
      final Map<String, Object?> neither = await askDataInsights(
        projectId: 'p',
        userQueryWithContext: 'q',
        credentials: const <String, Object?>{'access_token': 'tok'},
      );
      expect(neither['status'], 'ERROR');
      expect(
        neither['error_details'],
        contains('At least one of table_references or search_scope'),
      );

      final Map<String, Object?> dupKey = await askDataInsights(
        projectId: 'p',
        userQueryWithContext: 'q',
        credentials: const <String, Object?>{'access_token': 'tok'},
        searchScope: const <String, Object?>{
          'includeProjectIds': <String>['a'],
          'include_project_ids': <String>['b'],
        },
      );
      expect(dupKey['status'], 'ERROR');
      expect(dupKey['error_details'], contains('more than once'));

      final Map<String, Object?> tooMany = await askDataInsights(
        projectId: 'p',
        userQueryWithContext: 'q',
        credentials: const <String, Object?>{'access_token': 'tok'},
        searchScope: <String, Object?>{
          'includeProjectIds': List<String>.generate(101, (int i) => 'p$i'),
        },
      );
      expect(tooMany['status'], 'ERROR');
      expect(tooMany['error_details'], contains('100'));
    });
  });

  group('4. Unified isGoogleApisUrl across registries & MCP (72578551c)', () {
    test('ApiRegistry attaches auth headers only to https://*.googleapis.com', () async {
      final ApiRegistry registry = await ApiRegistry.create(
        apiRegistryProjectId: 'p1',
        authHeadersProvider: () async => <String, String>{
          'Authorization': 'Bearer secret',
        },
        httpGetProvider: (Uri uri, {required Map<String, String> headers}) async {
          return ApiRegistryHttpResponse(
            statusCode: 200,
            body: <String, Object?>{
              'mcpServers': <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'google_srv',
                  'urls': <String>['https://mcp.googleapis.com/v1'],
                },
                <String, Object?>{
                  'name': 'spoofed_srv',
                  'urls': <String>['https://evil@mcp.googleapis.com/v1'],
                },
                <String, Object?>{
                  'name': 'third_party',
                  'urls': <String>['https://example.com/mcp'],
                },
              ],
            },
          );
        },
      );

      final StreamableHTTPConnectionParams googleParams =
          registry.getToolset('google_srv').connectionParams
              as StreamableHTTPConnectionParams;
      final StreamableHTTPConnectionParams spoofedParams =
          registry.getToolset('spoofed_srv').connectionParams
              as StreamableHTTPConnectionParams;
      final StreamableHTTPConnectionParams thirdPartyParams =
          registry.getToolset('third_party').connectionParams
              as StreamableHTTPConnectionParams;

      expect(googleParams.headers['Authorization'], 'Bearer secret');
      expect(spoofedParams.headers.containsKey('Authorization'), isFalse);
      expect(thirdPartyParams.headers.containsKey('Authorization'), isFalse);
    });

    test('AgentRegistry rejects userinfo/backslash/bare googleapis URLs for Google auth', () async {
      final AgentRegistry registry = AgentRegistry(
        projectId: 'p1',
        location: 'us-central1',
        authHeadersProvider: () async => <String, String>{
          'Authorization': 'Bearer gcp-token',
        },
        httpGetProvider: (Uri uri, {required Map<String, String> headers}) async {
          return AgentRegistryHttpResponse(
            statusCode: 200,
            body: <String, Object?>{
              'name': 'projects/p1/locations/us-central1/mcpServers/s1',
              'displayName': 'spoofed',
              'interfaces': <Map<String, Object?>>[
                <String, Object?>{
                  'url': 'https://attacker@evil.googleapis.com/mcp',
                  'protocolBinding': 'JSONRPC',
                },
              ],
            },
          );
        },
      );

      final McpToolset toolset = await registry.getMcpToolset(
        'projects/p1/locations/us-central1/mcpServers/s1',
      );
      final StreamableHTTPConnectionParams params =
          toolset.connectionParams as StreamableHTTPConnectionParams;
      expect(params.headers.containsKey('Authorization'), isFalse);
    });

    test('McpSessionManager.mergeHeaders excludes runtime tag for non-googleapis URLs', () {
      final McpSessionManager manager = McpSessionManager.instance;
      final Map<String, String>? nonGoogleHeaders = manager.mergeHeaders(
        StreamableHTTPConnectionParams(url: 'https://thirdparty.example.com/mcp'),
      );
      final Map<String, String>? googleHeaders = manager.mergeHeaders(
        StreamableHTTPConnectionParams(url: 'https://mcp.googleapis.com/v1'),
      );
      expect(nonGoogleHeaders, isNotNull);
      expect(googleHeaders, isNotNull);
      expect(nonGoogleHeaders!['user-agent'], contains('google-adk/'));
      expect(googleHeaders!['user-agent'], contains('google-adk/'));
    });
  });

  group('5. RedisSessionService.getSession filtering order (b7c9c40f8)', () {
    test('applies afterTimestamp before numRecentEvents so out-of-order events are not dropped', () async {
      final RedisSessionService service = RedisSessionService();
      final Session session = await service.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );
      // Append out of timestamp order: [ts=100, ts=50]
      await service.appendEvent(
        session: session,
        event: Event(
          invocationId: 'i1',
          author: 'user',
          timestamp: 100.0,
          content: Content(role: 'user', parts: <Part>[Part.text('newer')]),
        ),
      );
      await service.appendEvent(
        session: session,
        event: Event(
          invocationId: 'i2',
          author: 'user',
          timestamp: 50.0,
          content: Content(role: 'user', parts: <Part>[Part.text('older')]),
        ),
      );

      final Session? fetched = await service.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        config: GetSessionConfig(afterTimestamp: 80.0, numRecentEvents: 1),
      );
      expect(fetched, isNotNull);
      expect(fetched!.events.length, 1);
      expect(fetched.events.single.timestamp, 100.0);
    });
  });

  group('6. VMaaS AgentEngineEnvironment & SandboxManager state (fa9ae7e01)', () {
    test('AgentEngineEnvironment drops owned sandbox, preserves named sandbox, and rejects explicit client', () async {
      final AgentEngineEnvironment owned = AgentEngineEnvironment(
        agentEngineResourceName:
            'projects/p/locations/us-central1/reasoningEngines/1',
      );
      await owned.initialize();
      expect(owned.isInitialized, isTrue);

      final Map<String, Object?> state = owned.toSerializableState();
      expect(state['sandboxResourceName'], isNull);
      final AgentEngineEnvironment restored =
          AgentEngineEnvironment.fromSerializableState(state);
      expect(restored.isInitialized, isFalse);
      expect(restored.sandboxResourceName, isNull);

      final AgentEngineEnvironment named = AgentEngineEnvironment(
        sandboxResourceName:
            'projects/p/locations/us-central1/reasoningEngines/1/sandboxEnvironments/sb1',
      );
      await named.initialize();
      final AgentEngineEnvironment restoredNamed =
          AgentEngineEnvironment.fromSerializableState(
            named.toSerializableState(),
          );
      expect(restoredNamed.isInitialized, isFalse);
      expect(restoredNamed.sandboxResourceName, named.sandboxResourceName);

      final AgentEngineEnvironment withClient = AgentEngineEnvironment(
        agentEngineResourceName:
            'projects/p/locations/us-central1/reasoningEngines/1',
        client: ShellBackedAgentEngineSandboxClient(
          commandRunner: ({
            required String sandboxResourceName,
            required String command,
            String? workingDir,
            Duration? timeout,
            Map<String, String>? envVars,
          }) async => const EnvironmentExecutionResult(exitCode: 0),
        ),
      );
      expect(() => withClient.toSerializableState(), throwsUnsupportedError);
    });

    test('SandboxManager serializes when owning client and throws when given explicit client', () {
      final SandboxManager owned = SandboxManager(
        projectId: 'p1',
        location: 'europe-west1',
      );
      final SandboxManager restored = SandboxManager.fromSerializableState(
        owned.toSerializableState(),
      );
      expect(restored.projectId, 'p1');
      expect(restored.location, 'europe-west1');

      final SandboxManager withExternal = SandboxManager(
        projectId: 'p1',
        controlClient: InMemoryVmaasVertexAiControlClient(
          projectId: 'p1',
          location: 'us-central1',
        ),
      );
      expect(() => withExternal.toSerializableState(), throwsUnsupportedError);
    });
  });

  group('7. EnvironmentScope & per-scope locking (691ecbeed)', () {
    test('session-scoped environment runs different sessions concurrently and cleans up locks', () async {
      final _ScopedFakeEnvironment env = _ScopedFakeEnvironment(
        EnvironmentScope.session,
      );
      expect(env.scope, EnvironmentScope.session);

      // Missing context throws ArgumentError for scoped environments.
      await expectLater(() => ensureInitialized(env), throwsArgumentError);

      final Completer<void> s1Gate = Completer<void>();
      final Completer<void> s2Gate = Completer<void>();
      env.blockers['u1:s1'] = s1Gate;
      env.blockers['u1:s2'] = s2Gate;

      final Context ctx1 = Context(_makeInvocationContext(sessionId: 's1'));
      final Context ctx2 = Context(_makeInvocationContext(sessionId: 's2'));

      final Future<void> f1 = ensureInitialized(env, ctx1);
      final Future<void> f2 = ensureInitialized(env, ctx2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(env.maxConcurrentInits, 2);

      // Close waits for both in-flight initializations.
      final Future<void> closeFuture = closeIfInitialized(env);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(env.closed, isFalse);

      s1Gate.complete();
      s2Gate.complete();
      await Future.wait(<Future<void>>[f1, f2, closeFuture]);
      expect(env.closed, isTrue);
      expect(activeEnvironmentLockCount(env), 0);
    });

    test('user-scoped environment serializes two sessions of same user', () async {
      final _ScopedFakeEnvironment env = _ScopedFakeEnvironment(
        EnvironmentScope.user,
      );
      final Completer<void> gate = Completer<void>();
      env.blockers['u1:s1'] = gate;

      final Context ctx1 = Context(
        _makeInvocationContext(userId: 'u1', sessionId: 's1'),
      );
      final Context ctx2 = Context(
        _makeInvocationContext(userId: 'u1', sessionId: 's2'),
      );

      final Future<void> f1 = ensureInitialized(env, ctx1);
      final Future<void> f2 = ensureInitialized(env, ctx2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(env.maxConcurrentInits, 1);

      gate.complete();
      await Future.wait(<Future<void>>[f1, f2]);
      expect(env.maxConcurrentInits, 1);
      expect(activeEnvironmentLockCount(env), 0);
    });
  });

  group('8. SkillToolset lazy refresh & .adk_skill_hash (5f2f2279c, d94b5e214)', () {
    test('does not write to env on request build; refreshes stale skill on script run', () async {
      final _InMemorySkillEnvironment env = _InMemorySkillEnvironment();
      final SkillRegistry registry = SkillRegistry();
      registry.register(
        Skill(
          frontmatter: Frontmatter(name: 'demo', description: 'Demo skill'),
          instructions: 'v1 instructions',
          resources: Resources(
            scripts: <String, Script>{'run.py': Script(src: 'print("v1")')},
          ),
        ),
      );
      final SkillToolset toolset = SkillToolset(
        registry: registry,
        environment: env,
        lifecycleConfig: SkillLifecycleConfig(
          enabled: true,
          revalidateSkills: true,
        ),
      );

      final ToolContext ctx = ToolContext(_makeInvocationContext());
      final List<BaseTool> tools = await toolset.getTools();
      final BaseTool loadTool = tools.firstWhere(
        (BaseTool t) => t.name == 'load_skill',
      );
      final BaseTool runTool = tools.firstWhere(
        (BaseTool t) => t.name == 'run_skill_script',
      );

      await loadTool.run(
        args: <String, dynamic>{'skill_name': 'demo'},
        toolContext: ctx,
      );
      await runTool.run(
        args: <String, dynamic>{'skill_name': 'demo', 'file_path': 'run.py'},
        toolContext: ctx,
      );
      expect(env.files.containsKey('/workspace/skills/demo/.adk_skill_hash'), isTrue);
      expect(
        utf8.decode(env.files['/workspace/skills/demo/scripts/run.py']!),
        'print("v1")',
      );
      final int writesAfterV1 = env.writtenPaths.length;

      // Update skill in registry to v2.
      registry.register(
        Skill(
          frontmatter: Frontmatter(name: 'demo', description: 'Demo skill'),
          instructions: 'v2 instructions',
          resources: Resources(
            scripts: <String, Script>{'run.py': Script(src: 'print("v2")')},
          ),
        ),
      );

      // On the next turn (new invocationId on the same session),
      // processLlmRequest restates v2 instructions WITHOUT writing to env!
      final InvocationContext turn2Inv = InvocationContext(
        sessionService: ctx.invocationContext.sessionService,
        invocationId: 'inv_turn_2',
        agent: ctx.invocationContext.agent,
        session: ctx.session,
      );
      final ToolContext turn2Ctx = ToolContext(turn2Inv);
      final LlmRequest req = LlmRequest(model: 'gemini-2.5-flash');
      await toolset.processLlmRequest(toolContext: turn2Ctx, llmRequest: req);
      expect(req.config.systemInstruction, contains('v2 instructions'));
      expect(env.writtenPaths.length, writesAfterV1);

      // Running the script refreshes the stale copy in env.
      await runTool.run(
        args: <String, dynamic>{'skill_name': 'demo', 'file_path': 'run.py'},
        toolContext: turn2Ctx,
      );
      expect(
        utf8.decode(env.files['/workspace/skills/demo/scripts/run.py']!),
        'print("v2")',
      );
      expect(env.writtenPaths.length, greaterThan(writesAfterV1));
    });
  });

  group('9. ModelConsultTool SDK thinking levels & reporting (8fa57e82a, c74df83c0)', () {
    test('resolveThinkingLevel accepts xhigh and rejects invalid values', () {
      expect(resolveThinkingLevel('minimal'), 'MINIMAL');
      expect(resolveThinkingLevel('XHIGH'), 'XHIGH');
      expect(resolveThinkingLevel('off'), isNull);
      expect(resolveThinkingLevel('none'), isNull);
      expect(resolveThinkingLevel(null), isNull);
      expect(
        () => resolveThinkingLevel('thinking_level_unspecified'),
        throwsArgumentError,
      );
      expect(() => resolveThinkingLevel('ultra'), throwsArgumentError);
    });

    test('ModelConsultTool sends and reports actual thinking_level', () async {
      final _RecordingLlm llm = _RecordingLlm('gemini-4.0-pro', 'Use X.');
      final ModelConsultTool tool = ModelConsultTool(
        model: llm,
        thinkingLevel: 'XHIGH',
      );
      expect(tool.thinkingLevel, 'xhigh');

      final ToolContext ctx = ToolContext(_makeInvocationContext());
      final Object? res = await tool.run(
        args: <String, dynamic>{'question': 'What should I do?'},
        toolContext: ctx,
      );
      expect(res, isA<Map<String, Object?>>());
      final Map<String, Object?> map = res! as Map<String, Object?>;
      expect(map['thinking_level'], 'xhigh');
      expect(
        llm.requests.single.config.thinkingConfig,
        <String, Object?>{'thinking_level': 'XHIGH'},
      );
    });
  });

  group('10. Gemini 4+ thinking_level in SemanticArgMatcher, Simulators & Optimizers (fa7b20458, 36ac021eb)', () {
    test('SemanticArgMatcher uses thinking_level LOW on Gemini 4+ and thinking_budget 512 on Gemini 2.5', () async {
      overrideFeatureEnabled(FeatureName.toolArgsMatcher, true);
      addTearDown(resetFeatureRegistryForTest);

      final _RecordingLlm g4Llm = _RecordingLlm(
        'gemini-4.0-flash',
        '{"matched": true, "score": 1.0, "reason": "same"}',
      );
      final SemanticArgMatcher g4Matcher = SemanticArgMatcher(
        model: 'gemini-4.0-flash',
        llm: g4Llm,
      );
      await g4Matcher.matchAsync(
        toolName: 'search',
        argName: 'q',
        expected: 'cats',
        actual: 'felines',
      );
      expect(g4Llm.requests.single.config.thinkingConfig, <String, Object?>{
        'include_thoughts': false,
        'thinking_level': 'LOW',
      });

      final _RecordingLlm g25Llm = _RecordingLlm(
        'gemini-2.5-flash',
        '{"matched": true, "score": 1.0, "reason": "same"}',
      );
      final SemanticArgMatcher g25Matcher = SemanticArgMatcher(
        model: 'gemini-2.5-flash',
        llm: g25Llm,
      );
      await g25Matcher.matchAsync(
        toolName: 'search',
        argName: 'q',
        expected: 'cats',
        actual: 'felines',
      );
      expect(g25Llm.requests.single.config.thinkingConfig, <String, Object?>{
        'include_thoughts': false,
        'thinking_budget': 512,
      });
    });

    test('LlmBackedUserSimulator sends thinking_level MEDIUM on Gemini 4+', () async {
      final _RecordingLlm g4Llm = _RecordingLlm('gemini-4.0-flash', 'Next msg');
      final LlmBackedUserSimulator sim = LlmBackedUserSimulator(
        config: LlmBackedUserSimulatorConfig(model: 'gemini-4.0-flash'),
        conversationScenario: ConversationScenario(
          startingPrompt: 'Hello',
          conversationPlan: 'Ask for help',
        ),
        llmFactory: (_) => g4Llm,
      );
      // Turn 0 returns startingPrompt; turn 1 invokes LLM.
      await sim.getNextUserMessage(const <Event>[]);
      await sim.getNextUserMessage(<Event>[
        Event(
          invocationId: 'i1',
          author: 'agent',
          content: Content(role: 'model', parts: <Part>[Part.text('Hi!')]),
        ),
      ]);
      expect(g4Llm.requests.single.config.thinkingConfig, <String, Object?>{
        'include_thoughts': true,
        'thinking_level': 'MEDIUM',
      });
    });

    test('SimplePromptOptimizer & GepaRootAgentPromptOptimizer send thinking_level HIGH on Gemini 4+', () async {
      final _RecordingLlm simpleLlm = _RecordingLlm(
        'gemini-4.0-pro',
        'Better prompt',
      );
      final SimplePromptOptimizer simple = SimplePromptOptimizer(
        SimplePromptOptimizerConfig(
          optimizerModel: simpleLlm,
          numIterations: 1,
          batchSize: 1,
        ),
      );
      await simple.optimize(
        Agent(name: 'a', model: 'gemini-2.5-flash', instruction: 'old'),
        _DummySampler(),
      );
      expect(simpleLlm.requests.single.config.thinkingConfig, <String, Object?>{
        'include_thoughts': true,
        'thinking_level': 'HIGH',
      });

      final _RecordingLlm gepaLlm = _RecordingLlm(
        'gemini-4.0-pro',
        'Better gepa prompt',
      );
      final GepaRootAgentPromptOptimizer gepa = GepaRootAgentPromptOptimizer(
        GepaRootAgentPromptOptimizerConfig(
          optimizerModel: gepaLlm,
          maxMetricCalls: 2,
          reflectionMinibatchSize: 1,
        ),
      );
      await gepa.optimize(
        Agent(name: 'a', model: 'gemini-2.5-flash', instruction: 'old'),
        _DummySampler(),
      );
      expect(gepaLlm.requests.first.config.thinkingConfig, <String, Object?>{
        'include_thoughts': true,
        'thinking_level': 'HIGH',
      });
    });
  });

  group('11. summarizeCrossRunCriteria (b64b540c1)', () {
    test('computes per-criterion mean in config order and tracks numCasesWithValue', () {
      final List<MultiRunCaseResult> cases = <MultiRunCaseResult>[
        MultiRunCaseResult(
          evalSetId: 'set1',
          evalId: 'c1',
          finalEvalStatus: EvalStatus.passed,
          crossRunResults: <MethodResult>[
            MethodResult(
              name: 'pass@3',
              value: 1.0,
              status: EvalStatus.passed,
            ),
            MethodResult(
              name: 'pass^3',
              value: 0.5,
              status: EvalStatus.failed,
            ),
          ],
        ),
        MultiRunCaseResult(
          evalSetId: 'set1',
          evalId: 'c2',
          finalEvalStatus: EvalStatus.failed,
          crossRunResults: <MethodResult>[
            MethodResult(
              name: 'pass@3',
              value: 0.5,
              status: EvalStatus.failed,
            ),
            MethodResult(
              name: 'pass^3',
              value: null,
              status: EvalStatus.notEvaluated,
            ),
          ],
        ),
        MultiRunCaseResult(
          evalSetId: 'set1',
          evalId: 'c3',
          finalEvalStatus: EvalStatus.notEvaluated,
          crossRunResults: const <MethodResult>[],
        ),
      ];

      final List<CrossRunCriterionSummary> summaries =
          summarizeCrossRunCriteria(cases);
      expect(summaries.length, 2);
      expect(summaries[0].name, 'pass@3');
      expect(summaries[0].mean, closeTo(0.75, 1e-9));
      expect(summaries[0].numCasesWithValue, 2);
      expect(summaries[0].numCases, 3);

      expect(summaries[1].name, 'pass^3');
      expect(summaries[1].mean, closeTo(0.5, 1e-9));
      expect(summaries[1].numCasesWithValue, 1);
      expect(summaries[1].numCases, 3);

      expect(summarizeCrossRunCriteria(const <MultiRunCaseResult>[]), isEmpty);
    });
  });

  group('12. Classifiers excludeRuntimeTag & ComputerUseToolset geminiMajorVersion', () {
    test('OpenAIDecisionsClassifier omits hosting runtime tag from User-Agent', () async {
      String? capturedUserAgent;
      final MockClient mockHttp = MockClient((http.Request request) async {
        capturedUserAgent = request.headers['User-Agent'];
        return http.Response(
          jsonEncode(<String, Object?>{
            'model': 'gpt-6-luna',
            'decisions': <String, Object?>{
              'ok': <String, Object?>{
                'type': 'predicate',
                'probability_true': 0.9,
              },
            },
          }),
          200,
        );
      });
      final OpenAIDecisionsClassifier classifier = OpenAIDecisionsClassifier(
        apiKey: 'sk-test',
        httpClient: mockHttp,
      );
      await classifier.classify(
        input: 'hello',
        questions: <String, ClassifierQuestion>{
          'ok': Binary(instructions: 'Is this ok?'),
        },
      );
      expect(capturedUserAgent, isNotNull);
      expect(capturedUserAgent, contains('google-adk/'));
      expect(capturedUserAgent, isNot(contains('gce')));
      expect(capturedUserAgent, isNot(contains('cloud_run')));
    });

    test('TypesafeClassifier omits hosting runtime tag from User-Agent', () async {
      String? capturedUserAgent;
      final TypesafeClassifier classifier = TypesafeClassifier(
        apiKey: 'ts-test',
        httpTransport: ({
          required Uri url,
          required Map<String, String> headers,
          required Map<String, Object?> body,
          required Duration timeout,
        }) async {
          capturedUserAgent = headers['User-Agent'];
          return TypesafeHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'model': 'jev-latest',
              'answers': <String, Object?>{
                'ok': <String, Object?>{'type': 'noul', 'noul': 0.8},
              },
            }),
          );
        },
      );
      await classifier.classify(
        input: 'hello',
        questions: <String, ClassifierQuestion>{
          'ok': Binary(instructions: 'Is this ok?'),
        },
      );
      expect(capturedUserAgent, isNotNull);
      expect(capturedUserAgent, contains('google-adk/'));
    });

    test('ComputerUseToolset maps legacy exclusions for Vertex/models-prefixed Gemini 3+ models', () async {
      final ComputerUseToolset toolset = ComputerUseToolset(
        computer: _FakeComputer(),
        excludedPredefinedFunctions: const <String>['click_at'],
      );
      final ToolContext ctx = ToolContext(_makeInvocationContext());
      final LlmRequest req = LlmRequest(
        model: 'publishers/google/models/gemini-4.0-pro',
      );
      await toolset.processLlmRequest(toolContext: ctx, llmRequest: req);
      final Map<String, Object?> computerUse =
          req.config.tools!.first.computerUse! as Map<String, Object?>;
      expect(computerUse['excludedPredefinedFunctions'], <String>['click']);
    });

    test('CheckGroundingClient retries TimeoutException and returns apiError', () async {
      int attempts = 0;
      final CheckGroundingClient client = CheckGroundingClient(
        projectId: 'p1',
        authHeadersProvider: () async => <String, String>{},
        transport: ({
          required Uri endpoint,
          required Map<String, Object?> requestBody,
          required Map<String, String> headers,
          required Duration timeout,
        }) async {
          attempts += 1;
          throw TimeoutException('deadline exceeded', timeout);
        },
        timeout: const Duration(milliseconds: 50),
        maxRetries: 1,
        retryInitialDelay: Duration.zero,
      );
      addTearDown(client.close);

      final GroundingResult result = await client.checkGroundingAsync(
        answerCandidate: 'Earth is round.',
        facts: <FactChunk>[FactChunk(text: 'Earth is a sphere.')],
      );
      expect(result.status, GroundingStatus.apiError);
      expect(result.error, contains('timed out'));
      expect(attempts, 2);
    });
  });
}
