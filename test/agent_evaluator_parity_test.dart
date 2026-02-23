import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EchoAgent extends BaseAgent {
  _EchoAgent() : super(name: 'echo_agent');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String input =
        context.userContent?.parts
            .map((Part p) => p.text ?? '')
            .where((String t) => t.isNotEmpty)
            .join(' ') ??
        '';
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('Echo: $input'),
    );
  }
}

class _RootAgent extends BaseAgent {
  _RootAgent({List<BaseAgent>? subAgents})
    : super(name: 'root_agent', subAgents: subAgents);

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('Root fallback'),
    );
  }
}

class _BinaryJudgeEvaluator extends LlmAsJudge {
  _BinaryJudgeEvaluator({
    required EvalMetricSpec evalMetric,
    required AutoRaterInvoker autoRaterInvoker,
  }) : super(
         evalMetric: evalMetric,
         expectedInvocationsRequired: true,
         autoRaterInvoker: autoRaterInvoker,
       );

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    return getTextFromContent(actualInvocation.finalResponse) ?? '';
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String text =
        autoRaterResponse.content?.parts
            .map((Part p) => p.text ?? '')
            .join(' ') ??
        '';
    return AutoRaterScore(score: text.contains('valid') ? 1.0 : 0.0);
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    final double total = perInvocationSamples.fold<double>(
      0,
      (double acc, PerInvocationResult value) => acc + (value.score ?? 0.0),
    );
    final double mean = total / perInvocationSamples.length;
    final PerInvocationResult first = perInvocationSamples.first;
    return PerInvocationResult(
      actualInvocation: first.actualInvocation,
      expectedInvocation: first.expectedInvocation,
      score: mean >= 0.5 ? 1.0 : 0.0,
      evalStatus: mean >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
    );
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final double total = perInvocationResults.fold<double>(
      0,
      (double acc, PerInvocationResult value) => acc + (value.score ?? 0.0),
    );
    final double score = total / perInvocationResults.length;
    return EvaluationResult(
      overallScore: score,
      overallEvalStatus: score >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
      perInvocationResults: perInvocationResults,
    );
  }
}

EvalSet _singleTurnEvalSet() {
  return EvalSet(
    evalSetId: 'set1',
    evalCases: <EvalCase>[
      EvalCase(evalId: 'case1', input: 'hello', expectedOutput: 'Echo: hello'),
    ],
  );
}

