/// Local in-memory implementation of [BaseEvalService].
library;

import 'dart:async';

import '../agents/base_agent.dart';
import '../agents/live_request_queue.dart';
import '../agents/run_config.dart';
import '../events/event.dart';
import '../runners/runner.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import '../utils/client_labels_utils.dart';
import 'base_eval_service.dart';
import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metric.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'eval_sets_manager.dart';
import 'evaluator.dart';
import 'metric_evaluator_registry.dart';

/// Local evaluation service that runs eval cases with an in-memory runner.
class LocalEvalService extends BaseEvalService {
  /// Creates a local eval service bound to [rootAgent].
  LocalEvalService({
    required BaseAgent rootAgent,
    String appName = 'eval_app',
    EvalSetsManager? evalSetsManager,
    MetricEvaluatorRegistry? metricEvaluatorRegistry,
  }) : _runner = InMemoryRunner(agent: rootAgent, appName: appName),
       _evalSetsManager = evalSetsManager,
       _metricEvaluatorRegistry =
           metricEvaluatorRegistry ?? defaultMetricEvaluatorRegistry;

  final InMemoryRunner _runner;
  final EvalSetsManager? _evalSetsManager;
  final MetricEvaluatorRegistry _metricEvaluatorRegistry;

  @override
  Stream<InferenceResult> performInference(InferenceRequest request) async* {
    final int numRuns = request.inferenceConfig.numRuns;
    final int effectiveParallelism =
        request.inferenceConfig.parallelism < 1
            ? 1
            : request.inferenceConfig.parallelism;

    Future<InferenceResult> runOne(EvalCase evalCase, int rep) async {
      final int? repetitionIndex = numRuns > 1 ? rep : null;
      final Session session = await _runner.sessionService.createSession(
        appName: _runner.appName,
        userId: request.userId,
      );

      try {
        final List<Event> events = request.inferenceConfig.useLive
            ? await _runLiveInference(
                request: request,
                session: session,
                evalCase: evalCase,
              )
            : await _runner
                  .runAsync(
                    userId: request.userId,
                    sessionId: session.id,
                    newMessage: Content.userText(evalCase.input),
                  )
                  .toList();
        final String response = _finalAgentText(events);
        return InferenceResult(
          appName: request.appName,
          evalCaseId: evalCase.evalId,
          userInput: evalCase.input,
          responseText: response,
          sessionId: session.id,
          status: InferenceStatus.success,
          repetitionIndex: repetitionIndex,
        );
      } catch (error) {
        return InferenceResult(
          appName: request.appName,
          evalCaseId: evalCase.evalId,
          userInput: evalCase.input,
          sessionId: session.id,
          status: InferenceStatus.failure,
          errorMessage: '$error',
          repetitionIndex: repetitionIndex,
        );
      }
    }

    final List<(EvalCase, int)> tasks = <(EvalCase, int)>[
      for (final EvalCase evalCase in request.evalCases)
        for (int rep = 0; rep < numRuns; rep += 1) (evalCase, rep),
    ];

    if (effectiveParallelism <= 1 || tasks.length <= 1) {
      for (final (EvalCase evalCase, int rep) in tasks) {
        yield await runOne(evalCase, rep);
      }
      return;
    }

    final List<InferenceResult?> results = List<InferenceResult?>.filled(
      tasks.length,
      null,
    );
    int nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final int current = nextIndex;
        if (current >= tasks.length) {
          return;
        }
        nextIndex += 1;
        final (EvalCase evalCase, int rep) = tasks[current];
        results[current] = await runOne(evalCase, rep);
      }
    }

    final int workerCount =
        effectiveParallelism < tasks.length ? effectiveParallelism : tasks.length;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    for (final InferenceResult? result in results) {
      if (result != null) {
        yield result;
      }
    }
  }

  @override
  Stream<EvalCaseResult> evaluate(EvaluateRequest request) async* {
    final int parallelism = request.evaluateConfig.parallelism;
    if (parallelism < 1) {
      throw ArgumentError(
        '`parallelism` must be at least 1, got $parallelism.',
      );
    }

    final List<InferenceResult> items = request.inferenceResults;
    if (items.isEmpty) {
      return;
    }

    if (parallelism == 1 || items.length == 1) {
      for (final InferenceResult inference in items) {
        yield await _evaluateSingleInferenceResult(
          inference: inference,
          request: request,
        );
      }
      return;
    }

    final List<EvalCaseResult?> results = List<EvalCaseResult?>.filled(
      items.length,
      null,
    );
    int nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final int current = nextIndex;
        if (current >= items.length) {
          return;
        }
        nextIndex += 1;
        results[current] = await _evaluateSingleInferenceResult(
          inference: items[current],
          request: request,
        );
      }
    }

    final int workerCount =
        parallelism < items.length ? parallelism : items.length;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    for (final EvalCaseResult? result in results) {
      if (result != null) {
        yield result;
      }
    }
  }

  Future<EvalCaseResult> _evaluateSingleInferenceResult({
    required InferenceResult inference,
    required EvaluateRequest request,
  }) async {
    EvalCase? evalCase = request.evalCasesById[inference.evalCaseId];
    if (evalCase == null &&
        _evalSetsManager != null &&
        inference.evalSetId.isNotEmpty) {
      evalCase = await _evalSetsManager.getEvalCase(
        inference.appName,
        inference.evalSetId,
        inference.evalCaseId,
      );
    }

    final String expected = evalCase?.expectedOutput ?? '';
    final String actual = inference.responseText ?? '';
    final String expectedNormalized = expected.trim().toLowerCase();
    final String actualNormalized = actual.trim().toLowerCase();

    final List<EvalMetricResult> metrics = <EvalMetricResult>[];
    for (final EvalMetric metric in request.evaluateConfig.evalMetrics) {
      switch (metric) {
        case EvalMetric.finalResponseExactMatch:
          final bool match =
              expectedNormalized.isNotEmpty &&
              actualNormalized == expectedNormalized;
          metrics.add(
            EvalMetricResult(
              metric: metric,
              score: match ? 1 : 0,
              passed: match,
              detail: 'Exact match against expected output.',
            ),
          );
          break;
        case EvalMetric.finalResponseContains:
          final bool contains =
              expectedNormalized.isNotEmpty &&
              actualNormalized.contains(expectedNormalized);
          metrics.add(
            EvalMetricResult(
              metric: metric,
              score: contains ? 1 : 0,
              passed: contains,
              detail: 'Response contains expected output.',
            ),
          );
          break;
      }
    }

    final List<EvalMetricResultSpec> overallEvalMetricResults =
        <EvalMetricResultSpec>[];
    if (request.evaluateConfig.evalMetricSpecs.isNotEmpty) {
      final List<Invocation> actualInvocations =
          inference.inferences ??
          <Invocation>[
            Invocation(
              userContent: <String, Object?>{
                'role': 'user',
                'parts': <Object?>[
                  <String, Object?>{'text': inference.userInput},
                ],
              },
              finalResponse: inference.responseText == null
                  ? null
                  : <String, Object?>{
                      'role': 'model',
                      'parts': <Object?>[
                        <String, Object?>{'text': inference.responseText},
                      ],
                    },
            ),
          ];
      final List<Invocation>? expectedInvocations = evalCase?.conversation;

      for (final EvalMetricSpec spec
          in request.evaluateConfig.evalMetricSpecs) {
        EvaluationResult evaluationResult;
        try {
          evaluationResult = await _runWithEvalClientLabel(
            () => _evaluateMetric(
              evalMetric: spec,
              actualInvocations: actualInvocations,
              expectedInvocations: expectedInvocations,
              conversationScenario: evalCase?.conversationScenario,
            ),
          );
        } catch (_) {
          evaluationResult = EvaluationResult(
            overallEvalStatus: EvalStatus.notEvaluated,
          );
        }

        final double? score = evaluationResult.overallScore;
        final double threshold =
            spec.threshold ?? spec.criterion?.threshold ?? 0.0;
        final EvalStatus evalStatus =
            evaluationResult.overallEvalStatus != EvalStatus.notEvaluated
            ? evaluationResult.overallEvalStatus
            : (score != null
                  ? (score >= threshold
                        ? EvalStatus.passed
                        : EvalStatus.failed)
                  : EvalStatus.notEvaluated);
        overallEvalMetricResults.add(
          EvalMetricResultSpec(
            metricName: spec.metricName,
            threshold: spec.threshold,
            criterion: spec.criterion,
            customFunctionPath: spec.customFunctionPath,
            score: score,
            evalStatus: evalStatus,
          ),
        );
        metrics.add(
          EvalMetricResult(
            metric: EvalMetric.finalResponseExactMatch,
            metricNameOverride: spec.metricName,
            score: score ?? 0.0,
            threshold: spec.threshold,
            evalStatus: evalStatus,
            passed: evalStatus == EvalStatus.passed,
          ),
        );
      }
    }

    EvalStatus? finalStatus;
    if (overallEvalMetricResults.isNotEmpty) {
      finalStatus = EvalStatus.notEvaluated;
      for (final EvalMetricResultSpec result in overallEvalMetricResults) {
        if (result.evalStatus == EvalStatus.passed) {
          finalStatus = EvalStatus.passed;
        } else if (result.evalStatus == EvalStatus.notEvaluated ||
            result.evalStatus == EvalStatus.informational) {
          continue;
        } else {
          finalStatus = EvalStatus.failed;
          break;
        }
      }
    }

    return EvalCaseResult(
      evalSetId: inference.evalSetId,
      evalCaseId: inference.evalCaseId,
      metrics: metrics,
      overallEvalMetricResults: overallEvalMetricResults.isEmpty
          ? null
          : overallEvalMetricResults,
      finalEvalStatus: finalStatus ?? EvalStatus.notEvaluated,
      sessionId: inference.sessionId ?? '',
      repetitionIndex: inference.repetitionIndex,
    );
  }

  Future<EvaluationResult> _runWithEvalClientLabel(
    Future<EvaluationResult> Function() action,
  ) {
    if (getClientLabels().contains(evalClientLabel)) {
      return action();
    }
    return clientLabelContext(evalClientLabel, action);
  }

  Future<EvaluationResult> _evaluateMetric({
    required EvalMetricSpec evalMetric,
    required List<Invocation> actualInvocations,
    required List<Invocation>? expectedInvocations,
    required ConversationScenario? conversationScenario,
  }) async {
    final Evaluator metricEvaluator = _metricEvaluatorRegistry.getEvaluator(
      evalMetric,
    );
    return Future<EvaluationResult>(() async {
      final FutureOr<EvaluationResult> result = metricEvaluator
          .evaluateInvocations(
            actualInvocations: actualInvocations,
            expectedInvocations: expectedInvocations,
            conversationScenario: conversationScenario,
          );
      return await result;
    });
  }

  Future<List<Event>> _runLiveInference({
    required InferenceRequest request,
    required Session session,
    required EvalCase evalCase,
  }) async {
    final LiveRequestQueue liveRequestQueue = LiveRequestQueue();
    scheduleMicrotask(() {
      liveRequestQueue.sendContent(Content.userText(evalCase.input));
    });

    final List<Event> events = <Event>[];
    final Stream<Event> stream = _runner
        .runLive(
          liveRequestQueue: liveRequestQueue,
          session: session,
          runConfig: RunConfig(
            streamingMode: StreamingMode.bidi,
            responseModalities: <String>['AUDIO'],
            outputAudioTranscription: <String, Object?>{},
            inputAudioTranscription: <String, Object?>{},
          ),
        )
        .timeout(
          Duration(seconds: request.inferenceConfig.liveTimeoutSeconds),
          onTimeout: (EventSink<Event> sink) {
            liveRequestQueue.close();
            sink.close();
          },
        );

    try {
      await for (final Event event in stream) {
        events.add(event);
        if (event.turnComplete == true && event.author != 'user') {
          liveRequestQueue.close();
          break;
        }
      }
    } finally {
      liveRequestQueue.close();
    }
    return events;
  }

  String _finalAgentText(List<Event> events) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      final content = event.content;
      if (content == null) {
        continue;
      }
      final List<String> chunks = <String>[];
      for (final part in content.parts) {
        final text = part.text;
        if (text != null && text.trim().isNotEmpty) {
          chunks.add(text.trim());
        }
      }
      if (chunks.isNotEmpty) {
        return chunks.join('\n');
      }
    }
    return '';
  }
}
