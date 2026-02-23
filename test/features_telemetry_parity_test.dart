import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/features/_feature_decorator.dart'
    as feature_decorator;
import 'package:test/test.dart';

void main() {
  group('features parity', () {
    setUp(() {
      resetFeatureRegistryForTest();
    });

    test('default/override/env precedence and warning-once behavior', () {
      final List<String> warnings = <String>[];
      setFeatureWarningEmitter(warnings.add);

      expect(isFeatureEnabled(FeatureName.agentConfig), isTrue);
      expect(isFeatureEnabled(FeatureName.agentConfig), isTrue);
      expect(warnings, hasLength(1));

      overrideFeatureEnabled(FeatureName.agentConfig, false);
      expect(
        isFeatureEnabled(
          FeatureName.agentConfig,
          environment: <String, String>{'ADK_ENABLE_AGENT_CONFIG': '1'},
        ),
        isFalse,
      );

      clearFeatureOverride(FeatureName.agentConfig);
      expect(
        isFeatureEnabled(
          FeatureName.agentConfig,
          environment: <String, String>{'ADK_DISABLE_AGENT_CONFIG': '1'},
        ),
        isFalse,
      );
    });

    test('temporary override restores original state', () {
      overrideFeatureEnabled(FeatureName.agentState, false);

      final bool inside = withTemporaryFeatureOverride(
        FeatureName.agentState,
        true,
        () => isFeatureEnabled(FeatureName.agentState),
      );
      expect(inside, isTrue);
      expect(isFeatureEnabled(FeatureName.agentState), isFalse);
    });

    test('decorator parity checks enabled state and stage mismatch', () {
      expect(
        () => feature_decorator.stable(FeatureName.agentConfig),
        throwsArgumentError,
      );

      final feature_decorator.FeatureDecorator guard = feature_decorator
          .workingInProgress(FeatureName.jsonSchemaForFuncDecl);

      expect(() => guard.run(() => 'x'), throwsA(isA<StateError>()));

      final String value = withTemporaryFeatureOverride(
        FeatureName.jsonSchemaForFuncDecl,
        true,
        () => guard.run(() => 'ok'),
      );
      expect(value, 'ok');
    });
  });

  group('platform thread parity', () {
    tearDown(() {
      setInternalThreadCreator(null);
    });

    test('createThread executes with positional and named arguments', () async {
      String result = '';
      final AdkThread thread = createThread(
        (String city, {required String zone}) {
          result = '$city-$zone';
        },
        args: <Object?>['Seoul'],
        namedArgs: <Symbol, Object?>{#zone: 'KST'},
      );

      thread.start();
      await thread.join();

      expect(result, 'Seoul-KST');
      expect(thread.isCompleted, isTrue);
    });

    test(
      'createThread delegates to internal implementation when present',
      () async {
        bool delegated = false;
        setInternalThreadCreator((
          Function target,
          List<Object?> args,
          Map<Symbol, Object?> namedArgs,
        ) {
          delegated = true;
          return AdkThread(target, args: args, namedArgs: namedArgs);
        });

        int value = 0;
        final AdkThread thread = createThread(
          (int next) => value = next,
          args: <Object?>[9],
        );
        await thread.join();

        expect(delegated, isTrue);
        expect(value, 9);
      },
    );
  });

  group('telemetry setup/google cloud/sqlite parity', () {
    setUp(() {
      resetOtelProvidersForTest();
      resetGoogleAuthResolverForTest();
      tracer.clear();
    });

    test('maybeSetOtelProviders collects processors and sets providers', () {
      maybeSetOtelProviders(
        otelHooksToSetup: <OTelHooks>[
          OTelHooks(
            spanProcessors: <SpanProcessor>[
              BatchSpanProcessor(OtlpSpanExporter()),
            ],
            metricReaders: <MetricReader>[
              PeriodicExportingMetricReader(const OtlpMetricExporter()),
            ],
            logRecordProcessors: <LogRecordProcessor>[
              BatchLogRecordProcessor(const OtlpLogExporter()),
            ],
          ),
        ],
        otelResource: OTelResource(
          attributes: <String, Object?>{'service.name': 'adk-test'},
        ),
      );

      expect(globalOtelProviders.tracerProvider, isNotNull);
      expect(globalOtelProviders.meterProvider, isNotNull);
      expect(globalOtelProviders.loggerProvider, isNotNull);
      expect(globalOtelProviders.eventLoggerProvider, isNotNull);
      expect(globalOtelProviders.tracerProvider!.spanProcessors, hasLength(1));
    });

    test('OTLP env vars create generic exporters', () {
      final OTelHooks hooks = getOtelExporters(
        environment: <String, String>{otelExporterOtlpEndpoint: 'http://otel'},
      );

      expect(hooks.spanProcessors, hasLength(1));
      expect(hooks.metricReaders, hasLength(1));
      expect(hooks.logRecordProcessors, hasLength(1));
    });

    test('gcp exporters honor enable flags and custom log name', () {
      final OTelHooks disabled = getGcpExporters(
        enableCloudTracing: true,
        googleAuth: const GoogleAuthResult(
          credentials: Object(),
          projectId: '',
        ),
      );
      expect(disabled.spanProcessors, isEmpty);

      final OTelHooks enabled = getGcpExporters(
        enableCloudTracing: true,
        enableCloudMetrics: true,
        enableCloudLogging: true,
        googleAuth: const GoogleAuthResult(
          credentials: Object(),
          projectId: 'proj-1',
        ),
        environment: <String, String>{gcpLogNameEnvVariableName: 'custom-log'},
      );
      expect(enabled.spanProcessors, hasLength(1));
      expect(enabled.metricReaders, hasLength(1));
      expect(enabled.logRecordProcessors, hasLength(1));

      final BatchLogRecordProcessor logProcessor =
          enabled.logRecordProcessors.single as BatchLogRecordProcessor;
      final CloudLoggingExporter exporter =
          logProcessor.exporter as CloudLoggingExporter;
      expect(exporter.defaultLogName, 'custom-log');
    });

    test('gcp resource merges project/env/detector attributes', () {
      final OTelResource resource = getGcpResource(
        projectId: 'proj-a',
        environment: <String, String>{
          otelServiceName: 'svc',
          otelResourceAttributes: 'k1=v1,k2=v2',
        },
        gcpResourceDetector: () => OTelResource(
          attributes: <String, Object?>{'cloud.zone': 'us-central1-a'},
        ),
      );

      expect(resource.attributes['gcp.project_id'], 'proj-a');
      expect(resource.attributes['service.name'], 'svc');
      expect(resource.attributes['k1'], 'v1');
      expect(resource.attributes['cloud.zone'], 'us-central1-a');
    });

    test('sqlite span exporter stores/reloads full trace by session', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'adk_sqlite_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final SqliteSpanExporter exporter = SqliteSpanExporter(
        dbPath: '${tempDir.path}/spans.db',
      );

      const SpanContext parentContext = SpanContext(
        traceId: 0x1,
        spanId: 0x10,
        isRemote: false,
        traceFlags: TraceFlags.sampled,
        traceState: TraceState(),
      );
      const SpanContext childContext = SpanContext(
        traceId: 0x1,
        spanId: 0x11,
        isRemote: false,
        traceFlags: TraceFlags.sampled,
        traceState: TraceState(),
      );

      final SpanExportResult exportResult = exporter.export(<ReadableSpan>[
        ReadableSpan(
          name: 'root',
          context: parentContext,
          attributes: <String, Object?>{
            'gcp.vertex.agent.session_id': 'sess-1',
          },
          startTimeUnixNano: 100,
          endTimeUnixNano: 200,
        ),
        ReadableSpan(
          name: 'child',
          context: childContext,
          parent: parentContext,
          attributes: <String, Object?>{},
          startTimeUnixNano: 110,
          endTimeUnixNano: 190,
        ),
      ]);
      expect(exportResult, SpanExportResult.success);

      final List<ReadableSpan> spans = exporter.getAllSpansForSession('sess-1');
      expect(spans.map((ReadableSpan span) => span.name).toList(), <String>[
        'root',
        'child',
      ]);
    });

    test('tracing helpers set tool/llm/send-data attributes', () {
      final _FakeSessionService sessionService = _FakeSessionService();
      final InvocationContext context = InvocationContext(
        sessionService: sessionService,
        invocationId: 'inv-1',
        agent: _FakeAgent(),
        session: Session(id: 's-1', appName: 'app', userId: 'user'),
      );
      final TraceSpanRecord span = tracer.startAsCurrentSpan('root');

      final Event functionResponseEvent = Event(
        invocationId: 'inv-1',
        author: 'tool',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionResponse(
              name: 'clock',
              id: 'call-1',
              response: <String, Object?>{'time': '10:30'},
            ),
          ],
        ),
      );

      traceToolCall(
        _FakeTool(),
        <String, Object?>{'city': 'Seoul'},
        functionResponseEvent,
        span: span,
      );
      expect(span.attributes['gen_ai.tool_call.id'], 'call-1');

      traceMergedToolCalls('resp-1', functionResponseEvent, span: span);
      expect(span.attributes['gcp.vertex.agent.event_id'], 'resp-1');

      final LlmRequest request = LlmRequest(
        model: 'gemini-2.5-flash',
        contents: <Content>[Content.userText('hello')],
      );
      final LlmResponse response = LlmResponse(
        finishReason: 'STOP',
        usageMetadata: <String, Object?>{
          'promptTokenCount': 3,
          'candidatesTokenCount': 7,
        },
      );

      traceCallLlm(context, 'evt-1', request, response, span: span);
      expect(span.attributes['gcp.vertex.agent.event_id'], 'evt-1');
      expect(span.attributes['gen_ai.response.finish_reasons'], <String>[
        'stop',
      ]);

      traceSendData(context, 'evt-2', <Content>[
        Content.userText('payload'),
      ], span: span);
      final String data = span.attributes['gcp.vertex.agent.data']! as String;
      expect(data, contains('payload'));

      traceSendData(
        context,
        'evt-3',
        <Content>[Content.userText('hidden')],
        span: span,
        environment: <String, String>{adkCaptureMessageContentInSpans: '0'},
      );
      expect(span.attributes['gcp.vertex.agent.data'], '{}');
    });
  });
}

class _FakeAgent extends BaseAgent {
  _FakeAgent() : super(name: 'fake_agent', description: 'fake');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

class _FakeTool extends BaseTool {
  _FakeTool() : super(name: 'clock_tool', description: 'clock tool');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'ok': true};
  }
}

class _FakeSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 's',
      appName: appName,
      userId: userId,
      state: state,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }
}
