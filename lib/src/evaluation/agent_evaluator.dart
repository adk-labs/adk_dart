import 'dart:io';

import '../agents/base_agent.dart';
import 'eval_case.dart';
import 'eval_config.dart';
import 'eval_metrics.dart';
import 'eval_set.dart';
import 'evaluation_generator.dart';
import 'metric_evaluator_registry.dart';

class AgentMetricAggregate {
  AgentMetricAggregate({
    required this.metricName,
    required this.threshold,
    required this.averageScore,
    required this.passed,
  });

  final String metricName;
  final double threshold;
  final double averageScore;
  final bool passed;
}

class AgentEvalCaseSummary {
  AgentEvalCaseSummary({
    required this.evalCaseId,
    required this.metrics,
    required this.passed,
  });

  final String evalCaseId;
  final List<AgentMetricAggregate> metrics;
  final bool passed;
}

class AgentEvaluator {
  static const int numRuns = 2;

  static EvalConfig findConfigForTestFile(String testFile) {
    final File file = File(testFile);
    final String testFolder = file.parent.path;
    final String configPath = '$testFolder/test_config.json';
    return getEvaluationCriteriaOrDefault(configPath);
  }

  static Future<List<AgentEvalCaseSummary>> evaluateEvalSet({
    required BaseAgent rootAgent,
    required EvalSet evalSet,
    EvalConfig? evalConfig,
    int repeatNum = numRuns,
    MetricEvaluatorRegistry? metricRegistry,
  }) async {
    final EvalConfig effectiveConfig =
        evalConfig ?? getEvaluationCriteriaOrDefault(null);
    final List<EvalMetricSpec> evalMetrics = getEvalMetricsFromConfig(
      effectiveConfig,
    );
    final MetricEvaluatorRegistry registry =
        metricRegistry ?? defaultMetricEvaluatorRegistry;

    final List<EvalCaseResponses> generated =
        await EvaluationGenerator.generateResponses(
          evalSet: evalSet,
          rootAgent: rootAgent,
          repeatNum: repeatNum,
        );

    final List<AgentEvalCaseSummary> summaries = <AgentEvalCaseSummary>[];
    for (final EvalCaseResponses evalCaseResponses in generated) {
      final EvalCase evalCase = evalCaseResponses.evalCase;
      final List<Invocation> expectedInvocations = _resolveExpectedInvocations(
        evalCase,
      );
      final List<AgentMetricAggregate> metricSummaries =
          <AgentMetricAggregate>[];

      for (final EvalMetricSpec metric in evalMetrics) {
        final evaluator = registry.getEvaluator(metric);
        final List<double> runScores = <double>[];
        for (final List<Invocation> runInvocations
            in evalCaseResponses.responses) {
          final evaluationResult = await evaluator.evaluateInvocations(
            actualInvocations: runInvocations,
            expectedInvocations: expectedInvocations.isEmpty
                ? null
                : expectedInvocations,
            conversationScenario: evalCase.conversationScenario,
          );
          if (evaluationResult.overallScore != null) {
            runScores.add(evaluationResult.overallScore!);
          }
        }
        final double average = runScores.isEmpty
            ? 0.0
            : runScores.reduce((double a, double b) => a + b) /
                  runScores.length;
        final double threshold =
            metric.threshold ?? metric.criterion?.threshold ?? 0.0;
        metricSummaries.add(
          AgentMetricAggregate(
            metricName: metric.metricName,
            threshold: threshold,
            averageScore: average,
            passed: average >= threshold,
          ),
        );
      }

      summaries.add(
        AgentEvalCaseSummary(
          evalCaseId: evalCase.evalId,
          metrics: metricSummaries,
          passed: metricSummaries.every(
            (AgentMetricAggregate metric) => metric.passed,
          ),
        ),
      );
    }
    return summaries;
  }

  static List<Invocation> _resolveExpectedInvocations(EvalCase evalCase) {
    if (evalCase.conversation != null && evalCase.conversation!.isNotEmpty) {
      return evalCase.conversation!;
    }
    if (evalCase.expectedOutput != null || evalCase.input.isNotEmpty) {
      return <Invocation>[
        Invocation(
          userContent: <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': evalCase.input},
            ],
          },
          finalResponse: <String, Object?>{
            'role': 'model',
            'parts': <Object?>[
              <String, Object?>{'text': evalCase.expectedOutput ?? ''},
            ],
          },
        ),
      ];
    }
    return <Invocation>[];
  }
}
