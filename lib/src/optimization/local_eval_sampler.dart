/// Local eval-set-backed sampler used by prompt optimizers.
library;

import '../agents/llm_agent.dart';
import '../evaluation/eval_case.dart';
import '../evaluation/eval_config.dart';
import '../evaluation/eval_metrics.dart';
import '../evaluation/eval_result.dart';
import '../evaluation/eval_set.dart';
import '../evaluation/eval_sets_manager.dart';
import '../evaluation/evaluation_generator.dart';
import '../evaluation/evaluator.dart';
import '../evaluation/metric_evaluator_registry.dart';
import '../evaluation/simulation/user_simulator_provider.dart';
import 'data_types.dart';
import 'sampler.dart';

/// Configuration for [LocalEvalSampler].
class LocalEvalSamplerConfig {
  /// Creates a local eval sampler configuration.
  LocalEvalSamplerConfig({
    required this.evalConfig,
    required this.appName,
    required this.trainEvalSet,
    List<String>? trainEvalCaseIds,
    this.validationEvalSet,
    List<String>? validationEvalCaseIds,
  }) : trainEvalCaseIds = trainEvalCaseIds == null
           ? null
           : List<String>.unmodifiable(trainEvalCaseIds),
       validationEvalCaseIds = validationEvalCaseIds == null
           ? null
           : List<String>.unmodifiable(validationEvalCaseIds);

  /// Evaluation config applied while scoring candidate agents.
  final EvalConfig evalConfig;

  /// App name used to load eval sets.
  final String appName;

  /// Eval set id used for training.
  final String trainEvalSet;

  /// Optional eval case subset for training.
  final List<String>? trainEvalCaseIds;

  /// Optional eval set id used for validation.
  final String? validationEvalSet;

  /// Optional eval case subset for validation.
  final List<String>? validationEvalCaseIds;

  /// Parses one config payload from JSON.
  factory LocalEvalSamplerConfig.fromJson(Map<String, Object?> json) {
    return LocalEvalSamplerConfig(
      evalConfig: EvalConfig.fromJson(
        _asObjectMap(json['evalConfig'] ?? json['eval_config']),
      ),
      appName:
          (json['appName'] ?? json['app_name'] ?? '').toString().trim(),
      trainEvalSet:
          (json['trainEvalSet'] ?? json['train_eval_set'] ?? '')
              .toString()
              .trim(),
      trainEvalCaseIds: _asStringList(
        json['trainEvalCaseIds'] ?? json['train_eval_case_ids'],
      ),
      validationEvalSet: _emptyToNull(
        '${json['validationEvalSet'] ?? json['validation_eval_set'] ?? ''}',
      ),
      validationEvalCaseIds: _asStringList(
        json['validationEvalCaseIds'] ?? json['validation_eval_case_ids'],
      ),
    );
  }

  /// Serializes this config to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eval_config': evalConfig.toJson(),
      'app_name': appName,
      'train_eval_set': trainEvalSet,
      if (trainEvalCaseIds != null) 'train_eval_case_ids': trainEvalCaseIds,
      if (validationEvalSet != null) 'validation_eval_set': validationEvalSet,
      if (validationEvalCaseIds != null)
        'validation_eval_case_ids': validationEvalCaseIds,
    };
  }
}

/// Eval-set backed sampler that scores agents using local evaluation flows.
class LocalEvalSampler extends Sampler<UnstructuredSamplingResult> {
  /// Loads train/validation eval sets from [evalSetsManager].
  static Future<LocalEvalSampler> create({
    required LocalEvalSamplerConfig config,
    required EvalSetsManager evalSetsManager,
    MetricEvaluatorRegistry? metricRegistry,
  }) async {
    final EvalSet trainEvalSet =
        await evalSetsManager.getEvalSet(config.appName, config.trainEvalSet) ??
        (throw StateError(
          'Eval set `${config.trainEvalSet}` does not exist for app '
          '`${config.appName}`.',
        ));
    final String validationEvalSetId =
        config.validationEvalSet ?? config.trainEvalSet;
    final EvalSet validationEvalSet = validationEvalSetId == config.trainEvalSet
        ? trainEvalSet
        : await evalSetsManager.getEvalSet(config.appName, validationEvalSetId) ??
              (throw StateError(
                'Eval set `$validationEvalSetId` does not exist for app '
                '`${config.appName}`.',
              ));

    return LocalEvalSampler._(
      config: config,
      trainEvalSet: trainEvalSet,
      validationEvalSet: validationEvalSet,
      metricRegistry: metricRegistry,
    );
  }

