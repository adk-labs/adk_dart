/// Shared rubric-based evaluator contracts and orchestration helpers.
library;

import 'dart:developer' as developer;

import '../models/llm_response.dart';
import '../types/content.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_rubrics.dart';
import 'evaluator.dart';
import 'llm_as_judge.dart';
import 'llm_as_judge_utils.dart';

/// Parsed rubric evaluation response item.
class RubricResponse {
  /// Creates a rubric response item.
  RubricResponse({
    this.rubricId,
    this.propertyText,
    this.rationale,
    this.score,
  });

  /// Optional rubric ID referenced by the model output.
  final String? rubricId;

  /// Rubric property text referenced by the model output.
  final String? propertyText;

  /// Model rationale for the verdict.
  final String? rationale;

  /// Parsed numeric score.
  final double? score;
}

/// Parser interface for converting auto-rater text into rubric responses.
abstract class AutoRaterResponseParser {
  /// Parses [autoRaterResponse] into structured rubric responses.
  List<RubricResponse> parse(String autoRaterResponse);
}

/// Default parser for `Property/Rationale/Verdict` auto-rater output.
class DefaultAutoRaterResponseParser implements AutoRaterResponseParser {
  static final RegExp _idPattern = RegExp(
    r'^\s*ID:\s*(.*)$',
    multiLine: true,
  );
  static final RegExp _propertyPattern = RegExp(
    r'^\s*Property:\s*(.*)$',
    multiLine: true,
  );
  static final RegExp _rationalePattern = RegExp(
    r'^\s*Rationale:\s*(.*)$',
    multiLine: true,
  );
  static final RegExp _verdictPattern = RegExp(
    r'^\s*Verdict:\s*(.*)$',
    multiLine: true,
  );

  @override
  List<RubricResponse> parse(String autoRaterResponse) {
    final List<RegExpMatch> propertyMatches = _propertyPattern
        .allMatches(autoRaterResponse)
        .toList();
    final List<RegExpMatch> idMatches = _idPattern
        .allMatches(autoRaterResponse)
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

    if (!(propertyMatches.length == rationales.length &&
        rationales.length == scores.length)) {
      return <RubricResponse>[];
    }

    final List<RubricResponse> responses = <RubricResponse>[];
    for (int i = 0; i < propertyMatches.length; i += 1) {
      final RegExpMatch propertyMatch = propertyMatches[i];
      final int previousStart = i > 0 ? propertyMatches[i - 1].start : -1;
      String? rubricId;
      for (final RegExpMatch idMatch in idMatches) {
        if (previousStart < idMatch.start &&
            idMatch.start < propertyMatch.start) {
          final String candidate = (idMatch.group(1) ?? '').trim();
          rubricId = candidate.isEmpty ? null : candidate;
        }
      }
      responses.add(
        RubricResponse(
          rubricId: rubricId,
          propertyText: (propertyMatch.group(1) ?? '').trim(),
          rationale: rationales[i],
          score: scores[i],
        ),
      );
    }
    return responses;
  }
}

/// Aggregator interface for multiple per-invocation samples.
abstract class PerInvocationResultsAggregator {
  /// Aggregates [perInvocationSamples] using [threshold].
  PerInvocationResult aggregate(
    List<PerInvocationResult> perInvocationSamples,
    double threshold,
  );
}

/// Majority-vote aggregator for per-invocation rubric scores.
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

/// Summarizer interface for invocation-level results.
abstract class InvocationResultsSummarizer {
  /// Summarizes [perInvocationResults] using [threshold].
  EvaluationResult summarize(
    List<PerInvocationResult> perInvocationResults,
    double threshold,
  );
}

/// Mean-based summarizer for invocation-level rubric results.
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

final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _leadingTrailingDecorationPattern = RegExp(
  r'''^[ *_`#>\-\u2022"']+|[ *_`#>\-\u2022"']+$''',
);

String _normalizeText(Object? text) {
  if (text is! String) {
    return '';
  }
  final String replaced = text
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-');
  final String collapsed = replaced.replaceAll(_whitespacePattern, ' ');
  return collapsed
      .replaceAll(_leadingTrailingDecorationPattern, '')
      .toLowerCase();
}

