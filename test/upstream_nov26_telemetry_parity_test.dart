import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/telemetry/_experimental_semconv.dart'
    as experimental_semconv;
import 'package:test/test.dart';

InvocationContext _buildInvocationContext({
  String model = 'gemini-2.5-flash',
  TelemetryConfig? telemetryConfig,
}) {
  final LlmAgent agent = LlmAgent(name: 'test_agent', model: model);
  final RunConfig runConfig = RunConfig()..telemetry = telemetryConfig;
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_nov26',
    agent: agent,
    session: Session(id: 'sess_nov26', appName: 'app', userId: 'user_1'),
    runConfig: runConfig,
  );
}

LlmRequest _requestWithContentAndTool() {
  return LlmRequest(
    model: 'gemini-2.5-flash',
    contents: <Content>[Content.userText('hi')],
    config: GenerateContentConfig(
      systemInstruction: 'be helpful',
      tools: <ToolDeclaration>[
        ToolDeclaration(
          functionDeclarations: <FunctionDeclaration>[
            FunctionDeclaration(
              name: 'add',
              description: 'Adds two numbers.',
              parameters: <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'a': <String, dynamic>{'type': 'integer'},
                  'b': <String, dynamic>{'type': 'integer'},
                },
              },
            ),
          ],
        ),
      ],
    ),
  );
}

List<Part> _thoughtAndAnswer() {
  return <Part>[
    Part.text('plan', thought: true, thoughtSignature: <int>[1, 2, 3]),
    Part.text('answer'),
  ];
}

List<String> _partTypes(Object? messages) {
  final List<Object?> list = messages! as List<Object?>;
  final Map<Object?, Object?> firstMsg = list.first! as Map<Object?, Object?>;
  final List<Object?> parts = firstMsg['parts']! as List<Object?>;
  return parts
      .map((Object? p) => (p! as Map<Object?, Object?>)['type'] as String)
      .toList();
}