void main() {
  group('evaluation generator', () {
    test('generates invocation responses from eval set', () async {
      final List<EvalCaseResponses> responses =
          await EvaluationGenerator.generateResponses(
            evalSet: _singleTurnEvalSet(),
            rootAgent: _EchoAgent(),
            repeatNum: 1,
          );

      expect(responses, hasLength(1));
      expect(responses.first.responses, hasLength(1));
      final List<Invocation> run = responses.first.responses.first;
      expect(run, isNotEmpty);
      final String? responseText = getTextFromContent(run.first.finalResponse);
      expect(responseText, contains('Echo: hello'));
    });
  });

  group('agent evaluator', () {
    test('evaluates metric scores across generated runs', () async {
      final List<AgentEvalCaseSummary> summary =
          await AgentEvaluator.evaluateEvalSet(
            rootAgent: _EchoAgent(),
            evalSet: _singleTurnEvalSet(),
            evalConfig: EvalConfig(
              criteria: <String, Object?>{
                PrebuiltMetricNames.responseMatchScore: 0.9,
              },
            ),
            repeatNum: 1,
          );

      expect(summary, hasLength(1));
      expect(summary.first.metrics, isNotEmpty);
      expect(
        summary.first.metrics.first.metricName,
        PrebuiltMetricNames.responseMatchScore,
      );
      expect(summary.first.passed, isTrue);
    });
  });

  group('llm as judge base', () {
    test('runs multi-sample auto-rater path and aggregates results', () async {
      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.finalResponseMatchV2,
        criterion: LlmAsAJudgeCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(numSamples: 2),
        ),
      );

      final _BinaryJudgeEvaluator evaluator = _BinaryJudgeEvaluator(
        evalMetric: metric,
        autoRaterInvoker:
            ({
              required String prompt,
              required JudgeModelOptions judgeModelOptions,
            }) async {
              return LlmResponse(
                content: Content.modelText(
                  '{"is_the_agent_response_valid":"valid"}',
                ),
              );
            },
      );

      final Invocation invocation = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'hello'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'Echo: hello'},
          ],
        },
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[invocation],
        expectedInvocations: <Invocation>[invocation],
      );
      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
    });
  });

  group('agent evaluator legacy dataset parity', () {
    test('migrates old eval data into EvalSet schema json', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'agent_eval_migrate_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final File legacyFile = File('${tempDir.path}/legacy.test.json')
        ..writeAsStringSync(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{'query': 'hello', 'reference': 'Echo: hello'},
          ]),
        );
      File('${tempDir.path}/test_config.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'criteria': <String, Object?>{
            PrebuiltMetricNames.responseMatchScore: 0.8,
          },
        }),
      );

      final String migratedPath = '${tempDir.path}/migrated.evalset.json';
      AgentEvaluator.migrateEvalDataToNewSchema(
        oldEvalDataFile: legacyFile.path,
        newEvalDataFile: migratedPath,
      );

      final Map<String, Object?> decoded = _asJsonMap(
        jsonDecode(File(migratedPath).readAsStringSync()) as Map,
      );
      final EvalSet evalSet = EvalSet.fromJson(decoded);
      expect(evalSet.evalCases, hasLength(1));
      expect(evalSet.evalCases.first.input, 'hello');
      expect(evalSet.evalCases.first.conversation, isNotNull);
    });

    test(
      'evaluate discovers .test.json files in directory and runs eval',
      () async {
        final Directory tempDir = Directory.systemTemp.createTempSync(
          'agent_eval_directory_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        File('${tempDir.path}/case_a.test.json').writeAsStringSync(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{'query': 'hello', 'reference': 'Echo: hello'},
          ]),
        );
        File('${tempDir.path}/test_config.json').writeAsStringSync(
          jsonEncode(<String, Object?>{
            'criteria': <String, Object?>{
              PrebuiltMetricNames.responseMatchScore: 0.8,
            },
          }),
        );

        final List<AgentEvalCaseSummary> summaries =
            await AgentEvaluator.evaluate(
              rootAgent: _EchoAgent(),
              evalDatasetFilePathOrDir: tempDir.path,
              repeatNum: 1,
              failOnFailure: true,
            );

        expect(summaries, hasLength(1));
        expect(summaries.first.passed, isTrue);
      },
    );

    test('loadEvalSetFromFile validates criteria keys for legacy format', () {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'agent_eval_validate_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final File legacyFile = File('${tempDir.path}/invalid.test.json')
        ..writeAsStringSync(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{'query': 'hello', 'reference': 'Echo: hello'},
          ]),
        );
      final EvalConfig invalidConfig = EvalConfig(
        criteria: <String, Object?>{'unknown_metric': 1.0},
      );

      expect(
        () => AgentEvaluator.loadEvalSetFromFile(
          evalSetFile: legacyFile.path,
          evalConfig: invalidConfig,
        ),
        throwsArgumentError,
      );
    });
  });

  group('agent evaluator module resolution parity', () {
    setUp(() {
      AgentEvaluator.clearAgentModules();
      AgentEvaluator.clearAgentModuleLoader();
    });

    tearDown(() {
      AgentEvaluator.clearAgentModules();
      AgentEvaluator.clearAgentModuleLoader();
    });

    test('evaluate resolves root agent from registered module name', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'agent_eval_module_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      File('${tempDir.path}/case_a.test.json').writeAsStringSync(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{'query': 'hello', 'reference': 'Echo: hello'},
        ]),
      );
      File('${tempDir.path}/test_config.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'criteria': <String, Object?>{
            PrebuiltMetricNames.responseMatchScore: 0.8,
          },
        }),
      );

      AgentEvaluator.registerAgentModule(
        'sample.agent',
        () => _RootAgent(subAgents: <BaseAgent>[_EchoAgent()]),
      );

      final List<AgentEvalCaseSummary> summaries =
          await AgentEvaluator.evaluate(
            agentModule: 'sample.agent',
            agentName: 'echo_agent',
            evalDatasetFilePathOrDir: tempDir.path,
            repeatNum: 1,
          );

      expect(summaries, hasLength(1));
      expect(summaries.first.passed, isTrue);
    });

    test('evaluateEvalSet uses injected module loader when provided', () async {
      final List<AgentEvalCaseSummary> summary =
          await AgentEvaluator.evaluateEvalSet(
            agentModule: 'dynamic.module',
            evalSet: _singleTurnEvalSet(),
            evalConfig: EvalConfig(
              criteria: <String, Object?>{
                PrebuiltMetricNames.responseMatchScore: 0.9,
              },
            ),
            repeatNum: 1,
            agentModuleLoader: (String moduleName) async {
              expect(moduleName, 'dynamic.module');
              return _EchoAgent();
            },
          );

      expect(summary, hasLength(1));
      expect(summary.first.passed, isTrue);
    });

    test('evaluate rejects unknown module when no loader is registered', () {
      expect(
        () => AgentEvaluator.evaluate(
          agentModule: 'missing.module',
          evalDatasetFilePathOrDir: '/tmp/does-not-matter',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

Map<String, Object?> _asJsonMap(Map value) {
  return value.map(
    (Object? key, Object? item) =>
        MapEntry<String, Object?>(key.toString(), item),
  );
}
