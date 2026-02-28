import 'dart:developer' as developer;

import '../models/llm_response.dart';
import '../types/content.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_rubrics.dart';
import 'evaluator.dart';
import 'llm_as_judge.dart';
import 'llm_as_judge_utils.dart';

class RubricResponse {
  RubricResponse({this.propertyText, this.rationale, this.score});

  final String? propertyText;
  final String? rationale;
  final double? score;
}

abstract class AutoRaterResponseParser {
  List<RubricResponse> parse(String autoRaterResponse);
}

class DefaultAutoRaterResponseParser implements AutoRaterResponseParser {
  static final RegExp _propertyPattern = RegExp(
    r'^Property:\s*(.*)$',
    multiLine: true,
  );
  static final RegExp _rationalePattern = RegExp(
    r'^Rationale:\s*(.*)$',
    multiLine: true,
  );
  static final RegExp _verdictPattern = RegExp(
    r'^Verdict:\s*(.*)$',
    multiLine: true,
  );

  @override
  List<RubricResponse> parse(String autoRaterResponse) {
    final List<String> properties = _propertyPattern
        .allMatches(autoRaterResponse)
        .map((RegExpMatch match) => (match.group(1) ?? '').trim())
        .toList();
    final List<String> rationales = _rationalePattern
        .allMatches(autoRaterResponse)
        .map((RegExpMatch match) => (match.group(1) ?? '').trim())
        .toList();
    final List<double?> scores = _verdictPattern
        .allMatches(autoRaterResponse)
        .map((RegExpMatch match) {
          final String verdict = (match.group(1) ?? '').toLowerCase();
          if (verdict.contains('yes')) {
            return 1.0;
          }
          if (verdict.contains('no')) {
            return 0.0;
          }
          return null;
        })
        .toList();

    final int count = <int>[
      properties.length,
      rationales.length,
      scores.length,
    ].reduce((int a, int b) => a < b ? a : b);
    final List<RubricResponse> responses = <RubricResponse>[];
    for (int i = 0; i < count; i += 1) {
      responses.add(
        RubricResponse(
          propertyText: properties[i],
          rationale: rationales[i],
          score: scores[i],
        ),
      );
    }
    return responses;
  }
}

abstract class PerInvocationResultsAggregator {
  PerInvocationResult aggregate(
    List<PerInvocationResult> perInvocationSamples,
    double threshold,
  );
}

class MajorityVotePerInvocationResultsAggregator
    implements PerInvocationResultsAggregator {
  @override
  PerInvocationResult aggregate(
    List<PerInvocationResult> perInvocationSamples,
    double threshold,
  ) {
    final Map<String, _RubricScoreBuckets> scoreBucketsByRubricId =
        <String, _RubricScoreBuckets>{};

    for (final PerInvocationResult sample in perInvocationSamples) {
      final List<RubricScore>? rubricScores = sample.rubricScores;
      if (rubricScores == null) {
        continue;
      }
      for (final RubricScore rubricScore in rubricScores) {
        final _RubricScoreBuckets buckets = scoreBucketsByRubricId.putIfAbsent(
          rubricScore.rubricId,
          () => _RubricScoreBuckets(),
        );
        if (rubricScore.score == null) {
          buckets.noScores.add(rubricScore);
        } else if (rubricScore.score == 1.0) {
          buckets.positives.add(rubricScore);
        } else {
          buckets.negatives.add(rubricScore);
        }
      }
    }

    final List<RubricScore> aggregatedRubricScores = <RubricScore>[];
    for (final _RubricScoreBuckets buckets in scoreBucketsByRubricId.values) {
      if (buckets.positives.isEmpty && buckets.negatives.isEmpty) {
        if (buckets.noScores.isNotEmpty) {
          aggregatedRubricScores.add(buckets.noScores.first);
        }
      } else if (buckets.positives.length > buckets.negatives.length) {
        aggregatedRubricScores.add(buckets.positives.first);
      } else {
        aggregatedRubricScores.add(buckets.negatives.first);
      }
    }

    final double? aggregatedOverallScore = getAverageRubricScore(
      aggregatedRubricScores,
    );
    return PerInvocationResult(
      actualInvocation: perInvocationSamples.first.actualInvocation,
      expectedInvocation: perInvocationSamples.first.expectedInvocation,
      score: aggregatedOverallScore,
      rubricScores: aggregatedRubricScores,
      evalStatus: getEvalStatus(aggregatedOverallScore, threshold),
    );
  }
}

class _RubricScoreBuckets {
  final List<RubricScore> noScores = <RubricScore>[];
  final List<RubricScore> positives = <RubricScore>[];
  final List<RubricScore> negatives = <RubricScore>[];
}

abstract class InvocationResultsSummarizer {
  EvaluationResult summarize(
    List<PerInvocationResult> perInvocationResults,
    double threshold,
  );
}

class MeanInvocationResultsSummarizer implements InvocationResultsSummarizer {
  @override
  EvaluationResult summarize(
    List<PerInvocationResult> perInvocationResults,
    double threshold,
  ) {
    final List<RubricScore> unaggregatedRubricScores = <RubricScore>[];
    final Map<String, List<RubricScore>> rubricScoresById =
        <String, List<RubricScore>>{};

    for (final PerInvocationResult sample in perInvocationResults) {
      final List<RubricScore>? rubricScores = sample.rubricScores;
      if (rubricScores == null) {
        continue;
      }
      for (final RubricScore rubricScore in rubricScores) {
        rubricScoresById
            .putIfAbsent(rubricScore.rubricId, () => <RubricScore>[])
            .add(rubricScore);
        unaggregatedRubricScores.add(rubricScore);
      }
    }

    final List<RubricScore> aggregatedRubricScores = <RubricScore>[];
    rubricScoresById.forEach((String rubricId, List<RubricScore> values) {
      aggregatedRubricScores.add(
        RubricScore(
          rubricId: rubricId,
          score: getAverageRubricScore(values),
          rationale:
              'This is an aggregated score derived from individual entries. Please refer to individual entries in each invocation for actual rationale from the model.',
        ),
      );
    });

    final double? aggregatedOverallScore = getAverageRubricScore(
      unaggregatedRubricScores,
    );
    return EvaluationResult(
      overallScore: aggregatedOverallScore,
      overallEvalStatus: getEvalStatus(aggregatedOverallScore, threshold),
      perInvocationResults: perInvocationResults,
      overallRubricScores: aggregatedRubricScores,
    );
  }
}

