import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeInferenceData {
  const _FakeInferenceData();
}

class _FakeSdkClient {
  const _FakeSdkClient(this.name);
  final String name;
}

class _ScriptedAdvisorLlm extends BaseLlm {
  _ScriptedAdvisorLlm({required super.model, required this.response});

  final LlmResponse response;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield response;
  }
}

InvocationContext _buildInvocationContext({
  String model = 'gemini-2.0-flash',
  TelemetryConfig? telemetryConfig,
}) {
  final LlmAgent agent = LlmAgent(name: 'test_agent', model: model);
  final RunConfig runConfig = RunConfig()..telemetry = telemetryConfig;
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_nov24',
    agent: agent,
    session: Session(id: 'sess_nov24', appName: 'app', userId: 'user_1'),
    runConfig: runConfig,
  );
}

void main() {
  setUp(() {
    tracer.clear();
    resetAdkMetricsRecorderForTest();
    resetGenAiInstrumentationDetectorForTest();
  });

  tearDown(() {
    tracer.clear();
    resetAdkMetricsRecorderForTest();
    resetGenAiInstrumentationDetectorForTest();
  });

  group('8c0d2f880: google-genai instrumentor bypass and util-genai gating', () {
    group('shouldEmitSemconvInferenceTokenMetrics (opentelemetry-util-genai)', () {
      const Map<String, bool> versionCases = <String, bool>{
        '0.3b0': true,
        '1.2b0': true,
        '1.3b0': true,
        '1.3b1': false,
        '1.3.0': false,
        '1.4b0': false,
      };

      for (final MapEntry<String, bool> entry in versionCases.entries) {
        test(
          'returns ${entry.value} for util-genai ${entry.key} under instrumentor',
          () {
            expect(
              shouldEmitSemconvInferenceTokenMetrics(
                'gemini-2.5-flash',
                hasGenAiInstrumentor: true,
                utilGenAiVersion: entry.key,
              ),
              entry.value,
            );
          },
        );
      }

      test('returns true when opentelemetry-util-genai is not installed', () {
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'gemini-2.5-flash',
            hasGenAiInstrumentor: true,
            environment: const <String, String>{},
          ),
          isTrue,
        );
      });

      test('returns true for non-Gemini models or when uninstrumented', () {
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'claude-3-5-sonnet',
            hasGenAiInstrumentor: true,
            utilGenAiVersion: '1.4b0',
          ),
          isTrue,
        );
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'gemini-2.5-flash',
            hasGenAiInstrumentor: false,
            utilGenAiVersion: '1.4b0',
          ),
          isTrue,
        );
      });

      test('reads simulated util-genai version from test hook and env', () {
        setUtilGenAiVersionForTest('1.4b0');
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'gemini-2.5-flash',
            hasGenAiInstrumentor: true,
          ),
          isFalse,
        );

        setUtilGenAiVersionForTest(null);
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'gemini-2.5-flash',
            hasGenAiInstrumentor: true,
            environment: const <String, String>{
              'OTEL_UTIL_GENAI_VERSION': '1.3b0',
            },
          ),
          isTrue,
        );
        expect(
          shouldEmitSemconvInferenceTokenMetrics(
            'gemini-2.5-flash',
            hasGenAiInstrumentor: true,
            environment: const <String, String>{
              'OTEL_UTIL_GENAI_VERSION': '1.4b0',
            },
          ),
          isFalse,
        );
      });
    });

    test(
      'skips an instrumentor 1.0b0 without co_filename stamp on SDK function',
      () async {
        final List<String> calls = <String>[];
        final GenAiRawFunction sdkFn = GenAiRawFunction(
          (instance, args, kwargs) => 'sdk_ok',
          codeFilename: '/site-packages/google/genai/models.py',
        );
        final GenAiWraptProxy instrumentor10b0 = GenAiWraptProxy(
          wrapped: sdkFn,
          wrapperCodeFilename:
              '/site-packages/$genAiInstrumentorModulePath/x.py',
          selfWrapper: (wrapped, instance, args, kwargs) {
            calls.add('instrumentor');
            return wrapped(args, kwargs);
          },
        );

        setGenAiGenerateContentWrapperForTest(instrumentor10b0);
        expect(isGenAiInstrumented(), isTrue);

        final InvocationContext ctx = _buildInvocationContext();
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        final Object? result = await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            final GenAiCallable callable = maybeWithoutGenAiInstrumentation(
              instrumentor10b0,
            );
            return await callable();
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '1',
          },
        );

        expect(result, 'sdk_ok');
        expect(calls, isEmpty);
      },
    );

    test(
      'skipping a pre-1.0 instrumentor keeps a wrapt wrapper beneath it',
      () async {
        final List<String> calls = <String>[];
        Object? observedForeignInstance;
        Object? observedSdkInstance;
        const _FakeSdkClient client = _FakeSdkClient('async_models');

        final GenAiRawFunction sdkFn = GenAiRawFunction((
          instance,
          args,
          kwargs,
        ) {
          observedSdkInstance = instance;
          return 'sdk_ok';
        }, codeFilename: '/site-packages/google/genai/models.py');

        final GenAiWraptProxy beneathForeign = GenAiWraptProxy(
          wrapped: sdkFn,
          wrapperCodeFilename: '/site-packages/third_party/wrapper.py',
          selfWrapper: (wrapped, instance, args, kwargs) {
            calls.add('foreign');
            observedForeignInstance = instance;
            return wrapped(args, kwargs);
          },
        );

        final GenAiPlainWrapper pre10Instrumentor = GenAiPlainWrapper(
          wrapped: beneathForeign,
          codeFilename: '/site-packages/$genAiInstrumentorModulePath/x.py',
          instance: client,
          invoke: (wrapped, instance, args, kwargs) {
            calls.add('instrumentor');
            return wrapped!.bindToInstance(instance)(args, kwargs);
          },
        );

        setGenAiGenerateContentWrapperForTest(pre10Instrumentor);
        expect(isGenAiInstrumented(), isTrue);

        final InvocationContext ctx = _buildInvocationContext();
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        final Object? result = await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            final GenAiCallable callable = maybeWithoutGenAiInstrumentation(
              pre10Instrumentor,
            );
            return await callable();
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '1',
          },
        );

        expect(result, 'sdk_ok');
        expect(calls, <String>['foreign']);
        expect(observedForeignInstance, same(client));
        expect(observedSdkInstance, same(client));
      },
    );

    test(
      'skipping a stamped >= 1.0b1 instrumentor keeps a wrapt wrapper above it',
      () async {
        final List<String> calls = <String>[];
        final List<String> spanScopes = <String>[];
        const _FakeSdkClient client = _FakeSdkClient('async_models');

        // >= 1.0b1 stamps co_filename on the wrapped SDK function itself.
        final GenAiRawFunction stampedSdkFn = GenAiRawFunction(
          (instance, args, kwargs) => 'sdk_ok',
          codeFilename:
              '/site-packages/$genAiInstrumentorModulePath/_stamped.py',
          instance: client,
        );

        final GenAiWraptProxy instrumentorProxy = GenAiWraptProxy(
          wrapped: stampedSdkFn,
          wrapperCodeFilename:
              '/site-packages/$genAiInstrumentorModulePath/wrapper.py',
          selfInstance: client,
          selfWrapper: (wrapped, instance, args, kwargs) {
            calls.add('instrumentor');
            spanScopes.add('opentelemetry.instrumentation.google_genai');
            return wrapped(args, kwargs);
          },
        );

        final GenAiWraptProxy foreignAbove = GenAiWraptProxy(
          wrapped: instrumentorProxy,
          wrapperCodeFilename: '/site-packages/third_party/foreign.py',
          selfInstance: client,
          selfWrapper: (wrapped, instance, args, kwargs) {
            calls.add('foreign');
            return wrapped(args, kwargs);
          },
        );

        // Even though foreignAbove inherits the stamped codeFilename, it is NOT
        // classified as the instrumentor layer.
        expect(isGenAiInstrumentorLayer(foreignAbove), isFalse);
        expect(isGenAiInstrumentorLayer(instrumentorProxy), isTrue);

        setGenAiGenerateContentWrapperForTest(foreignAbove);
        expect(isGenAiInstrumented(), isTrue);

        final InvocationContext ctx = _buildInvocationContext();
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        final Object? result = await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            spanScopes.add('gcp.vertex.agent');
            final GenAiCallable callable = maybeWithoutGenAiInstrumentation(
              foreignAbove,
            );
            return await callable();
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '1',
          },
        );

        expect(result, 'sdk_ok');
        expect(spanScopes, <String>['gcp.vertex.agent']);
        expect(calls, <String>['foreign']);
      },
    );

    test(
      'instrumentor stands down beneath any opaque wrapper via util-genai context',
      () async {
        final List<String> spanScopes = <String>[];

        final GenAiRawFunction sdkFn = GenAiRawFunction(
          (instance, args, kwargs) => 'sdk_ok',
        );

        // Simulates opentelemetry-util-genai >= 1.3b0 checking the context key.
        final GenAiWraptProxy instrumentorProxy = GenAiWraptProxy(
          wrapped: sdkFn,
          wrapperCodeFilename:
              '/site-packages/$genAiInstrumentorModulePath/wrapper.py',
          selfWrapper: (wrapped, instance, args, kwargs) {
            if (!isInsideAdkInferenceSpan()) {
              spanScopes.add('opentelemetry.instrumentation.google_genai');
            }
            return wrapped(args, kwargs);
          },
        );

        // A plain opaque foreign wrapper hides the instrumentor from unwrapping.
        final GenAiPlainWrapper opaqueForeign = GenAiPlainWrapper(
          codeFilename: '/site-packages/third_party/opaque.py',
          invoke: (wrapped, instance, args, kwargs) =>
              instrumentorProxy(args, kwargs),
        );

        final InvocationContext ctx = _buildInvocationContext();
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        final Object? result = await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            spanScopes.add('gcp.vertex.agent');
            final GenAiCallable callable = maybeWithoutGenAiInstrumentation(
              opaqueForeign,
            );
            // Opaque wrapper cannot be unwrapped, but util-genai still stands down.
            expect(callable, same(opaqueForeign));
            return await callable();
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '1',
          },
        );

        expect(result, 'sdk_ok');
        expect(spanScopes, <String>['gcp.vertex.agent']);
      },
    );

    for (final String schemaVersion in const <String>['1', '2']) {
      test(
        'inference span marks and clears util-genai context (schema v$schemaVersion)',
        () async {
          const String contextKey = 'test-client-inference-context-key';
          setUtilGenAiClientInferenceContextHookForTest(
            contextKey: contextKey,
            createInferenceData: () => const _FakeInferenceData(),
          );

          final List<Object?> observed = <Object?>[];
          final InvocationContext ctx = _buildInvocationContext();
          final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
          final Event event = Event(
            invocationId: ctx.invocationId,
            author: 'a',
          );

          await useInferenceSpan(
            req,
            ctx,
            event,
            (GenerateContentSpan? gcSpan) async {
              expect(gcSpan, isNotNull);
              observed.add(getCurrentClientInferenceContextValue(contextKey));
            },
            environment: <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': schemaVersion,
            },
          );

          expect(observed, hasLength(1));
          expect(observed.single, isA<_FakeInferenceData>());
          expect(getCurrentClientInferenceContextValue(contextKey), isNull);
        },
      );
    }

    test(
      'delegated inference span leaves util-genai context unset and preserves instrumentor',
      () async {
        final List<String> calls = <String>[];
        final GenAiRawFunction sdkFn = GenAiRawFunction(
          (instance, args, kwargs) => 'sdk_ok',
        );
        final GenAiWraptProxy instrumentorProxy = GenAiWraptProxy(
          wrapped: sdkFn,
          wrapperCodeFilename:
              '/site-packages/$genAiInstrumentorModulePath/wrapper.py',
          selfWrapper: (wrapped, instance, args, kwargs) {
            calls.add('instrumentor');
            return wrapped(args, kwargs);
          },
        );

        setGenAiGenerateContentWrapperForTest(instrumentorProxy);
        setGenAiInstrumentorVersionForTest('1.0b0');

        final InvocationContext ctx = _buildInvocationContext();
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            // Instrumentor owns this inference under schema v2.
            expect(gcSpan, isNull);
            expect(isInsideAdkInferenceSpan(), isFalse);
            final GenAiCallable callable = maybeWithoutGenAiInstrumentation(
              instrumentorProxy,
            );
            expect(callable, same(instrumentorProxy));
            await callable();
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
            'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
          },
        );

        expect(calls, <String>['instrumentor']);
      },
    );

    test(
      'ADK records semconv inference tokens when it skips the instrumentor even with util-genai 1.4b0',
      () async {
        final InMemoryAdkMetricsRecorder recorder =
            InMemoryAdkMetricsRecorder();
        setAdkMetricsRecorder(recorder);
        setGenAiInstrumentationDetectorForTest(
          () => true,
          version: '1.0b0',
          utilGenAiVersion: '1.4b0',
        );

        final InvocationContext ctx = _buildInvocationContext(
          telemetryConfig: const TelemetryConfig(
            genaiSemconvStabilityOptIn: 'stable',
          ),
        );
        final LlmRequest req = LlmRequest(model: 'gemini-2.0-flash');
        final Event event = Event(invocationId: ctx.invocationId, author: 'a');

        await useInferenceSpan(
          req,
          ctx,
          event,
          (GenerateContentSpan? gcSpan) async {
            expect(gcSpan, isNotNull);
            gcSpan!.responses.add(
              LlmResponse(
                modelVersion: 'gemini-2.0-flash',
                content: Content.modelText('ok'),
                finishReason: 'STOP',
                usageMetadata: const <String, Object?>{
                  'prompt_token_count': 10,
                  'candidates_token_count': 5,
                },
              ),
            );
          },
          environment: const <String, String>{
            'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
            'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
          },
        );

        final List<AdkMetricRecord> inputOpMetrics = recorder.records
            .where(
              (AdkMetricRecord r) =>
                  r.name == genAiClientInferenceOperationInputTokensMetric,
            )
            .toList();
        expect(inputOpMetrics, hasLength(1));
        expect(inputOpMetrics.single.value, 10);
      },
    );

    test(
      'ModelConsultTool gates inference token metrics by util-genai version (1.3b0 vs 1.4b0)',
      () async {
        final Map<String, String> experimentalEnv = const <String, String>{
          'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
        };
        final LlmResponse advisorResponse = LlmResponse(
          modelVersion: 'gemini-2.5-pro-001',
          content: Content.modelText('Advice'),
          finishReason: 'STOP',
          usageMetadata: const <String, Object?>{
            'prompt_token_count': 24,
            'candidates_token_count': 8,
          },
        );

        for (final (String utilVersion, bool expectTokens)
            in const <(String, bool)>[('1.3b0', true), ('1.4b0', false)]) {
          final InMemoryAdkMetricsRecorder recorder =
              InMemoryAdkMetricsRecorder();
          setAdkMetricsRecorder(recorder);
          setGenAiInstrumentationDetectorForTest(
            () => true,
            version: '1.0b0',
            utilGenAiVersion: utilVersion,
          );

          final ModelConsultTool tool = ModelConsultTool(
            model: _ScriptedAdvisorLlm(
              model: 'gemini-2.5-pro',
              response: advisorResponse,
            ),
            environment: experimentalEnv,
          );
          final InvocationContext invCtx = _buildInvocationContext(
            model: 'gemini-2.5-flash',
          );
          final ToolContext toolCtx = Context(invCtx, functionCallId: 'fc_1');

          await tool.run(
            args: <String, dynamic>{'question': 'Which option?'},
            toolContext: toolCtx,
          );

          final bool hasInferenceTokens = recorder.records.any(
            (AdkMetricRecord r) =>
                r.name == genAiClientInferenceOperationInputTokensMetric,
          );
          expect(
            hasInferenceTokens,
            expectTokens,
            reason: 'util-genai $utilVersion',
          );
        }
      },
    );
  });
}
