import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_dart.dart' hide Invocation;
import 'package:adk_dart/src/models/gemini_rest_api_client.dart'
    show GeminiRestTransport;
import 'package:test/test.dart';

class _RecordingMetricsRecorder extends AdkMetricsRecorder {
  final List<dynamic> records = <dynamic>[];

  @override
  void record(covariant dynamic metric) {
    records.add(metric);
  }
}

class _StubAdvisorLlm extends BaseLlm {
  _StubAdvisorLlm({super.model = 'gemini-2.5-pro', required this.chunks});

  final List<LlmResponse> chunks;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    for (final LlmResponse chunk in chunks) {
      yield chunk;
    }
  }
}

class _CapturingRestTransport implements GeminiRestTransport {
  final List<Map<String, Object?>> capturedPayloads = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> generateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async {
    capturedPayloads.add(
      jsonDecode(jsonEncode(payload)) as Map<String, Object?>,
    );
    return <String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'role': 'model',
            'parts': <Object?>[
              <String, Object?>{'text': 'ok'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    };
  }

  @override
  Stream<Map<String, Object?>> streamGenerateContent({
    required String model,
    required String apiKey,
    required Map<String, Object?> payload,
    String? baseUrl,
    required String apiVersion,
    Map<String, String>? headers,
    HttpRetryOptions? retryOptions,
  }) async* {
    yield await generateContent(
      model: model,
      apiKey: apiKey,
      payload: payload,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      headers: headers,
      retryOptions: retryOptions,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingLiveSession implements GeminiLiveSession {
  LlmRequest? capturedInitialRequest;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SingleValueLiveStreamingTool extends FunctionTool {
  _SingleValueLiveStreamingTool({
    required String name,
    required this.singleValue,
  }) : super(
         func: () async* {
           yield singleValue;
         },
         name: name,
         description: 'Live streaming tool returning a single non-Stream value',
       );

  final Map<String, Object?> singleValue;

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return singleValue;
  }
}

class _StaticTextLlm extends BaseLlm {
  _StaticTextLlm(this.replyText) : super(model: 'gemini-2.5-flash');

  final String replyText;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText(replyText),
      turnComplete: true,
    );
  }
}

class _ScriptedToolCallingLlm extends BaseLlm {
  _ScriptedToolCallingLlm(this.steps) : super(model: 'gemini-2.5-flash');

  final List<LlmResponse Function(LlmRequest request, int callIndex)> steps;
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final int current = _index;
    _index += 1;
    yield steps[current](request, current);
  }
}

class _CustomJsonCredentialHolder {
  _CustomJsonCredentialHolder({
    required this.liveHttp,
    required this.serializedHttpNoAuthType,
    required this.serializedOAuth2NoAuthType,
    required this.serializedServiceAccountNoAuthType,
  });

  final HttpCredentials liveHttp;
  final Map<String, Object?> serializedHttpNoAuthType;
  final Map<String, Object?> serializedOAuth2NoAuthType;
  final Map<String, Object?> serializedServiceAccountNoAuthType;

  Map<String, Object?> toJson() => <String, Object?>{
    'live_http': liveHttp,
    'http_json': serializedHttpNoAuthType,
    'oauth2_json': serializedOAuth2NoAuthType,
    'sa_json': serializedServiceAccountNoAuthType,
    'public_label': 'safe-metadata',
  };
}

class _CustomToMapCredentialHolder {
  _CustomToMapCredentialHolder(this.secretMap);

  final Map<String, Object?> secretMap;

  Map<String, Object?> toMap() => secretMap;
}

class _RecordingBigQuerySink implements BigQueryEventSink {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  @override
  Future<void> append(Map<String, Object?> row) async {
    rows.add(jsonDecode(jsonEncode(row)) as Map<String, Object?>);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

Future<List<LiveRequest>> _drainLiveQueue(LiveRequestQueue queue) async {
  queue.close();
  final List<LiveRequest> items = <LiveRequest>[];
  while (true) {
    final LiveRequest req = await queue.get();
    if (req.close) {
      break;
    }
    items.add(req);
  }
  return items;
}

Future<InvocationContext> _createInvocationContext({
  required BaseAgent agent,
  RunConfig? runConfig,
  List<BasePlugin>? plugins,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'parity_app',
    userId: 'user_1',
  );
  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'e-parent-inv-1',
    agent: agent,
    session: session,
    runConfig: runConfig,
    pluginManager: PluginManager(plugins: plugins),
  );
}

class _StubA2aClient implements A2aClient {
  _StubA2aClient(this.events);
  final List<Object> events;

  @override
  Stream<Object> sendMessage({
    required A2aMessage request,
    Map<String, Object?>? requestMetadata,
    A2aClientCallContext? context,
  }) => Stream<Object>.fromIterable(events);
}

class _StubA2aClientFactory implements A2aClientFactory {
  _StubA2aClientFactory(this.client);
  final A2aClient client;