  LocalEvalSampler._({
    required LocalEvalSamplerConfig config,
    required EvalSet trainEvalSet,
    required EvalSet validationEvalSet,
    MetricEvaluatorRegistry? metricRegistry,
  }) : _config = config,
       _trainEvalSet = trainEvalSet,
       _validationEvalSet = validationEvalSet,
       _metricRegistry = metricRegistry ?? defaultMetricEvaluatorRegistry,
       _evalMetrics = getEvalMetricsFromConfig(config.evalConfig),
       _trainEvalCaseIds = _resolveEvalCaseIds(
         trainEvalSet,
         config.trainEvalCaseIds,
         label: 'train_eval_case_ids',
       ),
       _validationEvalCaseIds = _resolveEvalCaseIds(
         validationEvalSet,
         config.validationEvalCaseIds,
         label: 'validation_eval_case_ids',
       );

  final LocalEvalSamplerConfig _config;
  final EvalSet _trainEvalSet;
  final EvalSet _validationEvalSet;
  final MetricEvaluatorRegistry _metricRegistry;
  final List<EvalMetricSpec> _evalMetrics;
  final List<String> _trainEvalCaseIds;
  final List<String> _validationEvalCaseIds;

  @override
  List<String> getTrainExampleIds() => List<String>.from(_trainEvalCaseIds);

  @override
  List<String> getValidationExampleIds() =>
      List<String>.from(_validationEvalCaseIds);

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final EvalSet sourceEvalSet = exampleSet == ExampleSet.train
        ? _trainEvalSet
        : _validationEvalSet;
    final List<String> selectedIds = batch == null
        ? (exampleSet == ExampleSet.train
              ? _trainEvalCaseIds
              : _validationEvalCaseIds)
        : List<String>.from(batch);

    final List<EvalCase> selectedCases = _selectEvalCases(
      sourceEvalSet,
      selectedIds,
    );
    final EvalSet workingEvalSet = EvalSet(
      evalSetId: sourceEvalSet.evalSetId,
      name: sourceEvalSet.name,
      description: sourceEvalSet.description,
      creationTimestamp: sourceEvalSet.creationTimestamp,
      evalCases: selectedCases,
    );

    final UserSimulatorProvider userSimulatorProvider = UserSimulatorProvider(
      userSimulatorConfig: _config.evalConfig.userSimulatorConfig,
    );
    final List<EvalCaseResponses> generated =
        await EvaluationGenerator.generateResponses(
          evalSet: workingEvalSet,
          rootAgent: candidate,
          repeatNum: 1,
          appName: _config.appName,
          userSimulatorProvider: userSimulatorProvider,
        );

    final Map<String, double> scores = <String, double>{};
    final Map<String, Map<String, Object?>>? evalData = captureFullEvalData
        ? <String, Map<String, Object?>>{}
        : null;

    for (final EvalCaseResponses evalCaseResponses in generated) {
      final EvalCase evalCase = evalCaseResponses.evalCase;
      final List<Invocation> expectedInvocations = _resolveExpectedInvocations(
        evalCase,
      );
      final List<Invocation> actualInvocations = evalCaseResponses.responses
          .isEmpty
          ? <Invocation>[]
          : evalCaseResponses.responses.first;
      final Map<int, List<Map<String, Object?>>> perInvocationMetricResults =
          <int, List<Map<String, Object?>>>{};
      bool passed = true;

      for (final EvalMetricSpec metric in _evalMetrics) {
        final Evaluator evaluator = _metricRegistry.getEvaluator(metric);
        final EvaluationResult evaluationResult = await evaluator
            .evaluateInvocations(
              actualInvocations: actualInvocations,
              expectedInvocations: expectedInvocations.isEmpty
                  ? null
                  : expectedInvocations,
              conversationScenario: evalCase.conversationScenario,
            );
        if (evaluationResult.overallEvalStatus != EvalStatus.passed) {
          passed = false;
        }
        for (int i = 0; i < evaluationResult.perInvocationResults.length; i += 1) {
          final PerInvocationResult perInvocation =
              evaluationResult.perInvocationResults[i];
          perInvocationMetricResults
              .putIfAbsent(i, () => <Map<String, Object?>>[])
              .add(<String, Object?>{
                'metric_name': metric.metricName,
                if (perInvocation.score != null)
                  'score': double.parse(
                    perInvocation.score!.toStringAsFixed(2),
                  ),
                'eval_status': perInvocation.evalStatus.name,
              });
        }
      }

      scores[evalCase.evalId] = passed ? 1.0 : 0.0;
      if (evalData != null) {
        evalData[evalCase.evalId] = _buildEvalData(
          evalCase: evalCase,
          actualInvocations: actualInvocations,
          expectedInvocations: expectedInvocations,
          perInvocationMetricResults: perInvocationMetricResults,
        );
      }
    }