void main() {
  setUp(() {
    tracer.clear();
    resetOtelLoggerForTest();
    resetAdkMetricsRecorderForTest();
    resetGenAiInstrumentationDetectorForTest();
  });

  tearDown(() {
    tracer.clear();
    resetOtelLoggerForTest();
    resetAdkMetricsRecorderForTest();
    resetGenAiInstrumentationDetectorForTest();
  });

  group('8d064dc91: gen_ai.client.inference.duration', () {
    test('recordClientInferenceDuration emits histogram with semconv attributes and no agent name', () {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
      final LlmResponse response = LlmResponse(
        modelVersion: 'gemini-2.5-flash-001',
      );

      recordClientInferenceDuration(
        elapsedS: 0.42,
        llmRequest: request,
        responses: <LlmResponse>[response],
        recorder: recorder,
      );

      expect(
        genAiClientInferenceDurationMetricName,
        'gen_ai.client.inference.duration',
      );
      expect(recorder.records, hasLength(1));
      final AdkMetricRecord record = recorder.records.single;
      expect(record.name, 'gen_ai.client.inference.duration');
      expect(record.value, 0.42);
      expect(record.unit, 's');
      expect(record.description, 'GenAI client inference operation duration.');
      expect(
        record.explicitBucketBoundariesAdvisory,
        operationDurationBucketBounds,
      );
      expect(record.attributes, <String, Object?>{
        'gen_ai.operation.name': 'generate_content',
        'gen_ai.provider.name': 'gcp.gemini',
        'gen_ai.request.model': 'gemini-2.5-flash',
        'gen_ai.response.model': 'gemini-2.5-flash-001',
      });
      expect(record.attributes.containsKey('gen_ai.agent.name'), isFalse);
    });

    test('recordClientInferenceDuration includes error.type on failure and omits response.model when empty', () {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

      recordClientInferenceDuration(
        elapsedS: 1.25,
        llmRequest: request,
        responses: const <LlmResponse>[],
        error: StateError('boom'),
        environment: const <String, String>{'GOOGLE_GENAI_USE_VERTEXAI': 'true'},
        recorder: recorder,
      );

      final AdkMetricRecord record = recorder.records.single;
      expect(record.attributes, <String, Object?>{
        'gen_ai.operation.name': 'generate_content',
        'gen_ai.provider.name': 'gcp.vertex.agent',
        'gen_ai.request.model': 'gemini-2.5-flash',
        'error.type': 'StateError',
      });
    });

    for (final String schemaVersion in const <String>['1', '2']) {
      test(
        'useInferenceSpan records gen_ai.client.inference.duration alongside operation duration (schema v$schemaVersion)',
        () async {
          final InMemoryAdkMetricsRecorder recorder =
              InMemoryAdkMetricsRecorder();
          setAdkMetricsRecorder(recorder);

          final InvocationContext ctx = _buildInvocationContext();
          final LlmRequest req = LlmRequest(model: 'gemini-2.5-flash');
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
              traceInferenceResult(
                gcSpan,
                LlmResponse(
                  modelVersion: 'gemini-2.5-flash-002',
                  content: Content.modelText('ok'),
                  finishReason: 'STOP',
                ),
                invocationContext: ctx,
              );
            },
            environment: <String, String>{
              'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': schemaVersion,
            },
          );

          final List<AdkMetricRecord> opDurations = recorder.records
              .where(
                (AdkMetricRecord r) =>
                    r.name == genAiClientOperationDurationMetric,
              )
              .toList();
          final List<AdkMetricRecord> infDurations = recorder.records
              .where(
                (AdkMetricRecord r) =>
                    r.name == genAiClientInferenceDurationMetricName,
              )
              .toList();
          expect(opDurations, hasLength(1));
          expect(infDurations, hasLength(1));

          final AdkMetricRecord inf = infDurations.single;
          expect(inf.unit, 's');
          expect(inf.attributes['gen_ai.operation.name'], 'generate_content');
          expect(inf.attributes['gen_ai.provider.name'], 'gcp.gemini');
          expect(inf.attributes['gen_ai.request.model'], 'gemini-2.5-flash');
          expect(
            inf.attributes['gen_ai.response.model'],
            'gemini-2.5-flash-002',
          );
          expect(inf.attributes.containsKey('gen_ai.agent.name'), isFalse);
        },
      );
    }

    test('useInferenceSpan records error.type on inference duration when call throws and skips when instrumentor owns span', () async {
      final InMemoryAdkMetricsRecorder recorder = InMemoryAdkMetricsRecorder();
      setAdkMetricsRecorder(recorder);

      final InvocationContext ctx = _buildInvocationContext();
      final LlmRequest req = LlmRequest(model: 'gemini-2.5-flash');
      final Event event = Event(invocationId: ctx.invocationId, author: 'a');

      await expectLater(
        () => useInferenceSpan(req, ctx, event, (GenerateContentSpan? _) async {
          throw ArgumentError('bad input');
        }),
        throwsArgumentError,
      );

      final AdkMetricRecord inf = recorder.records.singleWhere(
        (AdkMetricRecord r) =>
            r.name == genAiClientInferenceDurationMetricName,
      );
      expect(inf.attributes['error.type'], 'ArgumentError');
      expect(inf.attributes.containsKey('gen_ai.response.model'), isFalse);

      // When external instrumentor records the inference, ADK skips both.
      recorder.clear();
      setGenAiInstrumentationDetectorForTest(() => true, version: '1.0b0');
      await useInferenceSpan(
        req,
        ctx,
        event,
        (GenerateContentSpan? gcSpan) async {
          expect(gcSpan, isNull);
        },
        environment: const <String, String>{
          'ADK_TELEMETRY_SCHEMA_VERSION_OPT_IN': '2',
          'OTEL_SEMCONV_STABILITY_OPT_IN': 'gen_ai_latest_experimental',
        },
      );
      expect(
        recorder.records.where(
          (AdkMetricRecord r) =>
              r.name == genAiClientInferenceDurationMetricName ||
              r.name == genAiClientOperationDurationMetric,
        ),
        isEmpty,
      );
    });
  });

  group('825a44c5d: skip serializing request history when content capture is off', () {
    test('setOperationDetailsAttributesFromRequest skips history under NO_CONTENT and keeps tool definitions', () async {
      final LlmRequest request = _requestWithContentAndTool();
      final Map<String, Object?> full = <String, Object?>{};
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        full,
        request,
      );

      final Map<String, Object?> withoutContent = <String, Object?>{};
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        withoutContent,
        request,
        telemetryConfig: const TelemetryConfig(
          contentCapturingMode: ContentCapturingMode.noContent,
        ),
      );

      expect(
        full.containsKey(experimental_semconv.genAiInputMessages),
        isTrue,
      );
      expect(
        withoutContent.containsKey(experimental_semconv.genAiInputMessages),
        isFalse,
      );
      expect(
        withoutContent.containsKey(
          experimental_semconv.genAiSystemInstructions,
        ),
        isFalse,
      );
      expect(
        withoutContent[experimental_semconv.genAiToolDefinitions],
        full[experimental_semconv.genAiToolDefinitions],
      );

      // Also verify boolean captureMessageContent=false skips history.
      final Map<String, Object?> boolOff = <String, Object?>{};
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        boolOff,
        request,
        telemetryConfig: const TelemetryConfig(captureMessageContent: false),
      );
      expect(
        boolOff.containsKey(experimental_semconv.genAiInputMessages),
        isFalse,
      );
      expect(
        boolOff[experimental_semconv.genAiToolDefinitions],
        full[experimental_semconv.genAiToolDefinitions],
      );
    });

    for (final ContentCapturingMode mode in const <ContentCapturingMode>[
      ContentCapturingMode.eventOnly,
      ContentCapturingMode.spanOnly,
      ContentCapturingMode.spanAndEvent,
    ]) {
      test(
        'setOperationDetailsAttributesFromRequest serializes full attributes under $mode',
        () async {
          final LlmRequest request = _requestWithContentAndTool();
          final Map<String, Object?> full = <String, Object?>{};
          await experimental_semconv.setOperationDetailsAttributesFromRequest(
            full,
            request,
          );

          final Map<String, Object?> withContent = <String, Object?>{};
          await experimental_semconv.setOperationDetailsAttributesFromRequest(
            withContent,
            request,
            telemetryConfig: TelemetryConfig(contentCapturingMode: mode),
          );

          expect(withContent, equals(full));
        },
      );
    }

    test('useInferenceSpan passes telemetryConfig so NO_CONTENT skips input messages and log redaction matches', () async {
      final LlmRequest request = _requestWithContentAndTool();
      final InvocationContext ctx = _buildInvocationContext(
        telemetryConfig: const TelemetryConfig(
          genaiSemconvStabilityOptIn: 'experimental',
          contentCapturingMode: ContentCapturingMode.noContent,
        ),
      );
      final Event event = Event(invocationId: ctx.invocationId, author: 'a');

      await useInferenceSpan(request, ctx, event, (
        GenerateContentSpan? gcSpan,
      ) async {
        expect(gcSpan, isNotNull);
        expect(
          gcSpan!.operationDetailsAttributes.containsKey(
            experimental_semconv.genAiInputMessages,
          ),
          isFalse,
        );
        expect(
          gcSpan.operationDetailsAttributes.containsKey(
            experimental_semconv.genAiSystemInstructions,
          ),
          isFalse,
        );
        expect(
          gcSpan.operationDetailsAttributes[experimental_semconv
              .genAiToolDefinitions],
          isNotEmpty,
        );
      });

      final OTelLogRecord detailsLog = otelLogger.records.singleWhere(
        (OTelLogRecord r) =>
            r.eventName == 'gen_ai.client.inference.operation.details',
      );
      expect(
        detailsLog.attributes.containsKey(
          experimental_semconv.genAiInputMessages,
        ),
        isFalse,
      );
      expect(
        detailsLog.attributes.containsKey(
          experimental_semconv.genAiToolDefinitions,
        ),
        isTrue,
      );
    });
  });

  group('0019b8658: experimental reasoning parts in gen_ai messages', () {
    test('output reasoning parts are tagged apart from the answer when reasoning is enabled', () {
      final LlmResponse llmResponse = LlmResponse(
        content: Content(role: 'model', parts: _thoughtAndAnswer()),
        finishReason: 'STOP',
      );

      final Map<String, Object?> details = <String, Object?>{};
      final Map<String, Object?> common = <String, Object?>{};
      experimental_semconv.setOperationDetailsAttributesFromResponse(
        llmResponse,
        details,
        common,
        reasoning: true,
      );

      expect(details[experimental_semconv.genAiOutputMessages], <Object?>[
        <String, Object?>{
          'role': 'assistant',
          'parts': <Object?>[
            <String, Object?>{'content': 'plan', 'type': 'reasoning'},
            <String, Object?>{'content': 'answer', 'type': 'text'},
          ],
          'finish_reason': 'stop',
        },
      ]);
    });

    test('the reasoning feature leaves the answer part unchanged and defaults to text when off', () {
      final LlmResponse llmResponse = LlmResponse(
        content: Content(role: 'model', parts: _thoughtAndAnswer()),
        finishReason: 'STOP',
      );

      final Map<String, Object?> onDetails = <String, Object?>{};
      final Map<String, Object?> offDetails = <String, Object?>{};
      experimental_semconv.setOperationDetailsAttributesFromResponse(
        llmResponse,
        onDetails,
        <String, Object?>{},
        reasoning: true,
      );
      experimental_semconv.setOperationDetailsAttributesFromResponse(
        llmResponse,
        offDetails,
        <String, Object?>{},
      );

      final List<Object?> onParts =
          ((onDetails[experimental_semconv.genAiOutputMessages] as List).first
                  as Map)['parts']
              as List<Object?>;
      final List<Object?> offParts =
          ((offDetails[experimental_semconv.genAiOutputMessages] as List).first
                  as Map)['parts']
              as List<Object?>;
      expect(onParts[1], equals(offParts[1]));
      expect(
        _partTypes(offDetails[experimental_semconv.genAiOutputMessages]),
        <String>['text', 'text'],
      );
    });

    test('replayed thought parts are tagged in input messages when reasoning is enabled and stay text when off', () async {
      final LlmRequest llmRequest = LlmRequest(
        model: 'some-model',
        contents: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              ..._thoughtAndAnswer(),
              Part(thought: true, thoughtSignature: <int>[1, 2, 3]),
            ],
          ),
        ],
      );

      final Map<String, Object?> onAttrs = <String, Object?>{};
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        onAttrs,
        llmRequest,
        reasoning: true,
      );
      expect(onAttrs[experimental_semconv.genAiInputMessages], <Object?>[
        <String, Object?>{
          'role': 'assistant',
          'parts': <Object?>[
            <String, Object?>{'content': 'plan', 'type': 'reasoning'},
            <String, Object?>{'content': 'answer', 'type': 'text'},
          ],
        },
      ]);

      final Map<String, Object?> offAttrs = <String, Object?>{};
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        offAttrs,
        llmRequest,
      );
      expect(
        _partTypes(offAttrs[experimental_semconv.genAiInputMessages]),
        <String>['text', 'text'],
      );
    });

    for (final (bool reasoning, List<String> expected) in const <(bool, List<String>)>[
      (true, <String>['reasoning', 'text']),
      (false, <String>['text', 'text']),
    ]) {
      test(
        'TelemetryConfig experimentalFeaturesOptIn reaches request mapping (reasoning=$reasoning)',
        () async {
          final TelemetryConfig config = TelemetryConfig(
            genaiSemconvStabilityOptIn: 'experimental',
            contentCapturingMode: ContentCapturingMode.eventOnly,
            experimentalFeaturesOptIn: reasoning
                ? const <String>{'reasoning'}
                : null,
          );
          final InvocationContext ctx = _buildInvocationContext(
            telemetryConfig: config,
          );
          final LlmRequest request = LlmRequest(
            model: 'some-model',
            contents: <Content>[
              Content(role: 'model', parts: _thoughtAndAnswer()),
            ],
          );
          final Event event = Event(
            invocationId: ctx.invocationId,
            author: 'a',
          );

          await useInferenceSpan(request, ctx, event, (
            GenerateContentSpan? gcSpan,
          ) async {
            expect(gcSpan, isNotNull);
            expect(
              _partTypes(
                gcSpan!.operationDetailsAttributes[experimental_semconv
                    .genAiInputMessages],
              ),
              expected,
            );
          });
        },
      );

      test(
        'TelemetryConfig experimentalFeaturesOptIn reaches response mapping (reasoning=$reasoning)',
        () async {
          final TelemetryConfig config = TelemetryConfig(
            genaiSemconvStabilityOptIn: 'experimental',
            contentCapturingMode: ContentCapturingMode.eventOnly,
            experimentalFeaturesOptIn: reasoning
                ? const <String>{'reasoning'}
                : null,
          );
          final InvocationContext ctx = _buildInvocationContext(
            telemetryConfig: config,
          );
          final LlmRequest request = LlmRequest(
            model: 'some-model',
            contents: const <Content>[],
          );
          final LlmResponse response = LlmResponse(
            content: Content(role: 'model', parts: _thoughtAndAnswer()),
            finishReason: 'STOP',
          );
          final Event event = Event(
            invocationId: ctx.invocationId,
            author: 'a',
          );

          await useInferenceSpan(request, ctx, event, (
            GenerateContentSpan? gcSpan,
          ) async {
            expect(gcSpan, isNotNull);
            traceInferenceResult(gcSpan, response, invocationContext: ctx);
            expect(
              _partTypes(
                gcSpan!.operationDetailsAttributes[experimental_semconv
                    .genAiOutputMessages],
              ),
              expected,
            );
          });

          final OTelLogRecord detailsLog = otelLogger.records.singleWhere(
            (OTelLogRecord r) =>
                r.eventName == 'gen_ai.client.inference.operation.details',
          );
          expect(
            _partTypes(
              detailsLog.attributes[experimental_semconv.genAiOutputMessages],
            ),
            expected,
          );
        },
      );
    }

    test('TelemetryConfig recognizes reasoning in recognizedExperimentalFeatures and honors env/lock precedence', () {
      expect(
        TelemetryConfig.recognizedExperimentalFeatures,
        contains('reasoning'),
      );

      const TelemetryConfig blankOn = TelemetryConfig(
        adkExperimentalTelemetryOptIn: true,
      );
      expect(blankOn.isExperimentalFeatureEnabled('reasoning'), isTrue);
      expect(blankOn.isExperimentalFeatureEnabled('unknown_feature'), isFalse);

      const TelemetryConfig otherOnly = TelemetryConfig(
        experimentalFeaturesOptIn: <String>{'skills'},
      );
      expect(otherOnly.isExperimentalFeatureEnabled('reasoning'), isFalse);
      expect(otherOnly.isExperimentalFeatureEnabled('skills'), isTrue);

      const TelemetryConfig envFallback = TelemetryConfig();
      expect(
        envFallback.isExperimentalFeatureEnabled(
          'reasoning',
          environment: const <String, String>{
            'ADK_EXPERIMENTAL_TELEMETRY_FEATURES': 'skills,reasoning',
          },
        ),
        isTrue,
      );
      expect(
        otherOnly.isExperimentalFeatureEnabled(
          'reasoning',
          environment: const <String, String>{
            'ADK_TELEMETRY_IGNORE_RUN_CONFIG': '1',
            'ADK_EXPERIMENTAL_TELEMETRY_FEATURES': 'reasoning',
          },
        ),
        isTrue,
      );
    });
  });
}