/// Base evaluator for rubric-driven LLM-as-a-judge metrics.
abstract class RubricBasedEvaluator extends LlmAsJudge {
  /// Creates a rubric-based evaluator.
  RubricBasedEvaluator({
    required EvalMetricSpec evalMetric,
    AutoRaterResponseParser? autoRaterResponseParser,
    PerInvocationResultsAggregator? perInvocationResultsAggregator,
    InvocationResultsSummarizer? invocationResultsSummarizer,
    this.rubricType,
    super.autoRaterInvoker,
  }) : _autoRaterResponseParser =
           autoRaterResponseParser ?? DefaultAutoRaterResponseParser(),
       _perInvocationResultsAggregator =
           perInvocationResultsAggregator ??
           MajorityVotePerInvocationResultsAggregator(),
       _invocationResultsSummarizer =
           invocationResultsSummarizer ?? MeanInvocationResultsSummarizer(),
       _evalMetric = evalMetric,
       super(evalMetric: evalMetric, expectedInvocationsRequired: false) {
    if (evalMetric.criterion == null) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric expects a criterion of type '
        '`$RubricsBasedCriterion`.',
      );
    }
    _criterion = evalMetric.criterion is RubricsBasedCriterion
        ? evalMetric.criterion! as RubricsBasedCriterion
        : RubricsBasedCriterion.fromJson(evalMetric.criterion!.toJson());
    _rubrics = _criterion.rubrics;
  }

  /// Optional rubric type filter.
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

  /// Creates the effective rubric set for an invocation.
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
    if (_effectiveRubricsList!.isEmpty) {
      throw ArgumentError('Rubrics are required.');
    }
  }

  /// Returns the effective rubric set for scoring.
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
  AutoRaterScore convertAutoRaterResponseToScoreForInvocation(
    LlmResponse autoRaterResponse, {
    required Invocation actual,
    required Invocation? expected,
  }) {
    createEffectiveRubricsList(actual.rubrics);
    return super.convertAutoRaterResponseToScoreForInvocation(
      autoRaterResponse,
      actual: actual,
      expected: expected,
    );
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
    final List<RubricResponse> rubricResponses;
    if (responseText.trim().isEmpty) {
      developer.log(
        'Auto-rater returned an empty response; no rubric verdicts could be parsed and this sample will not be scored.',
        name: 'adk_dart.evaluation',
      );
      rubricResponses = <RubricResponse>[];
    } else {
      rubricResponses = _autoRaterResponseParser.parse(responseText);
      if (rubricResponses.isEmpty) {
        developer.log(
          'Auto-rater response did not match the expected Property/Rationale/Verdict format; no rubric verdicts were parsed. Raw auto-rater response: $responseText',
          name: 'adk_dart.evaluation',
        );
      }
    }
    final List<RubricScore> rubricScores = <RubricScore>[];

    final List<Rubric> effectiveRubrics = getEffectiveRubricsList();
    final Map<String, Rubric> normalizedRubrics = <String, Rubric>{};
    final Map<String, Rubric> rubricById = <String, Rubric>{};
    for (final Rubric rubric in effectiveRubrics) {
      normalizedRubrics[_normalizeText(rubric.rubricContent.textProperty)] =
          rubric;
      rubricById[rubric.rubricId] = rubric;
    }

    for (final RubricResponse rubricResponse in rubricResponses) {
      Rubric? rubric;
      if (rubricResponse.rubricId != null &&
          rubricResponse.rubricId!.isNotEmpty) {
        rubric = rubricById[rubricResponse.rubricId!];
      }
      rubric ??= normalizedRubrics[_normalizeText(rubricResponse.propertyText)];
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

    final Set<String> answeredRubricIds = <String>{
      for (final RubricScore s in rubricScores)
        if (s.score != null) s.rubricId,
    };
    final List<String> missingRubricIds = <String>[
      for (final Rubric r in effectiveRubrics)
        if (!answeredRubricIds.contains(r.rubricId)) r.rubricId,
    ];
    if (rubricResponses.isNotEmpty && missingRubricIds.isNotEmpty) {
      developer.log(
        'Auto-rater response has no verdict for rubric(s) $missingRubricIds; this sample will not be scored.',
        name: 'adk_dart.evaluation',
      );
      return AutoRaterScore(rubricScores: <RubricScore>[]);
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