    return UnstructuredSamplingResult(scores: scores, data: evalData);
  }
}

List<String> _resolveEvalCaseIds(
  EvalSet evalSet,
  List<String>? configuredIds, {
  required String label,
}) {
  final List<String> availableIds = evalSet.evalCases
      .map((EvalCase evalCase) => evalCase.evalId)
      .toList(growable: false);
  if (configuredIds == null || configuredIds.isEmpty) {
    return availableIds;
  }
  final Set<String> available = availableIds.toSet();
  final List<String> missing = configuredIds
      .where((String id) => !available.contains(id))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw StateError(
      '$label references unknown eval case ids: ${missing.join(', ')}.',
    );
  }
  return List<String>.from(configuredIds);
}

List<EvalCase> _selectEvalCases(EvalSet evalSet, List<String> selectedIds) {
  final Map<String, EvalCase> casesById = <String, EvalCase>{
    for (final EvalCase evalCase in evalSet.evalCases) evalCase.evalId: evalCase,
  };
  final List<String> missing = selectedIds
      .where((String id) => !casesById.containsKey(id))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw StateError(
      'Unknown eval case ids requested from `${evalSet.evalSetId}`: '
      '${missing.join(', ')}.',
    );
  }
  return selectedIds
      .map((String id) => casesById[id]!)
      .toList(growable: false);
}

List<Invocation> _resolveExpectedInvocations(EvalCase evalCase) {
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

Map<String, Object?> _buildEvalData({
  required EvalCase evalCase,
  required List<Invocation> actualInvocations,
  required List<Invocation> expectedInvocations,
  required Map<int, List<Map<String, Object?>>> perInvocationMetricResults,
}) {
  final Map<String, Object?> data = <String, Object?>{};
  if (evalCase.conversationScenario != null) {
    data['conversation_scenario'] = Map<String, Object?>.from(
      evalCase.conversationScenario!.toJson(),
    );
  }

  final List<Map<String, Object?>> invocations = <Map<String, Object?>>[];
  for (int i = 0; i < actualInvocations.length; i += 1) {
    final Invocation actual = actualInvocations[i];
    final Invocation? expected = i < expectedInvocations.length
        ? expectedInvocations[i]
        : null;
    invocations.add(<String, Object?>{
      'actual_invocation': _extractInvocationInfo(actual),
      if (expected != null) 'expected_invocation': _extractInvocationInfo(expected),
      'eval_metric_results': perInvocationMetricResults[i] ?? <Map<String, Object?>>[],
    });
  }
  data['invocations'] = invocations;
  return data;
}

Map<String, Object?> _extractInvocationInfo(Invocation invocation) {
  return <String, Object?>{
    'user_prompt': _contentText(invocation.userContent),
    'agent_response': _contentText(invocation.finalResponse),
    if (invocation.intermediateData != null)
      'tool_calls': getAllToolCallsWithResponses(invocation.intermediateData)
          .map(((EvalJsonMap, EvalJsonMap?) item) {
            final EvalJsonMap call = item.$1;
            final EvalJsonMap? response = item.$2;
            return <String, Object?>{
              'name': '${call['name'] ?? ''}',
              'args': _asObjectMap(call['args']),
              'response': response == null ? null : _asObjectMap(response['response']),
            };
          })
          .toList(growable: false),
  };
}

String _contentText(Map<String, Object?>? content) {
  if (content == null) {
    return '';
  }
  final Object? rawParts = content['parts'];
  if (rawParts is! List) {
    return '';
  }
  return rawParts
      .whereType<Map>()
      .map((Map<Object?, Object?> part) => '${part['text'] ?? ''}'.trim())
      .where((String text) => text.isNotEmpty)
      .join();
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<String>? _asStringList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<String> result = value
      .map((Object? item) => '$item'.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
  return result.isEmpty ? null : result;
}

String? _emptyToNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