  @override
  A2aClient create(AgentCard agentCard) => client;
}

Object? _decoded(Object? v) => v is String ? jsonDecode(v) : v;

class _FakeServer {
  Future<void> close({bool force = false}) async {}
}

final Map<AgentCard, A2aClientFactory> _factories =
    <AgentCard, A2aClientFactory>{};

A2aClientFactory _factoryFor(AgentCard card) => _factories[card]!;

Future<(_FakeServer, AgentCard)> _startLocalA2aServer(
  Map<String, Object?> task,
) async {
  final Map<String, Object?> status = task['status']! as Map<String, Object?>;
  final String rawState = status['state']! as String;
  final A2aTaskState state = rawState.toLowerCase().contains('failed')
      ? A2aTaskState.failed
      : A2aTaskState.completed;
  A2aMessage? message;
  final Map<String, Object?>? rawMessage =
      status['message'] as Map<String, Object?>?;
  if (rawMessage != null) {
    final List<A2aPart> parts = <A2aPart>[
      for (final Object? part in rawMessage['parts']! as List<Object?>)
        A2aPart.text((part! as Map<String, Object?>)['text']! as String),
    ];
    message = A2aMessage(
      messageId: rawMessage['messageId']! as String,
      role: A2aRole.agent,
      parts: parts,
    );
  }
  final A2aTask a2aTask = A2aTask(
    id: task['id']! as String,
    contextId: task['contextId']! as String,
    metadata: task['metadata'] as Map<String, Object?>?,
    status: A2aTaskStatus(state: state, message: message),
  );
  final AgentCard card = AgentCard(
    name: 'currency',
    description: 'Remote A2A agent',
    url: 'https://remote.example/rpc',
    version: '1.0.0',
  );
  _factories[card] = _StubA2aClientFactory(
    _StubA2aClient(<Object>[(a2aTask, null)]),
  );
  return (_FakeServer(), card);
}

void main() {
  group(
    '1. f9d948c58: ModelConsultTool advisor telemetry guard & provider alignment',
    () {
      tearDown(() {
        setGenAiInstrumentationDetectorForTest(() => false);
        setGenAiInstrumentorVersionForTest(null);
        tracer.clear();
      });

      test(
        'records client duration/tokens when isGenAiInstrumented is true and TelemetryConfig opts into stable semconv',
        () async {
          setGenAiInstrumentationDetectorForTest(() => true);
          setGenAiInstrumentorVersionForTest('0.7b2');
          final _RecordingMetricsRecorder recorder =
              _RecordingMetricsRecorder();
          final _StubAdvisorLlm advisorLlm = _StubAdvisorLlm(
            model: 'gemini-2.5-pro',
            chunks: <LlmResponse>[
              LlmResponse(
                modelVersion: 'gemini-2.5-pro-002',
                partial: true,
                content: Content.modelText('Use '),
                usageMetadata: <String, Object?>{
                  'prompt_token_count': 42,
                  'candidates_token_count': 11,
                  'thoughts_token_count': 5,
                  'cached_content_token_count': 10,
                },
              ),
              // Final chunk omits usageMetadata/modelVersion to verify tail normalization.
              LlmResponse(
                partial: false,
                turnComplete: true,
                content: Content.modelText('structured retries.'),
              ),
            ],
          );

          final LlmAgent rootAgent = LlmAgent(
            name: 'caller_agent',
            model: _StaticTextLlm('done'),
          );
          final RunConfig runConfig = RunConfig()
            ..telemetry = const TelemetryConfig(
              genaiSemconvStabilityOptIn: 'stable',
            );
          final InvocationContext invCtx = await _createInvocationContext(
            agent: rootAgent,
            runConfig: runConfig,
          );
          final ToolContext toolCtx = Context(
            invCtx,
            functionCallId: 'fc-adv-1',
          );

          final ModelConsultTool consultTool = ModelConsultTool(
            model: advisorLlm,
            metricsRecorder: recorder,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
              'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
            },
          );

          final Object? rawResult = await consultTool.run(
            args: <String, dynamic>{'question': 'How should retries behave?'},
            toolContext: toolCtx,
          );
          expect(rawResult, isA<Map<String, Object?>>());
          expect(
            (rawResult as Map<String, Object?>)['advice'],
            contains('retries'),
          );

          final durations = recorder.records
              .where((r) => r.name == 'gen_ai.client.operation.duration')
              .toList();
          expect(durations, hasLength(1));
          expect(
            durations.single.attributes['gen_ai.provider.name'] ??
                durations.single.attributes['gen_ai.system'],
            'gcp.gemini',
          );
          expect(
            durations.single.attributes['gen_ai.response.model'],
            'gemini-2.5-pro-002',
          );

          final clientTokens = recorder.records
              .where((r) => r.name == 'gen_ai.client.token.usage')
              .toList();
          expect(
            clientTokens,
            isNotEmpty,
            reason:
                'tokens=${clientTokens.map((r) => "${r.value}:${r.attributes}").toList()}',
          );
          expect(
            clientTokens.every(
              (r) =>
                  (r.attributes['gen_ai.provider.name'] ??
                      r.attributes['gen_ai.system']) ==
                  'gcp.gemini',
            ),
            isTrue,
          );
          final inputTokenSample = clientTokens.firstWhere(
            (r) => r.attributes['gen_ai.token.type'] == 'input',
          );
          final outputTokenSample = clientTokens.firstWhere(
            (r) => r.attributes['gen_ai.token.type'] == 'output',
          );
          expect(inputTokenSample.value, 42);
          expect(outputTokenSample.value, 16);

          final inferenceMetrics = recorder.records
              .where((r) => r.name.startsWith('gen_ai.client.inference.'))
              .toList();
          expect(inferenceMetrics, isNotEmpty);
          expect(
            inferenceMetrics.every(
              (r) => r.attributes['gen_ai.provider.name'] == 'gcp.gemini',
            ),
            isTrue,
          );
        },
      );

      test(
        'skips duplicate client duration/tokens when instrumentor records experimental semconv but still emits semconv inference tokens',
        () async {
          setGenAiInstrumentationDetectorForTest(() => true);
          setGenAiInstrumentorVersionForTest('0.7b2');
          final _RecordingMetricsRecorder recorder =
              _RecordingMetricsRecorder();
          final _StubAdvisorLlm advisorLlm = _StubAdvisorLlm(
            model: 'gemini-2.5-pro',
            chunks: <LlmResponse>[
              LlmResponse(
                modelVersion: 'gemini-2.5-pro-002',
                turnComplete: true,
                content: Content.modelText('Advice body'),
                usageMetadata: <String, Object?>{
                  'prompt_token_count': 20,
                  'candidates_token_count': 8,
                },
              ),
            ],
          );

          final LlmAgent rootAgent = LlmAgent(
            name: 'caller_agent',
            model: _StaticTextLlm('done'),
          );
          final RunConfig runConfig = RunConfig()
            ..telemetry = const TelemetryConfig(useExperimentalSemconv: true);
          final InvocationContext invCtx = await _createInvocationContext(
            agent: rootAgent,
            runConfig: runConfig,
          );
          final ToolContext toolCtx = Context(
            invCtx,
            functionCallId: 'fc-adv-2',
          );

          final ModelConsultTool consultTool = ModelConsultTool(
            model: advisorLlm,
            metricsRecorder: recorder,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
              'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
            },
          );
          await consultTool.run(
            args: <String, dynamic>{'question': 'Architecture check?'},
            toolContext: toolCtx,
          );

          expect(
            recorder.records.where(
              (r) =>
                  r.name == 'gen_ai.client.operation.duration' ||
                  r.name == 'gen_ai.client.token.usage',
            ),
            isEmpty,
          );
          expect(
            recorder.records.where(
              (r) => r.name.startsWith('gen_ai.client.inference.'),
            ),
            isNotEmpty,
          );
        },
      );

      test(
        'aligns client providerName with schema v1 ("gemini") vs schema v2 ("gcp.gemini") while semconv inference stays "gcp.gemini"',
        () async {
          setGenAiInstrumentationDetectorForTest(() => false);
          final _RecordingMetricsRecorder v1Recorder =
              _RecordingMetricsRecorder();
          final _RecordingMetricsRecorder v2Recorder =
              _RecordingMetricsRecorder();
          final _StubAdvisorLlm advisorLlm = _StubAdvisorLlm(
            model: 'gemini-2.5-flash',
            chunks: <LlmResponse>[
              LlmResponse(
                modelVersion: 'gemini-2.5-flash',
                turnComplete: true,
                content: Content.modelText('Quick answer'),
                usageMetadata: <String, Object?>{
                  'prompt_token_count': 15,
                  'candidates_token_count': 6,
                },
              ),
            ],
          );

          final InvocationContext invCtx = await _createInvocationContext(
            agent: LlmAgent(name: 'caller', model: _StaticTextLlm('ok')),
          );
          final ToolContext toolCtx = Context(
            invCtx,
            functionCallId: 'fc-adv-3',
          );

          await ModelConsultTool(
            model: advisorLlm,
            metricsRecorder: v1Recorder,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '1',
            },
          ).run(
            args: <String, dynamic>{'question': 'Schema v1 provider?'},
            toolContext: toolCtx,
          );

          await ModelConsultTool(
            model: advisorLlm,
            metricsRecorder: v2Recorder,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
            },
          ).run(
            args: <String, dynamic>{'question': 'Schema v2 provider?'},
            toolContext: toolCtx,
          );

          final v1Duration = v1Recorder.records.singleWhere(
            (r) => r.name == 'gen_ai.client.operation.duration',
          );
          expect(
            v1Duration.attributes['gen_ai.system'] ??
                v1Duration.attributes['gen_ai.provider.name'],
            'gemini',
          );
          final v1Inference = v1Recorder.records
              .where((r) => r.name.startsWith('gen_ai.client.inference.'))
              .first;
          expect(v1Inference.attributes['gen_ai.provider.name'], 'gcp.gemini');

          final v2Duration = v2Recorder.records.singleWhere(
            (r) => r.name == 'gen_ai.client.operation.duration',
          );
          expect(
            v2Duration.attributes['gen_ai.provider.name'] ??
                v2Duration.attributes['gen_ai.system'],
            'gcp.gemini',
          );
          final v1Token = v1Recorder.records
              .where((r) => r.name == 'gen_ai.client.token.usage')
              .first;
          expect(
            v1Token.attributes['gen_ai.provider.name'] ??
                v1Token.attributes['gen_ai.system'],
            'gemini',
          );
          final v2Token = v2Recorder.records
              .where((r) => r.name == 'gen_ai.client.token.usage')
              .first;
          expect(
            v2Token.attributes['gen_ai.provider.name'] ??
                v2Token.attributes['gen_ai.system'],
            'gcp.gemini',
          );
        },
      );
    },
  );

  group(
    '2. e5dd820da: FunctionDeclaration.behavior wire serialization, LiveRequest.partial, and live tool tracing',
    () {
      tearDown(() {
        tracer.clear();
      });

      test(
        'FunctionDeclaration.copyWith, sanitizedForModelCall, Gemini.connect, Gemini REST payload, and toGenerateContentBody preserve behavior on wire',
        () async {
          final FunctionDeclaration decl = FunctionDeclaration(
            name: 'bg_worker',
            description: 'Runs asynchronously in live mode',
            parameters: <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'query': <String, dynamic>{'type': 'string'},
              },
            },
            behavior: ToolBehavior.nonBlocking,
          );
          final FunctionDeclaration copied = decl.copyWith(
            description: 'Updated description',
          );
          expect(copied.behavior, ToolBehavior.nonBlocking);
          expect(decl.copyWith(behavior: null).behavior, isNull);

          final LlmRequest request = LlmRequest(
            model: 'gemini-2.5-flash',
            contents: <Content>[Content.userText('hello')],
            config: GenerateContentConfig(
              tools: <ToolDeclaration>[
                ToolDeclaration(
                  functionDeclarations: <FunctionDeclaration>[decl],
                ),
              ],
            ),
          );

          final LlmRequest sanitized = request.sanitizedForModelCall();
          expect(
            sanitized.config.tools!.single.functionDeclarations.single.behavior,
            ToolBehavior.nonBlocking,
          );

          // Verify toGenerateContentBody wire serialization.
          final Map<String, Object?> body = toGenerateContentBody(sanitized);
          final List<Object?> bodyTools = body['tools']! as List<Object?>;
          final Map<String, Object?> bodyTool =
              bodyTools.single as Map<String, Object?>;
          final List<Object?> bodyDecls =
              bodyTool['functionDeclarations']! as List<Object?>;
          expect(
            (bodyDecls.single as Map<String, Object?>)['behavior'],
            'NON_BLOCKING',
          );

          // Verify Gemini.generateContent REST wire payload serialization.
          final _CapturingRestTransport restTransport =
              _CapturingRestTransport();
          final _CapturingLiveSession liveSession = _CapturingLiveSession();
          final Gemini gemini = Gemini(
            model: 'gemini-2.5-flash',
            environment: const <String, String>{'GEMINI_API_KEY': 'test-key'},
            restTransport: restTransport,
            liveSessionFactory: (LlmRequest prepared) {
              liveSession.capturedInitialRequest = prepared;
              return liveSession;
            },
          );

          await gemini.generateContent(request).toList();
          expect(restTransport.capturedPayloads, hasLength(1));
          final List<Object?> wireTools =
              restTransport.capturedPayloads.single['tools']! as List<Object?>;
          final List<Object?> wireDecls =
              (wireTools.single
                      as Map<String, Object?>)['functionDeclarations']!
                  as List<Object?>;
          expect(
            (wireDecls.single as Map<String, Object?>)['behavior'],
            'NON_BLOCKING',
          );

          // Verify Gemini.connect() preserves behavior across sanitizedForModelCall + tool.copyWith()
          // and serializes behavior into the live setup request body.
          final BaseLlmConnection connection = gemini.connect(request);
          await connection.close();
          expect(liveSession.capturedInitialRequest, isNotNull);
          final FunctionDeclaration livePreparedDecl = liveSession
              .capturedInitialRequest!
              .liveConnectConfig
              .tools!
              .single
              .functionDeclarations
              .single;
          expect(livePreparedDecl.behavior, ToolBehavior.nonBlocking);
          final Map<String, Object?> liveSetupBody = toGenerateContentBody(
            liveSession.capturedInitialRequest!,
          );
          final List<Object?> liveSetupDecls =
              ((liveSetupBody['tools']! as List<Object?>).single
                      as Map<String, Object?>)['functionDeclarations']!
                  as List<Object?>;
          expect(
            (liveSetupDecls.single as Map<String, Object?>)['behavior'],
            'NON_BLOCKING',
          );
        },
      );

      test(
        'launchFunctionCallLive sets LiveRequest.partial=true on streamed chunks, partial=false on terminal responses/errors, and records execute_tool spans',
        () async {
          tracer.clear();
          final Completer<void> streamFailed = Completer<void>();
          final FunctionTool streamTool = FunctionTool(
            func: () async* {
              yield <String, Object?>{'tick': 1};
              yield <String, Object?>{'tick': 2};
              scheduleMicrotask(() {
                if (!streamFailed.isCompleted) {
                  streamFailed.complete();
                }
              });
              throw StateError('stream disconnected');
            },
            name: 'ticker_stream',
            description: 'Streams market ticks',
          );
          final _SingleValueLiveStreamingTool singleLiveStreamTool =
              _SingleValueLiveStreamingTool(
                name: 'single_stream_quote',
                singleValue: <String, Object?>{'price': 123.45},
              );
          final FunctionTool syncLiveTool = FunctionTool(
            func: () async => <String, Object?>{'status': 'done'},
            name: 'sync_lookup',
            description: 'Regular background live tool',
          );

          final LlmAgent agent = LlmAgent(
            name: 'live_agent',
            model: _StaticTextLlm('unused'),
            tools: <Object>[streamTool, singleLiveStreamTool, syncLiveTool],
          );
          final InvocationContext invCtx = await _createInvocationContext(
            agent: agent,
          );
          invCtx.liveRequestQueue = LiveRequestQueue();
          final LiveFunctionResponseQueue responseQueue =
              LiveFunctionResponseQueue();
          final Map<String, BaseTool> toolsDict = <String, BaseTool>{
            'ticker_stream': streamTool,
            'single_stream_quote': singleLiveStreamTool,
            'sync_lookup': syncLiveTool,
          };

          launchFunctionCallLive(
            invocationContext: invCtx,
            functionCall: FunctionCall(
              name: 'ticker_stream',
              id: 'call-stream-1',
              args: <String, dynamic>{},
            ),
            toolsDict: toolsDict,
            agent: agent,
            functionResponseQueue: responseQueue,
          );
          launchFunctionCallLive(
            invocationContext: invCtx,
            functionCall: FunctionCall(
              name: 'single_stream_quote',
              id: 'call-single-1',
              args: <String, dynamic>{},
            ),
            toolsDict: toolsDict,
            agent: agent,
            functionResponseQueue: responseQueue,
          );
          launchFunctionCallLive(
            invocationContext: invCtx,
            functionCall: FunctionCall(
              name: 'sync_lookup',
              id: 'call-sync-1',
              args: <String, dynamic>{},
            ),
            toolsDict: toolsDict,
            agent: agent,
            functionResponseQueue: responseQueue,
          );

          await waitForLiveToolCalls(
            invCtx,
            timeout: const Duration(seconds: 2),
          );
          await streamFailed.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await stopBackgroundToolTasks(invCtx);

          final List<LiveRequest> queuedRequests = await _drainLiveQueue(
            invCtx.liveRequestQueue!,
          );

          // Single-value live streaming tool sends terminal response with partial: false.
          final List<LiveRequest> singleToolRequests = queuedRequests.where((
            LiveRequest req,
          ) {
            final List<Part> parts = req.content?.parts ?? const <Part>[];
            return parts.any(
              (Part p) => p.functionResponse?.id == 'call-single-1',
            );
          }).toList();
          expect(singleToolRequests, hasLength(1));
          expect(singleToolRequests.single.partial, isFalse);
          expect(
            singleToolRequests
                .single
                .content
                ?.parts
                .single
                .functionResponse
                ?.response['price'],
            123.45,
          );

          // Streaming tool sends 2 yielded chunks with partial: true, followed by
          // post-pending error FunctionResponse with partial: false.
          final List<LiveRequest> streamToolRequests = queuedRequests.where((
            LiveRequest req,
          ) {
            final List<Part> parts = req.content?.parts ?? const <Part>[];
            return parts.any(
              (Part p) => p.functionResponse?.id == 'call-stream-1',
            );
          }).toList();
          expect(streamToolRequests, hasLength(3));
          expect(streamToolRequests[0].partial, isTrue);
          expect(streamToolRequests[1].partial, isTrue);
          expect(
            streamToolRequests[2]
                .content
                ?.parts
                .first
                .functionResponse
                ?.response['error'],
            contains('failed with an internal error'),
          );
          expect(streamToolRequests[2].partial, isFalse);

          // Verify OTel execute_tool spans were recorded for all live tool calls.
          final List<TraceSpanRecord> toolSpans = tracer.finishedSpans
              .where((TraceSpanRecord s) => s.name.startsWith('execute_tool'))
              .toList();
          expect(
            toolSpans.map(
              (TraceSpanRecord s) => s.attributes['gen_ai.tool.name'],
            ),
            containsAll(<String>[
              'ticker_stream',
              'single_stream_quote',
              'sync_lookup',
            ]),
          );
        },
      );
    },
  );

  group(
    '3. f67cc356c: Failed RemoteA2aAgent task is not promoted in live Workflow execution',
    () {
      test(
        'failed remote A2A task (A2A 0.3 & 1.x) is NOT promoted to JoinNode, while completed MAX_TOKENS and normal LlmAgent ARE promoted',
        () async {
          for (final String failedState in <String>[
            'failed',
            'TASK_STATE_FAILED',
          ]) {
            final (
              _FakeServer server,
              AgentCard card,
            ) = await _startLocalA2aServer(<String, Object?>{
              'kind': 'task',
              'id': 'currency-task',
              'contextId': 'currency-ctx',
              'status': <String, Object?>{
                'state': failedState,
                'message': <String, Object?>{
                  'kind': 'message',
                  'messageId': 'failure-msg',
                  'role': 'agent',
                  'parts': <Object?>[
                    <String, Object?>{
                      'kind': 'text',
                      'text': 'claude exited with code 1',
                    },
                  ],
                },
              },
            });
            addTearDown(() => server.close(force: true));
            final RemoteA2aAgent failedRemote = RemoteA2aAgent(
              name: 'currency',
              agentCard: card,
              a2aClientFactory: _factoryFor(card),
            );

            final AgentNode remoteNode = AgentNode(agent: failedRemote);
            final JoinNode joinNode = JoinNode(name: 'join');
            final Workflow workflow = Workflow(
              name: 'wf',
              nodes: <BaseNode>[remoteNode, joinNode],
              edges: <Edge>[
                Edge(fromNode: START, toNode: remoteNode),
                Edge(fromNode: remoteNode, toNode: joinNode),
              ],
            );
            final InMemoryRunner runner = InMemoryRunner(
              app: App(name: 'wf_app', rootAgent: workflow),
            );
            final Session session = await runner.sessionService.createSession(
              appName: 'wf_app',
              userId: 'u1',
            );
            final List<Event> events = await runner
                .runAsync(
                  userId: 'u1',
                  sessionId: session.id,
                  newMessage: Content.userText('start'),
                )
                .toList();

            final List<Event> failures = events
                .where((Event e) => e.errorCode == a2aTaskFailedErrorCode)
                .toList();
            final InvocationContext directCtx =
                await _createInvocationContext(agent: failedRemote)
                  ..userContent = Content.userText('start');
            final List<Event> directEvents = await failedRemote
                .runAsync(directCtx)
                .toList();
            expect(
              failures,
              hasLength(1),
              reason:
                  'state=$failedState direct=${directEvents.map((e) => "${e.author}:${e.errorCode}:${e.errorMessage}:${e.output}:${e.nodeInfo.messageAsOutput}").toList()} events=${events.map((e) => "${e.author}:${e.errorCode}:${e.errorMessage}:${e.output}").toList()}',
            );
            expect(failures.single.hasOutput, isFalse);
            expect(failures.single.output, isNull);
            expect(failures.single.nodeInfo.messageAsOutput, isNot(isTrue));

            final List<Event> joinEvents = events
                .where(
                  (Event e) =>
                      e.nodeInfo.path.contains('join') &&
                      (e.hasOutput || e.nodeInfo.messageAsOutput == true),
                )
                .toList();
            expect(joinEvents, hasLength(1), reason: 'state=$failedState');
            final Object? joinEventOutput = joinEvents.single.hasOutput
                ? joinEvents.single.output
                : jsonDecode(joinEvents.single.content!.parts.single.text!);
            expect(joinEventOutput, <String, Object?>{
              'currency': null,
            }, reason: 'Failed A2A task text must not feed JoinNode');

            final WorkflowResult rehydrated = workflow
                .rehydrateResultFromEvents(events);
            expect(
              rehydrated.nodeStates['currency']?.status,
              NodeStatus.failed,
            );
            expect(rehydrated.outputs.containsKey('currency'), isFalse);
            expect(_decoded(rehydrated.outputs['join']), <String, Object?>{
              'currency': null,
            });
          }

          // Completed task with errorCode == 'MAX_TOKENS' MUST still promote output.
          final (
            _FakeServer maxTokensServer,
            AgentCard maxTokensCard,
          ) = await _startLocalA2aServer(<String, Object?>{
            'kind': 'task',
            'id': 'currency-task-ok',
            'contextId': 'currency-ctx-ok',
            'metadata': <String, Object?>{'adk_error_code': 'MAX_TOKENS'},
            'status': <String, Object?>{
              'state': 'TASK_STATE_COMPLETED',
              'message': <String, Object?>{
                'kind': 'message',
                'messageId': 'ok-msg',
                'role': 'agent',
                'parts': <Object?>[
                  <String, Object?>{'kind': 'text', 'text': 'truncated answer'},
                ],
              },
            },
          });
          addTearDown(() => maxTokensServer.close(force: true));
          final RemoteA2aAgent maxTokensRemote = RemoteA2aAgent(
            name: 'currency',
            agentCard: maxTokensCard,
            a2aClientFactory: _factoryFor(maxTokensCard),
          );

          final AgentNode maxTokensNode = AgentNode(agent: maxTokensRemote);
          final JoinNode maxTokensJoinNode = JoinNode(name: 'join');
          final Workflow maxTokensWorkflow = Workflow(
            name: 'wf_max_tokens',
            nodes: <BaseNode>[maxTokensNode, maxTokensJoinNode],
            edges: <Edge>[
              Edge(fromNode: START, toNode: maxTokensNode),
              Edge(fromNode: maxTokensNode, toNode: maxTokensJoinNode),
            ],
          );
          final InMemoryRunner maxTokensRunner = InMemoryRunner(
            app: App(name: 'wf_max_app', rootAgent: maxTokensWorkflow),
          );
          final Session maxTokensSession = await maxTokensRunner.sessionService
              .createSession(appName: 'wf_max_app', userId: 'u1');
          final List<Event> maxTokensEvents = await maxTokensRunner
              .runAsync(
                userId: 'u1',
                sessionId: maxTokensSession.id,
                newMessage: Content.userText('start'),
              )
              .toList();
          final Event maxTokensJoin = maxTokensEvents.singleWhere(
            (Event e) =>
                e.nodeInfo.path.contains('join') &&
                (e.hasOutput || e.nodeInfo.messageAsOutput == true),
          );
          final Object? maxTokensJoinOutput = maxTokensJoin.hasOutput
              ? maxTokensJoin.output
              : jsonDecode(maxTokensJoin.content!.parts.single.text!);
          expect(maxTokensJoinOutput, <String, Object?>{
            'currency': 'truncated answer',
          });
          expect(
            _decoded(
              maxTokensWorkflow
                  .rehydrateResultFromEvents(maxTokensEvents)
                  .outputs['join'],
            ),
            <String, Object?>{'currency': 'truncated answer'},
          );

          // Normal LlmAgent (errorCode == null) MUST still promote output.
          final LlmAgent normalAgent = LlmAgent(
            name: 'assistant',
            mode: 'single_turn',
            model: _StaticTextLlm('normal reply'),
          );
          final AgentNode normalNode = AgentNode(agent: normalAgent);
          final JoinNode normalJoinNode = JoinNode(name: 'join');
          final Workflow normalWorkflow = Workflow(
            name: 'wf_normal',
            nodes: <BaseNode>[normalNode, normalJoinNode],
            edges: <Edge>[
              Edge(fromNode: START, toNode: normalNode),
              Edge(fromNode: normalNode, toNode: normalJoinNode),
            ],
          );
          final InMemoryRunner normalRunner = InMemoryRunner(
            app: App(name: 'wf_norm_app', rootAgent: normalWorkflow),
          );
          final Session normalSession = await normalRunner.sessionService
              .createSession(appName: 'wf_norm_app', userId: 'u1');
          final List<Event> normalEvents = await normalRunner
              .runAsync(
                userId: 'u1',
                sessionId: normalSession.id,
                newMessage: Content.userText('start'),
              )
              .toList();
          final Event normalJoin = normalEvents.singleWhere(
            (Event e) =>
                e.nodeInfo.path.contains('join') &&
                (e.hasOutput || e.nodeInfo.messageAsOutput == true),
          );
          final Object? normalJoinOutput = normalJoin.hasOutput
              ? normalJoin.output
              : jsonDecode(normalJoin.content!.parts.single.text!);
          expect(normalJoinOutput, <String, Object?>{
            'assistant': 'normal reply',
          });
          expect(
            _decoded(
              normalWorkflow
                  .rehydrateResultFromEvents(normalEvents)
                  .outputs['join'],
            ),
            <String, Object?>{'assistant': 'normal reply'},
          );
        },
      );
    },
  );

  group(
    '4. b6952874a: Complete credential parameter allowlist & telemetry serializer masking',
    () {
      tearDown(() {
        tracer.clear();
      });

      test(
        'isCredentialArgName matches all 6 added exact names and 4 added suffixes across snake_case, camelCase, PascalCase, and headers',
        () {
          const List<String> shouldMatch = <String>[
            'additional_headers',
            'additionalHeaders',
            'auth_config',
            'authConfig',
            'auth_credential',
            'authCredential',
            'auth_response_uri',
            'authResponseUri',
            'code_verifier',
            'codeVerifier',
            'private_key_id',
            'privateKeyId',
            'PrivateKeyId',
            'X-Private-Key',
            'tool_auth_config',
            'toolAuthConfig',
            'OAuth2AuthConfig',
            'upstream_authorization',
            'upstreamAuthorization',
            'proxy_cookie',
            'proxyCookie',
            'session_cookies',
            'sessionCookies',
          ];
          for (final String name in shouldMatch) {
            expect(isCredentialArgName(name), isTrue, reason: 'Expected $name');
          }

          expect(isCredentialArgName('page_size'), isFalse);
          expect(isCredentialArgName('project_id'), isFalse);
          expect(isCredentialArgName('redirect_uri'), isFalse);
        },
      );

      test(
        'safeJsonSerialize and maskCredentialValues mask standalone instances and .toJson()/.toMap() maps without auth_type while preserving ordinary content',
        () {
          final HttpCredentials httpCreds = HttpCredentials(
            username: 'alice',
            password: 'secret-http-password',
            token: 'secret-http-token',
          );
          final HttpAuth httpAuth = HttpAuth(
            scheme: 'bearer',
            credentials: httpCreds,
            additionalHeaders: <String, String>{
              'Authorization': 'Bearer secret-extra-header',
            },
          );
          final OAuth2Auth oauth2 = OAuth2Auth(
            clientId: 'public-client-id',
            clientSecret: 'secret-oauth-client-secret',
            authResponseUri: 'https://example.com/cb?code=secret-cb-code',
            authCode: 'secret-oauth-code',
            accessToken: 'ya29.secret-access-token',
            refreshToken: '1//secret-refresh-token',
            idToken: 'eyJ.secret-id-token',
            codeVerifier: 'secret-pkce-verifier',
          );
          final ServiceAccountCredential saCred = ServiceAccountCredential(
            projectId: 'my-gcp-project',
            privateKeyId: 'secret-sa-key-id',
            privateKey: '-----BEGIN PRIVATE KEY-----secret-pem',
            clientEmail: 'bot@my-gcp-project.iam.gserviceaccount.com',
            clientId: '123456789',
            authUri: 'https://accounts.google.com/o/oauth2/auth',
            tokenUri: 'https://oauth2.googleapis.com/token',
          );
          final OpenIdConnectWithConfig oidc = OpenIdConnectWithConfig(
            authorizationEndpoint: 'https://idp.example.com/authorize',
            tokenEndpoint: 'https://idp.example.com/token',
            scopes: <String>['openid', 'email'],
          );
          final AuthCredential authCred = AuthCredential(
            authType: AuthCredentialTypes.oauth2,
            oauth2: oauth2,
            http: httpAuth,
          );
          final AuthConfig authConfig = AuthConfig(
            authScheme: 'openIdConnect',
            rawAuthCredential: authCred,
            exchangedAuthCredential: authCred,
          );

          // 1. Standalone live instances are recognized by isCredentialType and masked to '<redacted>'.
          for (final Object instance in <Object>[
            httpCreds,
            httpAuth,
            oauth2,
            saCred,
            oidc,
            authCred,
            authConfig,
          ]) {
            expect(
              isCredentialType(instance),
              isTrue,
              reason: '${instance.runtimeType}',
            );
            expect(
              jsonDecode(safeJsonSerialize(instance)),
              redacted,
              reason: '${instance.runtimeType}',
            );
          }

          // 2. Standalone .toJson() / .toMap() maps WITHOUT an outer auth_type tag still mask all secret fields!
          final Map<String, Object?> standaloneHttpCredsJson =
              <String, Object?>{
                'username': 'alice',
                'password': 'secret-http-password',
                'token': 'secret-http-token',
              };
          final Map<String, Object?> standaloneHttpAuthJson = <String, Object?>{
            'scheme': 'bearer',
            'credentials': standaloneHttpCredsJson,
            'additionalHeaders': <String, Object?>{
              'Authorization': 'Bearer secret-extra-header',
            },
          };
          final Map<String, Object?> standaloneOAuth2Json = <String, Object?>{
            'clientId': 'public-client-id',
            'clientSecret': 'secret-oauth-client-secret',
            'authResponseUri': 'https://example.com/cb?code=secret-cb-code',
            'authCode': 'secret-oauth-code',
            'accessToken': 'ya29.secret-access-token',
            'refreshToken': '1//secret-refresh-token',
            'idToken': 'eyJ.secret-id-token',
            'codeVerifier': 'secret-pkce-verifier',
          };
          final Map<String, Object?> standaloneServiceAccountJson =
              <String, Object?>{
                'project_id': 'my-gcp-project',
                'private_key_id': 'secret-sa-key-id',
                'private_key': '-----BEGIN PRIVATE KEY-----secret-pem',
                'client_email': 'bot@my-gcp-project.iam.gserviceaccount.com',
              };
          final Map<String, Object?> standaloneAuthConfigJson =
              <String, Object?>{
                'authScheme': 'openIdConnect',
                'rawAuthCredential': <String, Object?>{
                  'oauth2': standaloneOAuth2Json,
                },
                'exchangedAuthCredential': <String, Object?>{
                  'http': standaloneHttpAuthJson,
                },
              };

          final List<String> allSecrets = <String>[
            'secret-http-password',
            'secret-http-token',
            'secret-extra-header',
            'secret-oauth-client-secret',
            'secret-cb-code',
            'secret-oauth-code',
            'ya29.secret-access-token',
            '1//secret-refresh-token',
            'eyJ.secret-id-token',
            'secret-pkce-verifier',
            'secret-sa-key-id',
            '-----BEGIN PRIVATE KEY-----secret-pem',
          ];

          final _CustomJsonCredentialHolder holder =
              _CustomJsonCredentialHolder(
                liveHttp: httpCreds,
                serializedHttpNoAuthType: standaloneHttpCredsJson,
                serializedOAuth2NoAuthType: standaloneOAuth2Json,
                serializedServiceAccountNoAuthType:
                    standaloneServiceAccountJson,
              );
          final _CustomToMapCredentialHolder toMapHolder =
              _CustomToMapCredentialHolder(standaloneAuthConfigJson);

          final String serializedHolder = safeJsonSerialize(<String, Object?>{
            'holder': holder,
            'to_map_holder': toMapHolder,
            'standalone_http_auth': standaloneHttpAuthJson,
            'standalone_auth_config': standaloneAuthConfigJson,
            'live_list': <Object?>[
              oidc,
              saCred,
              httpCreds,
              authCred,
              authConfig,
            ],
          });
          for (final String secret in allSecrets) {
            expect(
              serializedHolder,
              isNot(contains(secret)),
              reason:
                  'Secret "$secret" must be redacted from serialized output',
            );
          }
          final Map<String, Object?> decodedHolder =
              jsonDecode(serializedHolder) as Map<String, Object?>;
          expect(decodedHolder['live_list'], <String>[
            redacted,
            redacted,
            redacted,
            redacted,
            redacted,
          ]);
          final Map<String, Object?> innerHolder =
              decodedHolder['holder']! as Map<String, Object?>;
          expect(innerHolder['public_label'], 'safe-metadata');
          expect(innerHolder['live_http'], redacted);
          expect(
            (innerHolder['http_json']! as Map<String, Object?>)['password'],
            redacted,
          );
          expect(
            (innerHolder['http_json']! as Map<String, Object?>)['token'],
            redacted,
          );
          expect(
            (innerHolder['oauth2_json']!
                as Map<String, Object?>)['accessToken'],
            redacted,
          );
          expect(
            (innerHolder['oauth2_json']!
                as Map<String, Object?>)['codeVerifier'],
            redacted,
          );
          expect(
            (innerHolder['sa_json']! as Map<String, Object?>)['private_key_id'],
            redacted,
          );

          // 3. Ordinary non-credential content (schemas and benign pagination tokens) stays unchanged.
          final Map<String, Object?> benignPayload = <String, Object?>{
            'model': 'gemini-2.5-flash',
            'tools': <Object?>[
              <String, Object?>{
                'function_declarations': <Object?>[
                  <String, Object?>{
                    'name': 'search',
                    'parameters': <String, Object?>{
                      'type': 'OBJECT',
                      'properties': <String, Object?>{
                        'page_token': <String, Object?>{'type': 'STRING'},
                        'api_key': <String, Object?>{'type': 'STRING'},
                        'password': <String, Object?>{'type': 'STRING'},
                      },
                    },
                  },
                ],
              },
            ],
            'response': <String, Object?>{
              'token': 'next-page-cursor-token',
              'apiKey': 'public-app-identifier',
            },
          };
          expect(jsonDecode(safeJsonSerialize(benignPayload)), benignPayload);

          // 4. traceToolCall (including semconv gen_ai.tool.call.result) and traceMergedToolCalls redact live credentials.
          final FunctionTool dummyTool = FunctionTool(
            func: () => 'ok',
            name: 'fetch_creds',
            description: 'Fetches credentials',
          );
          final Event responseEvent = Event(
            id: 'ev-cred-1',
            invocationId: 'inv-cred-1',
            author: 'agent',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  id: 'fc-cred-1',
                  name: 'fetch_creds',
                  response: <String, dynamic>{
                    'cred': saCred,
                    'oauth_json': standaloneOAuth2Json,
                  },
                ),
              ],
            ),
          );

          final TraceSpanRecord singleSpan = tracer.startAsCurrentSpan(
            'execute_tool',
          );
          traceToolCall(
            dummyTool,
            <String, Object?>{'arg_cred': httpCreds},
            responseEvent,
            span: singleSpan,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION': '2',
              'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
              'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT': 'SPAN_ONLY',
            },
          );
          tracer.endSpan(singleSpan);

          final String semconvResult =
              singleSpan.attributes['gen_ai.tool.call.result']! as String;
          expect(semconvResult, isNot(contains('secret-sa-key-id')));
          expect(semconvResult, isNot(contains('ya29.secret-access-token')));
          expect(
            (jsonDecode(semconvResult) as Map<String, Object?>)['cred'],
            redacted,
          );

          final TraceSpanRecord mergedSpan = tracer.startAsCurrentSpan(
            'execute_tool',
          );
          traceMergedToolCalls(
            'ev-cred-1',
            responseEvent,
            span: mergedSpan,
            environment: const <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION': '2',
              'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
              'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT': 'SPAN_ONLY',
            },
          );
          tracer.endSpan(mergedSpan);
          expect(
            mergedSpan.attributes.containsKey('gen_ai.tool.call.result'),
            isFalse,
          );
          final String mergedLegacyResp =
              mergedSpan.attributes['gcp.vertex.agent.tool_response']!
                  as String;
          expect(mergedLegacyResp, isNot(contains('secret-sa-key-id')));
          expect(mergedLegacyResp, isNot(contains('ya29.secret-access-token')));
        },
      );
    },
  );

  group(
    '5. 5ce1d0c15: Inline AgentTool session isolation & BigQueryAgentAnalyticsPlugin [FORMATTER_FAILED] sentinel',
    () {
      test(
        'nested inline SingleTurnAgentTool generates fresh invocationId, links parentInvocationId per level, and cleans up _adk_parent_session_id',
        () async {
          for (final bool includePlugins in <bool>[true, false]) {
            final Map<String, String> recordedInvIds = <String, String>{};
            final Map<String, String?> recordedParentInvIds =
                <String, String?>{};
            final Map<String, Object?> recordedParentSessionMeta =
                <String, Object?>{};

            Content? recordCtx(CallbackContext cbCtx) {
              recordedInvIds[cbCtx.agentName] = cbCtx.invocationId;
              recordedParentInvIds[cbCtx.agentName] =
                  cbCtx.invocationContext.parentInvocationId;
              recordedParentSessionMeta[cbCtx.agentName] = cbCtx
                  .invocationContext
                  .privateMetadata['_adk_parent_session_id'];
              return null;
            }

            final LlmAgent level2Agent = LlmAgent(
              name: 'inline_level_2',
              mode: 'single_turn',
              model: _StaticTextLlm('level2_done'),
              beforeAgentCallback: recordCtx,
            );

            final LlmAgent level1Agent = LlmAgent(
              name: 'inline_level_1',
              mode: 'single_turn',
              model: _ScriptedToolCallingLlm(
                <LlmResponse Function(LlmRequest, int)>[
                  (LlmRequest req, int idx) => LlmResponse(
                    content: Content(
                      role: 'model',
                      parts: <Part>[
                        Part.fromFunctionCall(
                          name: 'inline_level_2',
                          id: 'fc-l2',
                          args: <String, dynamic>{'request': 'go l2'},
                        ),
                      ],
                    ),
                  ),
                  (LlmRequest req, int idx) => LlmResponse(
                    content: Content.modelText('level1_done'),
                    turnComplete: true,
                  ),
                ],
              ),
              tools: <Object>[
                SingleTurnAgentTool(
                  agent: level2Agent,
                  includePlugins: includePlugins,
                ),
              ],
              beforeAgentCallback: recordCtx,
            );

            Map<String, Object?>? rootPrivateMetaAfterTool;
            final LlmAgent rootAgent = LlmAgent(
              name: 'root_agent',
              model: _ScriptedToolCallingLlm(
                <LlmResponse Function(LlmRequest, int)>[
                  (LlmRequest req, int idx) => LlmResponse(
                    content: Content(
                      role: 'model',
                      parts: <Part>[
                        Part.fromFunctionCall(
                          name: 'inline_level_1',
                          id: 'fc-l1',
                          args: <String, dynamic>{'request': 'go l1'},
                        ),
                      ],
                    ),
                  ),
                  (LlmRequest req, int idx) => LlmResponse(
                    content: Content.modelText('root_done'),
                    turnComplete: true,
                  ),
                ],
              ),
              tools: <Object>[
                SingleTurnAgentTool(
                  agent: level1Agent,
                  includePlugins: includePlugins,
                ),
              ],
              beforeAgentCallback: recordCtx,
              afterAgentCallback: (CallbackContext cbCtx) {
                rootPrivateMetaAfterTool = Map<String, Object?>.from(
                  cbCtx.invocationContext.privateMetadata,
                );
                return null;
              },
            );

            final _RecordingBigQuerySink bqSink = _RecordingBigQuerySink();
            final BigQueryAgentAnalyticsPlugin bqPlugin =
                BigQueryAgentAnalyticsPlugin(
                  projectId: 'p',
                  datasetId: 'd',
                  tableId: 't',
                  sink: bqSink,
                  useBigQueryInsertAllSink: false,
                );

            final Runner runner = Runner(
              appName: 'inline_app',
              agent: rootAgent,
              sessionService: InMemorySessionService(),
              plugins: <BasePlugin>[bqPlugin],
            );
            final Session session = await runner.sessionService.createSession(
              appName: 'inline_app',
              userId: 'u1',
            );
            await runner
                .runAsync(
                  userId: 'u1',
                  sessionId: session.id,
                  newMessage: Content.userText('run nested inline'),
                )
                .toList();
            await bqPlugin.flush();

            final String rootInvId = recordedInvIds['root_agent']!;
            final String l1InvId = recordedInvIds['inline_level_1']!;
            final String l2InvId = recordedInvIds['inline_level_2']!;

            // Fresh child invocationIds at every inline nesting level.
            expect(l1InvId, isNot(equals(rootInvId)));
            expect(l2InvId, isNot(equals(rootInvId)));
            expect(l2InvId, isNot(equals(l1InvId)));

            expect(recordedParentInvIds['root_agent'], isNull);
            if (includePlugins) {
              expect(recordedParentInvIds['inline_level_1'], rootInvId);
              expect(recordedParentInvIds['inline_level_2'], l1InvId);
              expect(recordedParentSessionMeta['inline_level_1'], session.id);
              expect(recordedParentSessionMeta['inline_level_2'], session.id);

              final List<Map<String, Object?>> l2AgentRows = bqSink.rows.where((
                Map<String, Object?> r,
              ) {
                return r['event_type'] == 'AGENT_STARTING' &&
                    r['agent'] == 'inline_level_2';
              }).toList();
              expect(l2AgentRows, hasLength(1));
              final Object? rawAttrs = l2AgentRows.single['attributes'];
              final Map<String, Object?> attrs = rawAttrs is String
                  ? jsonDecode(rawAttrs) as Map<String, Object?>
                  : rawAttrs! as Map<String, Object?>;
              final Map<String, Object?> adkMeta =
                  attrs['adk']! as Map<String, Object?>;
              expect(adkMeta['parent_invocation_id'], l1InvId);
              expect(adkMeta['parent_session_id'], session.id);
            } else {
              expect(recordedParentInvIds['inline_level_1'], isNull);
              expect(recordedParentInvIds['inline_level_2'], isNull);
              expect(recordedParentSessionMeta['inline_level_1'], isNull);
              expect(recordedParentSessionMeta['inline_level_2'], isNull);
            }

            // Parent privateMetadata and session.state must not be polluted after inline runs finish.
            expect(
              rootPrivateMetaAfterTool?.containsKey('_adk_parent_session_id'),
              isFalse,
            );
            final Session? updatedSession = await runner.sessionService
                .getSession(
                  appName: 'inline_app',
                  userId: 'u1',
                  sessionId: session.id,
                );
            expect(
              updatedSession!.state.containsKey('_adk_parent_session_id'),
              isFalse,
            );
            expect(
              updatedSession.state.containsKey('temp:_adk_parent_session_id'),
              isFalse,
            );
          }
        },
      );

      test(
        'BigQueryAgentAnalyticsPlugin emits "[FORMATTER_FAILED]" sentinel when config.contentFormatter throws',
        () async {
          for (final bool logDetails in <bool>[false, true]) {
            final _RecordingBigQuerySink sink = _RecordingBigQuerySink();
            final BigQueryAgentAnalyticsPlugin plugin =
                BigQueryAgentAnalyticsPlugin(
                  projectId: 'proj',
                  datasetId: 'ds',
                  tableId: 'tbl',
                  sink: sink,
                  useBigQueryInsertAllSink: false,
                  config: BigQueryLoggerConfig(
                    logContentFormatterErrorDetails: logDetails,
                    contentFormatter: (Object? content, String eventType) {
                      throw StateError(
                        'formatter exploded on secret_value_123',
                      );
                    },
                  ),
                );

            final LlmAgent agent = LlmAgent(
              name: 'fmt_agent',
              model: _StaticTextLlm('raw sensitive model reply'),
            );
            final Runner runner = Runner(
              appName: 'fmt_app',
              agent: agent,
              sessionService: InMemorySessionService(),
              plugins: <BasePlugin>[plugin],
            );
            final Session session = await runner.sessionService.createSession(
              appName: 'fmt_app',
              userId: 'u1',
            );
            await runner
                .runAsync(
                  userId: 'u1',
                  sessionId: session.id,
                  newMessage: Content.userText('raw sensitive user prompt'),
                )
                .toList();
            await plugin.flush();

            final List<Map<String, Object?>> contentRows = sink.rows
                .where(
                  (Map<String, Object?> r) =>
                      r['event_type'] == 'USER_MESSAGE_RECEIVED' ||
                      r['event_type'] == 'AGENT_RESPONSE',
                )
                .toList();
            expect(contentRows, isNotEmpty);
            for (final Map<String, Object?> row in contentRows) {
              final Object? rawContent = row['content'];
              final Object? decoded = rawContent is String
                  ? (() {
                      try {
                        return jsonDecode(rawContent);
                      } catch (_) {
                        return rawContent;
                      }
                    })()
                  : rawContent;
              expect(decoded, '[FORMATTER_FAILED]');
              expect('$rawContent', isNot(contains('raw sensitive')));
            }
          }
        },
      );
    },
  );
}