String _normalizeText(String text) {
  return text.toLowerCase().trim();
}

abstract class RubricBasedEvaluator extends LlmAsJudge {
  RubricBasedEvaluator({
    required EvalMetricSpec evalMetric,
    AutoRaterResponseParser? autoRaterResponseParser,
    PerInvocationResultsAggregator? perInvocationResultsAggregator,
    InvocationResultsSummarizer? invocationResultsSummarizer,
    this.rubricType,
    AutoRaterInvoker? autoRaterInvoker,
  }) : _autoRaterResponseParser =
           autoRaterResponseParser ?? DefaultAutoRaterResponseParser(),
       _perInvocationResultsAggregator =
           perInvocationResultsAggregator ??
           MajorityVotePerInvocationResultsAggregator(),
       _invocationResultsSummarizer =
           invocationResultsSummarizer ?? MeanInvocationResultsSummarizer(),
       _evalMetric = evalMetric,
       super(
         evalMetric: evalMetric,
         expectedInvocationsRequired: false,
         autoRaterInvoker: autoRaterInvoker,
       ) {
    if (evalMetric.criterion == null) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric expects a criterion of type '
        '`$RubricsBasedCriterion`.',
      );
    }
    _criterion = evalMetric.criterion is RubricsBasedCriterion
        ? evalMetric.criterion! as RubricsBasedCriterion
        : RubricsBasedCriterion.fromJson(evalMetric.criterion!.toJson());
    if (_criterion.rubrics.isEmpty) {
      throw ArgumentError('Rubrics are required.');
    }
    _rubrics = _criterion.rubrics;
  }

  final String? rubricType;
  final AutoRaterResponseParser _autoRaterResponseParser;
  final PerInvocationResultsAggregator _perInvocationResultsAggregator;
  final InvocationResultsSummarizer _invocationResultsSummarizer;
  final EvalMetricSpec _evalMetric;

  late final RubricsBasedCriterion _criterion;
  late final List<Rubric> _rubrics;
  List<Rubric>? _effectiveRubricsList;

  @override
  Type get criterionType => RubricsBasedCriterion;

  void createEffectiveRubricsList(List<EvalJsonMap>? invocationRubrics) {
    final Map<String, Rubric> rubricsById = <String, Rubric>{};

    void addRubrics(List<Rubric> values, String scopeName) {
      for (final Rubric rubric in values) {
        if (rubricsById.containsKey(rubric.rubricId)) {
          throw ArgumentError(
            "Rubric with rubric_id '${rubric.rubricId}' already exists. Rubric defined in $scopeName conflicts with an existing rubric.",
          );
        }
        rubricsById[rubric.rubricId] = rubric;
      }
    }

    addRubrics(_rubrics, 'criterion');

    if (invocationRubrics != null && invocationRubrics.isNotEmpty) {
      List<Rubric> parsed = invocationRubrics
          .map((EvalJsonMap rubric) => Rubric.fromJson(rubric))
          .toList(growable: false);
      if (rubricType != null && rubricType!.isNotEmpty) {
        parsed = parsed
            .where((Rubric rubric) => rubric.type == rubricType)
            .toList(growable: false);
      }
      addRubrics(parsed, 'invocation');
    }

    _effectiveRubricsList = rubricsById.values.toList(growable: false);
  }

  List<Rubric> getEffectiveRubricsList() {
    final List<Rubric>? list = _effectiveRubricsList;
    if (list == null) {
      throw StateError(
        'Effective rubrics list not initialized. Call createEffectiveRubricsList() first.',
      );
    }
    return list;
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String responseText =
        autoRaterResponse.content?.parts
            .map((Part part) => part.text ?? '')
            .join('\n') ??
        '';
    final List<RubricResponse> rubricResponses = _autoRaterResponseParser.parse(
      responseText,
    );
    final List<RubricScore> rubricScores = <RubricScore>[];

    final Map<String, Rubric> normalizedRubrics = <String, Rubric>{
      for (final Rubric rubric in getEffectiveRubricsList())
        _normalizeText(rubric.rubricContent.textProperty ?? ''): rubric,
    };

    for (final RubricResponse rubricResponse in rubricResponses) {
      final String key = _normalizeText(rubricResponse.propertyText ?? '');
      final Rubric? rubric = normalizedRubrics[key];
      if (rubric == null) {
        developer.log(
          'Rubric ${rubricResponse.propertyText} not found in the rubrics provided to the metric.',
          name: 'adk_dart.evaluation',
        );
        continue;
      }
      rubricScores.add(
        RubricScore(
          rubricId: rubric.rubricId,
          rationale: rubricResponse.rationale,
          score: rubricResponse.score,
        ),
      );
    }

    return AutoRaterScore(
      score: getAverageRubricScore(rubricScores),
      rubricScores: rubricScores,
    );
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;
    return _perInvocationResultsAggregator.aggregate(
      perInvocationSamples,
      threshold,
    );
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;
    return _invocationResultsSummarizer.summarize(
      perInvocationResults,
      threshold,
    );
  }
}
