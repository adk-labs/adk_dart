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
import 'base_eval_service.dart';
import 'eval_case.dart';
import 'eval_metric.dart';
import 'eval_result.dart';

/// Local evaluation service that runs eval cases with an in-memory runner.
class LocalEvalService extends BaseEvalService {
  /// Creates a local eval service bound to [rootAgent].
  LocalEvalService({required BaseAgent rootAgent, String appName = 'eval_app'})
    : _runner = InMemoryRunner(agent: rootAgent, appName: appName);

  final InMemoryRunner _runner;

  @override
  Stream<InferenceResult> performInference(InferenceRequest request) async* {
    for (final EvalCase evalCase in request.evalCases) {
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
        yield InferenceResult(
          appName: request.appName,
          evalCaseId: evalCase.evalId,
          userInput: evalCase.input,
          responseText: response,
          sessionId: session.id,
          status: InferenceStatus.success,
        );
      } catch (error) {
        yield InferenceResult(
          appName: request.appName,
          evalCaseId: evalCase.evalId,
          userInput: evalCase.input,
          sessionId: session.id,
          status: InferenceStatus.failure,
          errorMessage: '$error',
        );
      }
    }
  }

  @override
  Stream<EvalCaseResult> evaluate(EvaluateRequest request) async* {
    for (final InferenceResult inference in request.inferenceResults) {
      final EvalCase? evalCase = request.evalCasesById[inference.evalCaseId];
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

      yield EvalCaseResult(evalCaseId: inference.evalCaseId, metrics: metrics);
    }
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
