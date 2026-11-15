import 'dart:typed_data';

import 'package:adk_dart/adk_core.dart';
import 'package:adk_dart/evaluation.dart';
import 'package:test/test.dart';

const Map<String, Object?> _userContent = <String, Object?>{
  'role': 'user',
  'parts': <Object?>[
    <String, Object?>{'text': 'User input here.'},
  ],
};

Map<String, Object?> _usage({
  int? prompt = 0,
  int? candidates = 0,
  int? cached = 0,
  int? thoughts = 0,
  int? toolUsePrompt = 0,
  int? backendTotal,
}) {
  return <String, Object?>{
    'prompt_token_count': ?prompt,
    'candidates_token_count': ?candidates,
    'total_token_count': ?backendTotal,
    'cached_content_token_count': ?cached,
    'thoughts_token_count': ?thoughts,
    'tool_use_prompt_token_count': ?toolUsePrompt,
  };
}

Invocation _invocationWithUsages(List<Map<String, Object?>?> usages) {
  return Invocation(
    userContent: _userContent,
    intermediateData: InvocationEvents(
      invocationEvents: <InvocationEvent>[
        for (final Map<String, Object?>? usage in usages)
          InvocationEvent(author: 'agent', usageMetadata: usage),
      ],
    ),
  );
}

Map<String, Object?> _toolCall(String name) {
  return <String, Object?>{'name': name, 'args': <String, Object?>{}};
}

