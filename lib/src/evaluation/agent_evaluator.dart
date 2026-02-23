import 'dart:convert';
import 'dart:io';

import '../agents/base_agent.dart';
import 'eval_case.dart';
import 'eval_config.dart';
import 'eval_metrics.dart';
import 'eval_set.dart';
import 'evaluation_generator.dart';
import 'local_eval_sets_manager.dart' as local_eval_sets_manager;
import 'metric_evaluator_registry.dart';
import 'simulation/user_simulator_provider.dart';

const String _toolTrajectoryScoreKey =
    PrebuiltMetricNames.toolTrajectoryAvgScore;
const String _responseEvaluationScoreKey =
    PrebuiltMetricNames.responseEvaluationScore;
const String _responseMatchScoreKey = PrebuiltMetricNames.responseMatchScore;
const String _safetyV1Key = PrebuiltMetricNames.safetyV1;

const List<String> _allowedCriteria = <String>[
  _toolTrajectoryScoreKey,
  _responseEvaluationScoreKey,
  _responseMatchScoreKey,
  _safetyV1Key,
];

const String _queryColumn = 'query';
const String _referenceColumn = 'reference';
const String _expectedToolUseColumn = 'expected_tool_use';

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

  static Future<List<AgentEvalCaseSummary>> evaluate({
    required BaseAgent rootAgent,
    required String evalDatasetFilePathOrDir,
    int repeatNum = numRuns,
    String? initialSessionFile,
    bool failOnFailure = true,
    MetricEvaluatorRegistry? metricRegistry,
  }) async {
    final List<String> testFiles = _discoverTestFiles(evalDatasetFilePathOrDir);
    final Map<String, Object?> initialSession = _getInitialSession(
      initialSessionFile,
    );

    final List<AgentEvalCaseSummary> allSummaries = <AgentEvalCaseSummary>[];
    final List<String> failures = <String>[];

    for (final String testFile in testFiles) {
      final EvalConfig evalConfig = findConfigForTestFile(testFile);
      final EvalSet evalSet = loadEvalSetFromFile(
        evalSetFile: testFile,
        evalConfig: evalConfig,
        initialSession: initialSession,
      );

      final List<AgentEvalCaseSummary> summaries = await evaluateEvalSet(
        rootAgent: rootAgent,
        evalSet: evalSet,
        evalConfig: evalConfig,
        repeatNum: repeatNum,
        metricRegistry: metricRegistry,
      );
      allSummaries.addAll(summaries);

      if (failOnFailure) {
        for (final AgentEvalCaseSummary summary in summaries) {
          if (!summary.passed) {
            final String metricDump = summary.metrics
                .map((AgentMetricAggregate metric) {
                  return '${metric.metricName}(${metric.averageScore} < ${metric.threshold})';
                })
                .join(', ');
            failures.add(
              'Eval case `${summary.evalCaseId}` failed in `$testFile`: $metricDump',
            );
          }
        }
      }
    }

    if (failOnFailure && failures.isNotEmpty) {
      throw StateError(
        'Following are all the test failures.\n${failures.join('\n')}',
      );
    }

    return allSummaries;
  }

  static Future<List<AgentEvalCaseSummary>> evaluateEvalSet({
    required BaseAgent rootAgent,
    required EvalSet evalSet,
    Map<String, double>? criteria,
    EvalConfig? evalConfig,
    int repeatNum = numRuns,
    MetricEvaluatorRegistry? metricRegistry,
  }) async {
    final EvalConfig effectiveConfig;
    if (criteria != null && criteria.isNotEmpty) {
      effectiveConfig = EvalConfig(
        criteria: criteria.map(
          (String key, double value) => MapEntry(key, value),
        ),
      );
    } else {
      effectiveConfig = evalConfig ?? getEvaluationCriteriaOrDefault(null);
    }

    final List<EvalMetricSpec> evalMetrics = getEvalMetricsFromConfig(
      effectiveConfig,
    );
    final UserSimulatorProvider userSimulatorProvider = UserSimulatorProvider(
      userSimulatorConfig: effectiveConfig.userSimulatorConfig,
    );
    final MetricEvaluatorRegistry registry =
        metricRegistry ?? defaultMetricEvaluatorRegistry;

    final List<EvalCaseResponses> generated =
        await EvaluationGenerator.generateResponses(
          evalSet: evalSet,
          rootAgent: rootAgent,
          repeatNum: repeatNum,
          userSimulatorProvider: userSimulatorProvider,
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

  static void migrateEvalDataToNewSchema({
    required String oldEvalDataFile,
    required String newEvalDataFile,
    String? initialSessionFile,
  }) {
    if (oldEvalDataFile.isEmpty || newEvalDataFile.isEmpty) {
      throw ArgumentError(
        'One of oldEvalDataFile or newEvalDataFile is empty.',
      );
    }

    final EvalConfig evalConfig = findConfigForTestFile(oldEvalDataFile);
    final Map<String, Object?> initialSession = _getInitialSession(
      initialSessionFile,
    );
    final EvalSet evalSet = _getEvalSetFromOldFormat(
      evalSetFile: oldEvalDataFile,
      evalConfig: evalConfig,
      initialSession: initialSession,
    );

    final File target = File(newEvalDataFile);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(evalSet.toJson(includeNulls: false)),
    );
  }

  static EvalSet loadEvalSetFromFile({
    required String evalSetFile,
    required EvalConfig evalConfig,
    Map<String, Object?>? initialSession,
  }) {
    final Map<String, Object?> safeInitialSession =
        initialSession ?? <String, Object?>{};

    final File file = File(evalSetFile);
    if (!file.existsSync()) {
      throw ArgumentError('Eval set file `$evalSetFile` does not exist.');
    }

    final String content = file.readAsStringSync();
    final Object? decoded = jsonDecode(content);
    if (decoded is Map) {
      try {
        if (safeInitialSession.isNotEmpty) {
          throw ArgumentError(
            'Initial session should be specified as a part of EvalSet file.',
          );
        }
        return EvalSet.fromJson(_asJsonMap(decoded));
      } catch (_) {
        // Fall through to legacy parser path.
      }
    }

    return _getEvalSetFromOldFormat(
      evalSetFile: evalSetFile,
      evalConfig: evalConfig,
      initialSession: safeInitialSession,
    );
  }

  static EvalSet _getEvalSetFromOldFormat({
    required String evalSetFile,
    required EvalConfig evalConfig,
    required Map<String, Object?> initialSession,
  }) {
    final List<Map<String, Object?>> data = _loadDataset(evalSetFile).first;
    _validateInput(<List<Map<String, Object?>>>[data], evalConfig.criteria);

    final List<dynamic> legacyContainer = <dynamic>[
      <String, Object?>{
        'name': evalSetFile,
        'data': data,
        'initial_session': initialSession,
      },
    ];

    final String evalSetId =
        'evalset_${DateTime.now().microsecondsSinceEpoch.toString()}';
    return local_eval_sets_manager.convertEvalSetToModernSchema(
      evalSetId,
      legacyContainer,
    );
  }

  static List<List<Map<String, Object?>>> _loadDataset(String inputPath) {
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      inputPath,
    );
    if (entityType == FileSystemEntityType.notFound) {
      throw ArgumentError('Input path `$inputPath` is invalid.');
    }

    if (entityType == FileSystemEntityType.directory) {
      final List<List<Map<String, Object?>>> datasets =
          <List<Map<String, Object?>>>[];
      for (final String filePath in _discoverTestFiles(inputPath)) {
        datasets.add(_loadJsonFile(filePath));
      }
      return datasets;
    }

    return <List<Map<String, Object?>>>[_loadJsonFile(inputPath)];
  }

  static List<Map<String, Object?>> _loadJsonFile(String filePath) {
    final Object? decoded = jsonDecode(File(filePath).readAsStringSync());
    if (decoded is! List) {
      throw ArgumentError('$filePath must contain a list of dictionaries.');
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? row in decoded) {
      if (row is! Map) {
        throw ArgumentError('$filePath must contain a list of dictionaries.');
      }
      rows.add(_asJsonMap(row));
    }
    return rows;
  }

  static void _validateInput(
    List<List<Map<String, Object?>>> evalDataset,
    Map<String, Object?> criteria,
  ) {
    if (evalDataset.isEmpty || evalDataset.first.isEmpty) {
      throw ArgumentError('The evaluation dataset is empty.');
    }

    for (final String key in criteria.keys) {
      if (!_allowedCriteria.contains(key)) {
        throw ArgumentError(
          'Invalid criteria key: $key. Expected one of $_allowedCriteria.',
        );
      }
    }

    final List<Map<String, Object?>> sample = evalDataset.first;
    final Map<String, Object?> firstQuery = sample.first;

    if (criteria.containsKey(_toolTrajectoryScoreKey)) {
      if (!firstQuery.containsKey(_queryColumn) ||
          !firstQuery.containsKey(_expectedToolUseColumn)) {
        throw ArgumentError(
          'Samples for $_toolTrajectoryScoreKey must include `$_queryColumn` '
          'and `$_expectedToolUseColumn` keys.',
        );
      }
    }

    if (criteria.containsKey(_responseEvaluationScoreKey)) {
      if (!firstQuery.containsKey(_queryColumn)) {
        throw ArgumentError(
          'Samples for $_responseEvaluationScoreKey must include '
          '`$_queryColumn` key.',
        );
      }
    }

    if (criteria.containsKey(_responseMatchScoreKey)) {
      if (!firstQuery.containsKey(_queryColumn) ||
          !firstQuery.containsKey(_referenceColumn)) {
        throw ArgumentError(
          'Samples for $_responseMatchScoreKey must include `$_queryColumn` '
          'and `$_referenceColumn` keys.',
        );
      }
    }
  }

  static Map<String, Object?> _getInitialSession(String? initialSessionFile) {
    if (initialSessionFile == null || initialSessionFile.isEmpty) {
      return <String, Object?>{};
    }

    final File file = File(initialSessionFile);
    if (!file.existsSync()) {
      throw ArgumentError(
        'initialSessionFile `$initialSessionFile` does not exist.',
      );
    }

    final Object? decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw ArgumentError(
        'initialSessionFile `$initialSessionFile` must contain a JSON object.',
      );
    }
    return _asJsonMap(decoded);
  }

  static List<String> _discoverTestFiles(String evalDatasetFilePathOrDir) {
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      evalDatasetFilePathOrDir,
    );
    if (entityType == FileSystemEntityType.notFound) {
      throw ArgumentError('Input path `$evalDatasetFilePathOrDir` is invalid.');
    }

    if (entityType == FileSystemEntityType.directory) {
      final List<String> testFiles = <String>[];
      final Directory directory = Directory(evalDatasetFilePathOrDir);
      for (final FileSystemEntity entity in directory.listSync(
        recursive: true,
      )) {
        if (entity is File && entity.path.endsWith('.test.json')) {
          testFiles.add(entity.path);
        }
      }
      testFiles.sort();
      return testFiles;
    }

    return <String>[evalDatasetFilePathOrDir];
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

Map<String, Object?> _asJsonMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}