Uint8List _pcm(List<int> samples) {
  final Uint8List bytes = Uint8List(samples.length * 2);
  final ByteData view = ByteData.sublistView(bytes);
  for (int i = 0; i < samples.length; i += 1) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

List<int> _samples(List<int> pcmBytes) {
  final Uint8List raw = Uint8List.fromList(pcmBytes);
  final int count = raw.length ~/ 2;
  final ByteData view = ByteData.sublistView(raw);
  return <int>[
    for (int i = 0; i < count; i += 1) view.getInt16(i * 2, Endian.little),
  ];
}

Uint8List _buildWavPcm16(
  List<int> interleavedSamples, {
  required int sampleRate,
  int numChannels = 1,
}) {
  final Uint8List pcmData = _pcm(interleavedSamples);
  final int totalSize = 44 + pcmData.length;
  final Uint8List wav = Uint8List(totalSize);
  final ByteData view = ByteData.sublistView(wav);

  void writeAscii(int offset, String s) {
    for (int i = 0; i < s.length; i += 1) {
      wav[offset + i] = s.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  view.setUint32(4, 36 + pcmData.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, numChannels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * numChannels * 2, Endian.little);
  view.setUint16(32, numChannels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little); // 16-bit
  writeAscii(36, 'data');
  view.setUint32(40, pcmData.length, Endian.little);
  wav.setRange(44, totalSize, pcmData);
  return wav;
}

class _FakeStreamLlm extends BaseLlm {
  _FakeStreamLlm({required super.model, required this.responses});

  final List<LlmResponse> responses;
  final List<LlmRequest> capturedRequests = <LlmRequest>[];

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    capturedRequests.add(request);
    for (final LlmResponse response in responses) {
      yield response;
    }
  }
}

class _ScriptedUserSimulator extends UserSimulator<BaseUserSimulatorConfig> {
  _ScriptedUserSimulator(this.results)
    : super(
        config: BaseUserSimulatorConfig(),
        configDecoder: (BaseUserSimulatorConfig c) => c,
      );

  final List<NextUserMessage> results;
  int _index = 0;

  @override
  Future<NextUserMessage> getNextUserMessage(List<Event> events) async {
    if (_index >= results.length) {
      return NextUserMessage(status: Status.stopSignalDetected);
    }
    final NextUserMessage next = results[_index];
    _index += 1;
    return next;
  }

  @override
  Evaluator? getSimulationEvaluator() => null;
}

void main() {
  group('Efficiency Evaluators parity', () {
    group('Threshold rejection & empty invocations', () {
      test('rejects configured threshold on EvalMetricSpec across all 4 evaluators', () {
        expect(
          () => ToolCallCountV1Evaluator(
            evalMetric: EvalMetricSpec(
              metricName: PrebuiltMetricNames.toolCallCountV1,
              threshold: 1.0,
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message.toString(),
              'message',
              contains('does not support a threshold'),
            ),
          ),
        );
        expect(
          () => InferenceCallCountV1Evaluator(
            evalMetric: EvalMetricSpec(
              metricName: PrebuiltMetricNames.inferenceCallCountV1,
              threshold: 1.0,
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => TokenUsageV1Evaluator(
            evalMetric: EvalMetricSpec(
              metricName: PrebuiltMetricNames.tokenUsageV1,
              threshold: 1.0,
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => InvocationDurationV1Evaluator(
            evalMetric: EvalMetricSpec(
              metricName: PrebuiltMetricNames.invocationDurationV1,
              threshold: 1.0,
            ),
          ),
          throwsArgumentError,
        );
      });

      test('rejects threshold configured via criterion', () {
        expect(
          () => TokenUsageV1Evaluator(
            evalMetric: EvalMetricSpec(
              metricName: PrebuiltMetricNames.tokenUsageV1,
              criterion: BaseCriterion(threshold: 0.5),
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message.toString(),
              'message',
              contains('does not support a threshold'),
            ),
          ),
        );
      });

      test('empty invocation list returns informational status with null score', () {
        final ToolCallCountV1Evaluator evaluator = ToolCallCountV1Evaluator(
          evalMetric: EvalMetricSpec(
            metricName: PrebuiltMetricNames.toolCallCountV1,
          ),
        );
        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[],
        );
        expect(result.overallScore, isNull);
        expect(result.overallEvalStatus, EvalStatus.informational);
        expect(result.perInvocationResults, isEmpty);
      });
    });

    group('ToolCallCountV1Evaluator', () {
      test('counts tool calls per invocation and averages across turns', () {
        final ToolCallCountV1Evaluator evaluator = ToolCallCountV1Evaluator(
          evalMetric: EvalMetricSpec(
            metricName: PrebuiltMetricNames.toolCallCountV1,
          ),
        );
        final Invocation inv1 = Invocation(
          userContent: _userContent,
          intermediateData: IntermediateData(
            toolUses: <EvalJsonMap>[_toolCall('a'), _toolCall('b')],
          ),
        );
        final Invocation inv2 = Invocation(
          userContent: _userContent,
          intermediateData: IntermediateData(
            toolUses: <EvalJsonMap>[_toolCall('a')],
          ),
        );

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv1, inv2],
        );

        expect(result.overallScore, 1.5);
        expect(result.overallEvalStatus, EvalStatus.informational);
        expect(result.perInvocationResults[0].score, 2.0);
        expect(
          result.perInvocationResults[0].evalStatus,
          EvalStatus.informational,
        );
        expect(result.perInvocationResults[1].score, 1.0);
        expect(
          result.perInvocationResults[1].evalStatus,
          EvalStatus.informational,
        );
      });

      test('never fails even for high tool call counts', () {
        final ToolCallCountV1Evaluator evaluator = ToolCallCountV1Evaluator();
        final Invocation inv = Invocation(
          userContent: _userContent,
          intermediateData: IntermediateData(
            toolUses: <EvalJsonMap>[
              _toolCall('a'),
              _toolCall('b'),
              _toolCall('c'),
            ],
          ),
        );

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv],
        );
        expect(result.overallScore, 3.0);
        expect(result.overallEvalStatus, EvalStatus.informational);
      });
    });

    group('InferenceCallCountV1Evaluator', () {
      test('counts model call events with usageMetadata or modelVersion', () {
        final InferenceCallCountV1Evaluator evaluator =
            InferenceCallCountV1Evaluator(
              evalMetric: EvalMetricSpec(
                metricName: PrebuiltMetricNames.inferenceCallCountV1,
              ),
            );
        final Invocation inv = Invocation(
          userContent: _userContent,
          intermediateData: InvocationEvents(
            invocationEvents: <InvocationEvent>[
              InvocationEvent(author: 'agent', usageMetadata: _usage()),
              InvocationEvent(author: 'agent', modelVersion: 'gemini-2.5-flash'),
              InvocationEvent(author: 'user'), // Not a model call event
            ],
          ),
        );

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv],
        );
        expect(result.overallScore, 2.0);
        expect(result.overallEvalStatus, EvalStatus.informational);
      });

      test('returns null when intermediateData is not captured', () {
        final InferenceCallCountV1Evaluator evaluator =
            InferenceCallCountV1Evaluator();
        final Invocation inv = Invocation(userContent: _userContent);

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv],
        );
        expect(result.overallScore, isNull);
        expect(result.perInvocationResults[0].score, isNull);
        expect(
          result.perInvocationResults[0].evalStatus,
          EvalStatus.informational,
        );
      });

      test('empty InvocationEvents list counts as zero calls', () {
        final InferenceCallCountV1Evaluator evaluator =
            InferenceCallCountV1Evaluator();
        final Invocation inv = Invocation(
          userContent: _userContent,
          intermediateData: InvocationEvents(invocationEvents: <InvocationEvent>[]),
        );

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv],
        );
        expect(result.overallScore, 0.0);
      });
    });

    group('TokenUsageV1Evaluator', () {
      test('sums total tokens across model calls and derives total from input + output', () {
        final TokenUsageV1Evaluator evaluator = TokenUsageV1Evaluator(
          evalMetric: EvalMetricSpec(
            metricName: PrebuiltMetricNames.tokenUsageV1,
          ),
        );
        final Invocation inv1 = _invocationWithUsages(<Map<String, Object?>>[
          _usage(prompt: 60, candidates: 40),
          _usage(prompt: 200, candidates: 50),
        ]);

        final EvaluationResult result1 = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv1],
        );
        expect(result1.overallScore, 350.0);
        expect(result1.overallEvalStatus, EvalStatus.informational);

        // Backend total disagrees with parts; derived sum (100 + 20 + 5 = 125) wins.
        final Invocation inv2 = _invocationWithUsages(<Map<String, Object?>>[
          _usage(prompt: 100, candidates: 20, thoughts: 5, backendTotal: 9999),
        ]);
        final EvaluationResult result2 = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[inv2],
        );
        expect(result2.overallScore, 125.0);
      });

      test('reports nested token breakdown agreeing with telemetry TokenUsage', () {
        final TokenUsageV1Evaluator evaluator = TokenUsageV1Evaluator();
        final Map<String, Object?> usageMeta = _usage(
          prompt: 700,
          cached: 100,
          toolUsePrompt: 20,
          candidates: 200,
          thoughts: 80,
        );
        final TokenUsage telemetryUsage = TokenUsage.fromUsageMetadata(
          usageMeta,
        );

        final EvaluationResult result = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[
            _invocationWithUsages(<Map<String, Object?>>[usageMeta]),
          ],
        );

        final TokenUsageDetails? details = result.overallTokenUsageDetails;
        expect(details, isNotNull);
        expect(details!.inputTokens, 720.0);
        expect(details.promptTokens, 700.0);
        expect(details.cachedTokens, 100.0);
        expect(details.toolUseTokens, 20.0);
        expect(details.outputTokens, 280.0);
        expect(details.candidatesTokens, 200.0);
        expect(details.reasoningTokens, 80.0);
        expect(details.totalTokens, 1000.0);

        expect(details.inputTokens, telemetryUsage.inputTokens!.toDouble());
        expect(details.outputTokens, telemetryUsage.outputTokens!.toDouble());
        expect(details.totalTokens, telemetryUsage.totalTokens.toDouble());
      });

      test('preserves null for unreported buckets and excludes n/a turns from average', () {
        final TokenUsageV1Evaluator evaluator = TokenUsageV1Evaluator();

        // Single call reporting only prompt tokens -> output/cached/tool/reasoning stay null.
        final Invocation promptOnly = _invocationWithUsages(
          <Map<String, Object?>>[
            <String, Object?>{'prompt_token_count': 500},
          ],
        );
        final EvaluationResult promptOnlyResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[promptOnly],
        );
        final TokenUsageDetails singleDetails =
            promptOnlyResult.overallTokenUsageDetails!;
        expect(singleDetails.promptTokens, 500.0);
        expect(singleDetails.inputTokens, 500.0);
        expect(singleDetails.totalTokens, 500.0);
        expect(singleDetails.outputTokens, isNull);
        expect(singleDetails.candidatesTokens, isNull);
        expect(singleDetails.reasoningTokens, isNull);
        expect(singleDetails.cachedTokens, isNull);
        expect(singleDetails.toolUseTokens, isNull);

        // Two reported turns where second omits thoughts -> thoughts averages 40 / 2 = 20.0.
        final Invocation reportsThoughts = _invocationWithUsages(
          <Map<String, Object?>>[
            _usage(prompt: 50, candidates: 10, thoughts: 40),
          ],
        );
        final Invocation omitsThoughts = _invocationWithUsages(
          <Map<String, Object?>>[
            <String, Object?>{
              'prompt_token_count': 200,
              'candidates_token_count': 100,
            },
          ],
        );
        final EvaluationResult twoTurnResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[reportsThoughts, omitsThoughts],
        );
        expect(twoTurnResult.overallTokenUsageDetails!.totalTokens, 200.0);
        expect(twoTurnResult.overallTokenUsageDetails!.reasoningTokens, 20.0);

        // Unreported and cached-only turns have null totalTokens and are excluded from denominator.
        final Invocation reported = _invocationWithUsages(<Map<String, Object?>>[
          _usage(prompt: 900, candidates: 100, thoughts: 40),
        ]);
        final Invocation unreported = Invocation(
          userContent: _userContent,
          intermediateData: InvocationEvents(
            invocationEvents: <InvocationEvent>[
              InvocationEvent(author: 'agent', modelVersion: 'test-model'),
            ],
          ),
        );
        final Invocation cachedOnly = _invocationWithUsages(
          <Map<String, Object?>>[
            <String, Object?>{'cached_content_token_count': 50},
          ],
        );
        final EvaluationResult mixedResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[reported, unreported, cachedOnly],
        );
        expect(
          mixedResult.perInvocationResults.map((PerInvocationResult r) => r.score),
          <double?>[1040.0, null, null],
        );
        expect(mixedResult.overallScore, 1040.0);
        expect(mixedResult.overallTokenUsageDetails!.totalTokens, 1040.0);
        expect(mixedResult.overallTokenUsageDetails!.inputTokens, 900.0);
        expect(mixedResult.overallTokenUsageDetails!.outputTokens, 140.0);
        expect(mixedResult.overallTokenUsageDetails!.reasoningTokens, 40.0);
        expect(mixedResult.overallTokenUsageDetails!.cachedTokens, 0.0);
      });
    });

    group('InvocationDurationV1Evaluator', () {
      test('reports wall-clock duration, breakdown, clamping, and timed-only averaging', () {
        final InvocationDurationV1Evaluator evaluator =
            InvocationDurationV1Evaluator(
              evalMetric: EvalMetricSpec(
                metricName: PrebuiltMetricNames.invocationDurationV1,
              ),
            );

        // Partitioned breakdown: 10.0 - 6.0 - 3.0 = 1.0 framework seconds.
        final Invocation splitTurn = TimedInvocation(
          userContent: _userContent,
          duration: 10.0,
          modelDuration: 6.0,
          toolDuration: 3.0,
        );
        final EvaluationResult splitResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[splitTurn],
        );
        final DurationDetails splitDetails =
            splitResult.perInvocationResults[0].durationDetails!;
        expect(splitResult.overallScore, 10.0);
        expect(splitResult.overallEvalStatus, EvalStatus.informational);
        expect(splitDetails.totalSeconds, 10.0);
        expect(splitDetails.modelSeconds, 6.0);
        expect(splitDetails.toolSeconds, 3.0);
        expect(splitDetails.frameworkSeconds, 1.0);

        // Negative remainder clamped to 0.0.
        final Invocation slightOverhang = TimedInvocation(
          userContent: _userContent,
          duration: 2.0,
          modelDuration: 2.001,
          toolDuration: 0.0,
        );
        final EvaluationResult clampedResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[slightOverhang],
        );
        expect(
          clampedResult.perInvocationResults[0].durationDetails!.frameworkSeconds,
          0.0,
        );

        // Unsplit turn & untimed turn averaging:
        final Invocation timedSplit = TimedInvocation(
          userContent: _userContent,
          duration: 10.0,
          modelDuration: 6.0,
          toolDuration: 2.0,
        );
        final Invocation timedUnsplit = TimedInvocation(
          userContent: _userContent,
          duration: 20.0,
        );
        final Invocation untimed = Invocation(userContent: _userContent);

        final EvaluationResult avgResult = evaluator.evaluateInvocations(
          actualInvocations: <Invocation>[timedSplit, timedUnsplit, untimed],
        );
        expect(avgResult.overallScore, 15.0);
        expect(avgResult.overallDurationDetails!.totalSeconds, 15.0);
        expect(avgResult.overallDurationDetails!.modelSeconds, 6.0);
        expect(avgResult.overallDurationDetails!.toolSeconds, 2.0);
        expect(avgResult.overallDurationDetails!.frameworkSeconds, 2.0);
        expect(
          avgResult.perInvocationResults[2].durationDetails!.totalSeconds,
          isNull,
        );
      });
    });
  });

  group('MetricEvaluatorRegistry & registerCustomMetricsFromConfig parity', () {
    test('default registry registers all 4 efficiency metrics', () {
      final MetricEvaluatorRegistry registry =
          getDefaultMetricEvaluatorRegistry();
      final Set<String> registeredNames = registry
          .getRegisteredMetrics()
          .map((MetricInfo info) => info.metricName)
          .toSet();

      expect(
        registeredNames,
        containsAll(<String>[
          PrebuiltMetricNames.toolCallCountV1,
          PrebuiltMetricNames.inferenceCallCountV1,
          PrebuiltMetricNames.invocationDurationV1,
          PrebuiltMetricNames.tokenUsageV1,
        ]),
      );

      expect(
        registry.getEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.toolCallCountV1),
        ),
        isA<ToolCallCountV1Evaluator>(),
      );
      expect(
        registry.getEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.inferenceCallCountV1),
        ),
        isA<InferenceCallCountV1Evaluator>(),
      );
      expect(
        registry.getEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.invocationDurationV1),
        ),
        isA<InvocationDurationV1Evaluator>(),
      );
      expect(
        registry.getEvaluator(
          EvalMetricSpec(metricName: PrebuiltMetricNames.tokenUsageV1),
        ),
        isA<TokenUsageV1Evaluator>(),
      );
    });

    test('registerCustomMetricsFromConfig registers custom metrics, overrides metricInfo name, ignores spec override, and survives fork()', () async {
      const String customMetricName = 'custom_metric_nov15_test';
      const String configFnPath = 'pkg.nov15.trustedFn';
      const String untrustedFnPath = 'pkg.nov15.untrustedFn';

      registerCustomMetricFunction(configFnPath, (
        EvalMetricSpec evalMetric,
        List<Invocation> actualInvocations,
        List<Invocation>? expectedInvocations,
        ConversationScenario? conversationScenario,
      ) {
        return EvaluationResult(
          overallScore: 0.88,
          overallEvalStatus: EvalStatus.passed,
        );
      });
      registerCustomMetricFunction(untrustedFnPath, (
        EvalMetricSpec evalMetric,
        List<Invocation> actualInvocations,
        List<Invocation>? expectedInvocations,
        ConversationScenario? conversationScenario,
      ) {
        return EvaluationResult(
          overallScore: 0.0,
          overallEvalStatus: EvalStatus.failed,
        );
      });
      addTearDown(() {
        unregisterCustomMetricFunction(configFnPath);
        unregisterCustomMetricFunction(untrustedFnPath);
      });

      final MetricEvaluatorRegistry registry =
          getDefaultMetricEvaluatorRegistry();
      final EvalConfig configWithInfo = EvalConfig(
        customMetrics: <String, CustomMetricConfig>{
          customMetricName: CustomMetricConfig(
            codeConfig: CodeConfig(name: configFnPath),
            metricInfo: MetricInfo(
              metricName: 'name_to_be_overridden',
              description: 'Custom description',
              metricValueInfo: MetricValueInfo(
                interval: Interval(minValue: 0.0, maxValue: 5.0),
              ),
            ),
          ),
          'default_info_metric': CustomMetricConfig(
            codeConfig: CodeConfig(name: configFnPath),
            description: 'Default interval description',
          ),
        },
      );

      final MetricEvaluatorRegistry returned = registerCustomMetricsFromConfig(
        configWithInfo,
        registry,
      );
      expect(identical(returned, registry), isTrue);

      final List<MetricInfo> registered = registry.getRegisteredMetrics();
      expect(
        registered.any((MetricInfo m) => m.metricName == 'name_to_be_overridden'),
        isFalse,
      );

      final MetricInfo customInfo = registered.firstWhere(
        (MetricInfo m) => m.metricName == customMetricName,
      );
      expect(customInfo.metricValueInfo.interval?.maxValue, 5.0);

      final MetricInfo defaultInfo = registered.firstWhere(
        (MetricInfo m) => m.metricName == 'default_info_metric',
      );
      expect(defaultInfo.description, 'Default interval description');
      expect(defaultInfo.metricValueInfo.interval?.minValue, 0.0);
      expect(defaultInfo.metricValueInfo.interval?.maxValue, 1.0);

      // Config-registered function path takes precedence over untrusted spec path.
      final Evaluator evaluator = registry.getEvaluator(
        EvalMetricSpec(
          metricName: customMetricName,
          threshold: 0.5,
          customFunctionPath: untrustedFnPath,
        ),
      );
      expect(evaluator, isA<CustomMetricEvaluator>());
      final EvaluationResult evalResult = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[Invocation(userContent: _userContent)],
      );
      expect(evalResult.overallScore, 0.88);

      // Fork carries over custom function paths even when EvalMetricSpec omits customFunctionPath.
      final MetricEvaluatorRegistry forked = registry.fork();
      final Evaluator forkedEvaluator = forked.getEvaluator(
        EvalMetricSpec(metricName: customMetricName, threshold: 0.5),
      );
      final EvaluationResult forkedResult = await forkedEvaluator
          .evaluateInvocations(
            actualInvocations: <Invocation>[
              Invocation(userContent: _userContent),
            ],
          );
      expect(forkedResult.overallScore, 0.88);
    });

    test('registerCustomMetricsFromConfig is a no-op when customMetrics is empty', () {
      final MetricEvaluatorRegistry registry =
          getDefaultMetricEvaluatorRegistry();
      final int beforeCount = registry.getRegisteredMetrics().length;
      final MetricEvaluatorRegistry result = registerCustomMetricsFromConfig(
        EvalConfig(),
        registry,
      );
      expect(identical(result, registry), isTrue);
      expect(registry.getRegisteredMetrics().length, beforeCount);
    });
  });

  group('Audio utils parity', () {
    test('parseSampleRate extracts standalone rate parameter case-insensitively', () {
      expect(parseSampleRate('audio/l16; rate=24000', defaultRate: 8000), 24000);
      expect(parseSampleRate('audio/pcm', defaultRate: 16000), 16000);
      expect(parseSampleRate(null, defaultRate: 16000), 16000);
      expect(parseSampleRate('audio/pcm;bitrate=128000', defaultRate: 24000), 24000);
      expect(parseSampleRate('audio/pcm;RATE=16000', defaultRate: 24000), 16000);
    });

    test('resamplePcm16 validates rates, handles edge cases, downsamples, and interpolates accurately', () {
      expect(
        () => resamplePcm16(_pcm(<int>[1, 2]), fromRate: 0, toRate: 16000),
        throwsArgumentError,
      );
      expect(
        () => resamplePcm16(_pcm(<int>[1, 2]), fromRate: 24000, toRate: 0),
        throwsArgumentError,
      );

      final Uint8List matching = _pcm(<int>[1, 2, 3, 4]);
      expect(resamplePcm16(matching, fromRate: 16000, toRate: 16000), matching);
      expect(resamplePcm16(Uint8List(0), fromRate: 24000, toRate: 16000), isEmpty);

      final Uint8List single = _pcm(<int>[42]);
      expect(resamplePcm16(single, fromRate: 24000, toRate: 16000), single);

      // 600 samples at 24 kHz -> 400 samples at 16 kHz.
      final Uint8List pcm600 = _pcm(List<int>.generate(600, (int i) => i));
      final Uint8List downsampled = resamplePcm16(
        pcm600,
        fromRate: 24000,
        toRate: 16000,
      );
      expect(_samples(downsampled), hasLength(400));

      // Linear interpolation: index 1 at ratio 1.5 -> halfway between 100 and 200 = 150.
      final Uint8List ramp = _pcm(<int>[0, 100, 200, 300]);
      final List<int> rampOut = _samples(
        resamplePcm16(ramp, fromRate: 24000, toRate: 16000),
      );
      expect(rampOut[1], 150);

      // Signed negative samples interpolate accurately too.
      final Uint8List negRamp = _pcm(<int>[0, -100, -200, -300]);
      final List<int> negRampOut = _samples(
        resamplePcm16(negRamp, fromRate: 24000, toRate: 16000),
      );
      expect(negRampOut[1], -150);
    });

    test('toLiveInput resamples raw PCM and strips/resamples RIFF WAV headers to 16 kHz PCM', () {
      final Uint8List pcm600 = _pcm(List<int>.generate(600, (int i) => i));

      final Blob fromDeclared = toLiveInput(
        Blob(mimeType: 'audio/l16; rate=24000', data: pcm600),
      );
      expect(fromDeclared.mimeType, 'audio/pcm;rate=16000');
      expect(_samples(fromDeclared.data), hasLength(400));

      // Missing rate= defaults to 24 kHz TTS output rate.
      final Blob fromDefault = toLiveInput(
        Blob(mimeType: 'audio/pcm', data: pcm600),
      );
      expect(fromDefault.mimeType, 'audio/pcm;rate=16000');
      expect(_samples(fromDefault.data), hasLength(400));

      // Already at 16 kHz passes through unchanged.
      final Uint8List pcm16k = _pcm(<int>[10, 20, 30, 40]);
      final Blob passthrough = toLiveInput(
        Blob(mimeType: 'audio/pcm;rate=16000', data: pcm16k),
      );
      expect(passthrough.mimeType, 'audio/pcm;rate=16000');
      expect(passthrough.data, pcm16k);

      // RIFF/WAVE 24 kHz mono WAV strips 44-byte header and resamples 600 -> 400 samples.
      final Uint8List wav24k = _buildWavPcm16(
        List<int>.generate(600, (int i) => i * 10),
        sampleRate: 24000,
      );
      final Blob fromWav = toLiveInput(
        Blob(mimeType: 'audio/wav', data: wav24k),
      );
      expect(fromWav.mimeType, 'audio/pcm;rate=16000');
      expect(_samples(fromWav.data), hasLength(400));
      expect(_samples(fromWav.data)[0], 0);
      expect(_samples(fromWav.data)[1], 15);
    });
  });

  group('LlmAudioUserSimulator parity', () {
    test('config defaults and customInstructions placeholder validation', () {
      final LlmAudioUserSimulatorConfig config = LlmAudioUserSimulatorConfig();
      expect(config.type, 'llm_audio');
      expect(config.model, 'gemini-2.5-flash');
      expect(config.audioModel, 'cloud_tts');
      expect(config.includeTextWithAudio, isTrue);

      expect(
        () => LlmAudioUserSimulatorConfig(
          customInstructions: 'missing placeholders',
        ),
        throwsArgumentError,
      );

      final LlmAudioUserSimulatorConfig validCustom =
          LlmAudioUserSimulatorConfig(
            customInstructions:
                '{{ stop_signal }} {{ conversation_plan }} {{ conversation_history }}',
          );
      expect(validCustom.customInstructions, isNotNull);
    });

    test('toAudioContent concatenates streamed chunks and resamples 24 kHz to 16 kHz PCM', () async {
      // Split 600 samples at 24 kHz across two streamed chunks (300 + 300 samples).
      final Uint8List chunk1 = _pcm(List<int>.generate(300, (int i) => i * 2));
      final Uint8List chunk2 = _pcm(
        List<int>.generate(300, (int i) => (300 + i) * 2),
      );
      final _FakeStreamLlm audioLlm = _FakeStreamLlm(
        model: 'gemini-tts',
        responses: <LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromInlineData(
                  mimeType: 'audio/l16;rate=24000',
                  data: chunk1,
                ),
              ],
            ),
          ),
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromInlineData(
                  mimeType: 'audio/l16;rate=24000',
                  data: chunk2,
                ),
              ],
            ),
          ),
        ],
      );

      final LlmAudioUserSimulator simulator = LlmAudioUserSimulator(
        config: LlmAudioUserSimulatorConfig(
          audioModel: 'gemini-tts',
          includeTextWithAudio: true,
        ),
        textSimulator: _ScriptedUserSimulator(<NextUserMessage>[]),
        audioLlm: audioLlm,
      );

      final Content content = await simulator.toAudioContent('Hello there');
      expect(content.role, 'user');
      expect(content.parts, hasLength(2));
      expect(content.parts[0].text, 'Hello there');
      expect(content.parts[1].inlineData, isNotNull);
      expect(content.parts[1].inlineData!.mimeType, 'audio/pcm;rate=16000');
      expect(content.parts[1].inlineData!.data, hasLength(400 * 2));
    });

    test('getNextUserMessage decorates StaticUserSimulator, honors includeTextWithAudio=false, and passes through non-success/empty turns', () async {
      final Uint8List ttsPcm = _pcm(List<int>.generate(60, (int i) => i * 10));
      final _FakeStreamLlm audioLlm = _FakeStreamLlm(
        model: 'gemini-tts',
        responses: <LlmResponse>[
          LlmResponse(
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromInlineData(
                  mimeType: 'audio/pcm;rate=24000',
                  data: ttsPcm,
                ),
              ],
            ),
          ),
        ],
      );

      final StaticUserSimulator staticSim = StaticUserSimulator(
        staticConversation: <Invocation>[
          Invocation(
            userContent: <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': 'Book me a flight.'},
              ],
            },
          ),
          Invocation(
            userContent: <String, Object?>{
              'role': 'user',
              'parts': <Object?>[],
            },
          ),
        ],
      );

      final LlmAudioUserSimulator simulator = LlmAudioUserSimulator(
        config: LlmAudioUserSimulatorConfig(
          audioModel: 'gemini-tts',
          includeTextWithAudio: false,
        ),
        textSimulator: staticSim,
        audioLlm: audioLlm,
      );

      // Turn 1: audio-only part resampled 60 -> 40 samples.
      final NextUserMessage turn1 = await simulator.getNextUserMessage(<Event>[]);
      expect(turn1.status, Status.success);
      expect(turn1.userMessage!.parts, hasLength(1));
      expect(turn1.userMessage!.parts[0].inlineData!.mimeType, 'audio/pcm;rate=16000');
      expect(_samples(turn1.userMessage!.parts[0].inlineData!.data), hasLength(40));
      expect(audioLlm.capturedRequests, hasLength(1));

      // Turn 2: empty text passes through without calling audio model.
      final NextUserMessage turn2 = await simulator.getNextUserMessage(<Event>[]);
      expect(turn2.status, Status.success);
      expect(turn2.userMessage!.parts, isEmpty);
      expect(audioLlm.capturedRequests, hasLength(1));

      // Turn 3: StaticUserSimulator exhausted -> stopSignalDetected passthrough.
      final NextUserMessage turn3 = await simulator.getNextUserMessage(<Event>[]);
      expect(turn3.status, Status.stopSignalDetected);
      expect(audioLlm.capturedRequests, hasLength(1));
    });

    test('toAudioContent throws StateError on model error response or empty audio output', () async {
      final _FakeStreamLlm errorLlm = _FakeStreamLlm(
        model: 'gemini-tts',
        responses: <LlmResponse>[
          LlmResponse(errorCode: 'SAFETY', errorMessage: 'blocked'),
        ],
      );
      final LlmAudioUserSimulator errorSim = LlmAudioUserSimulator(
        config: LlmAudioUserSimulatorConfig(audioModel: 'gemini-tts'),
        textSimulator: _ScriptedUserSimulator(<NextUserMessage>[]),
        audioLlm: errorLlm,
      );
      await expectLater(
        errorSim.toAudioContent('hello'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Audio generation failed: SAFETY'),
          ),
        ),
      );

      final _FakeStreamLlm emptyLlm = _FakeStreamLlm(
        model: 'gemini-tts',
        responses: <LlmResponse>[
          LlmResponse(content: Content.modelText('not audio')),
        ],
      );
      final LlmAudioUserSimulator emptySim = LlmAudioUserSimulator(
        config: LlmAudioUserSimulatorConfig(audioModel: 'gemini-tts'),
        textSimulator: _ScriptedUserSimulator(<NextUserMessage>[]),
        audioLlm: emptyLlm,
      );
      await expectLater(
        emptySim.toAudioContent('hello'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Audio model returned no audio data'),
          ),
        ),
      );
    });
  });
}
