import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/adk.dart';
import 'package:test/test.dart';

class _CapturedSink {
  _CapturedSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

class _SequencedGeminiModel extends BaseLlm {
  _SequencedGeminiModel({required super.model, required this.replies});

  final List<String> replies;
  int _callCount = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String reply = replies[_callCount % replies.length];
    _callCount += 1;
    yield LlmResponse(content: Content.modelText(reply));
  }
}

EvalCaseResult _runResult({
  String evalSetId = 'eval-set',
  String evalId = 'flaky-case',
  required int repetitionIndex,
  required double score,
  double threshold = 0.8,
  required EvalStatus evalStatus,
}) {
  return EvalCaseResult(
    evalSetId: evalSetId,
    evalId: evalId,
    finalEvalStatus: evalStatus,
    overallEvalMetricResults: <EvalMetricResultSpec>[
      EvalMetricResultSpec(
        metricName: 'response_match_score',
        score: score,
        threshold: threshold,
        evalStatus: evalStatus,
      ),
    ],
    sessionId: 'session-$repetitionIndex',
    repetitionIndex: repetitionIndex,
  );
}

void main() {
  group('Upstream 287c0b0e6 — prettyPrintMultiRunSummaryTable & adk eval CLI', () {
    test('prettyPrintMultiRunSummaryTable renders Status, Runs strip, Pass Rate, criteria, and per-run scores', () {
      final List<EvalCaseResult> runs = <EvalCaseResult>[
        _runResult(
          repetitionIndex: 0,
          score: 1.0,
          evalStatus: EvalStatus.passed,
        ),
        _runResult(
          repetitionIndex: 1,
          score: 0.6,
          evalStatus: EvalStatus.failed,
        ),
      ];
      final MultiRunCaseResult verdict = MultiRunCaseResult(
        evalSetId: 'eval-set',
        evalId: 'flaky-case',
        finalEvalStatus: EvalStatus.failed,
        overallEvalMetricResults: <EvalMetricResultSpec>[
          EvalMetricResultSpec(
            metricName: 'response_match_score',
            score: 0.8,
            threshold: 0.8,
            evalStatus: EvalStatus.passed,
          ),
        ],
        runs: runs,
        crossRunResults: const <MethodResult>[
          MethodResult(
            name: 'pass_rate',
            value: 0.5,
            threshold: 0.8,
            status: EvalStatus.failed,
            note: '1 of 2 runs passed',
          ),
        ],
      );

      final String out = prettyPrintMultiRunSummaryTable(
        <MultiRunCaseResult>[verdict],
      );

      expect(
        out,
        '\n'
        '  flaky-case  FAILED  PF  1/2 (50%)  pass_rate=0.50 (FAILED)\n'
        '    response_match_score: 0.80 (threshold 0.80, PASSED, runs: [1.00, 0.60])\n',
      );
    });

    test('prettyPrintMultiRunSummaryTable uses decided runs denominator to match passRate', () {
      final EvalCaseResult crashedRun = EvalCaseResult(
        evalSetId: 'eval-set',
        evalId: 'crashed-case',
        finalEvalStatus: EvalStatus.failed,
        overallEvalMetricResults: const <EvalMetricResultSpec>[],
        evalMetricResultPerInvocation: const <EvalMetricResultPerInvocation>[],
        sessionId: 'session-3',
        repetitionIndex: 3,
      );
      final List<EvalCaseResult> runs = <EvalCaseResult>[
        _runResult(
          evalId: 'crashed-case',
          repetitionIndex: 0,
          score: 1.0,
          evalStatus: EvalStatus.passed,
        ),
        _runResult(
          evalId: 'crashed-case',
          repetitionIndex: 1,
          score: 0.9,
          evalStatus: EvalStatus.passed,
        ),
        _runResult(
          evalId: 'crashed-case',
          repetitionIndex: 2,
          score: 0.5,
          evalStatus: EvalStatus.failed,
        ),
        crashedRun,
      ];
      final MultiRunCaseResult verdict = MultiRunCaseResult(
        evalSetId: 'eval-set',
        evalId: 'crashed-case',
        finalEvalStatus: EvalStatus.passed,
        overallEvalMetricResults: <EvalMetricResultSpec>[
          EvalMetricResultSpec(
            metricName: 'response_match_score',
            score: 0.8,
            threshold: 0.8,
            evalStatus: EvalStatus.passed,
          ),
        ],
        runs: runs,
        maxCrashedRuns: 1,
      );

      final String out = prettyPrintMultiRunSummaryTable(
        <MultiRunCaseResult>[verdict],
      );

      expect(
        out,
        '\n'
        '  crashed-case  PASSED  PPFC  2/3 (67%)\n'
        '    response_match_score: 0.80 (threshold 0.80, PASSED, runs: [1.00, 0.90, 0.50, -])\n',
      );
    });

    test('adk eval --num_runs prints default multi-run Pass Rate summary and persists multi_run_case_summaries', () async {
      LLMRegistry.clear();
      final _SequencedGeminiModel sequencedModel = _SequencedGeminiModel(
        model: 'gemini-2.5-flash',
        replies: <String>['expected reply', 'completely wrong'],
      );
      LLMRegistry.register(
        supportedModels: <RegExp>[RegExp(r'gemini-2\.5-flash')],
        factory: (String _) => sequencedModel,
      );
      addTearDown(LLMRegistry.clear);

      final Directory parentDir = await Directory.systemTemp.createTemp(
        'adk_cli_multi_run_eval_',
      );
      addTearDown(() async {
        if (await parentDir.exists()) {
          await parentDir.delete(recursive: true);
        }
      });
      final Directory agentDir = Directory(
        '${parentDir.path}${Platform.pathSeparator}demo_agent',
      );
      await createDevProject(
        projectDirPath: agentDir.path,
        appName: 'demo_agent',
      );

      final File evalSetFile = File(
        '${agentDir.path}${Platform.pathSeparator}smoke_set.evalset.json',
      );
      await evalSetFile.writeAsString('''
{
  "eval_set_id": "smoke_set",
  "eval_cases": [
    {
      "eval_id": "case1",
      "input": "hello",
      "expected_output": "expected reply"
    }
  ]
}
''');

      final File configFile = File(
        '${parentDir.path}${Platform.pathSeparator}eval_config.json',
      );
      await configFile.writeAsString('''
{
  "criteria": {
    "final_response_exact_match": 0.5
  },
  "parallelism": 1
}
''');

      final _CapturedSink outCapture = _CapturedSink();
      final _CapturedSink errCapture = _CapturedSink();
      final int exitCode = await runAdkCli(
        <String>[
          'eval',
          '--num_runs',
          '2',
          '--config_file_path',
          configFile.path,
          agentDir.path,
          'smoke_set',
        ],
        outSink: outCapture.sink,
        errSink: errCapture.sink,
      );
      final String stdoutText = await outCapture.closeAndRead();
      final String stderrText = await errCapture.closeAndRead();

      expect(
        exitCode,
        0,
        reason: 'STDOUT:\n$stdoutText\nSTDERR:\n$stderrText',
      );
      expect(stdoutText, contains('Tests passed: 1'));
      expect(stdoutText, contains('Tests failed: 0'));
      expect(stdoutText, contains('case1  PASSED  PF  1/2 (50%)'));
      expect(
        stdoutText,
        contains(
          'finalResponseExactMatch: 0.50 (threshold 0.50, PASSED, runs: [1.00, 0.00])',
        ),
      );

      final LocalEvalSetResultsManager resultsManager =
          LocalEvalSetResultsManager(parentDir.path);
      final List<String> resultIds = await resultsManager.listEvalSetResults(
        'demo_agent',
      );
      expect(resultIds, hasLength(1));

      final EvalSetResult persisted = await resultsManager.getEvalSetResult(
        'demo_agent',
        resultIds.single,
      );
      expect(persisted.multiRunCaseSummaries, isNotNull);
      expect(persisted.multiRunCaseSummaries, hasLength(1));
      expect(persisted.multiRunCaseSummaries!.single.evalId, 'case1');
      expect(persisted.multiRunCaseSummaries!.single.numRuns, 2);
      expect(persisted.multiRunCaseSummaries!.single.passedRuns, 1);
      expect(persisted.multiRunCaseSummaries!.single.failedRuns, 1);
      expect(persisted.multiRunCaseSummaries!.single.passRate, 0.5);
    });
  });

  group('Upstream 12aab4aaa — only create agents file watcher when agent reload is enabled', () {
    late Directory tempAgentsDir;
    late List<AgentsFileObserver> createdObservers;

    setUp(() async {
      tempAgentsDir = await Directory.systemTemp.createTemp(
        'adk_watcher_parity_',
      );
      createdObservers = <AgentsFileObserver>[];
      agentsFileObserverFactoryTestingOverride = () {
        final AgentsFileObserver obs = AgentsFileObserver();
        createdObservers.add(obs);
        return obs;
      };
    });

    tearDown(() async {
      agentsFileObserverFactoryTestingOverride = null;
      if (await tempAgentsDir.exists()) {
        await tempAgentsDir.delete(recursive: true);
      }
    });

    test('no file observer is created without reloadAgents', () async {
      final FastApiApp app = getFastApiApp(
        agentsDir: tempAgentsDir.path,
        reloadAgents: false,
      );
      await app.stop();

      expect(createdObservers, isEmpty);
    });

    test('file observer is started and stopped when reloadAgents is true', () async {
      final FastApiApp app = getFastApiApp(
        agentsDir: tempAgentsDir.path,
        reloadAgents: true,
      );

      expect(createdObservers, hasLength(1));
      final AgentsFileObserver observer = createdObservers.single;
      expect(observer.startCallCount, 1);
      expect(observer.stopCallCount, 0);
      expect(observer.isRunning, isTrue);

      await app.stop();

      expect(observer.stopCallCount, 1);
      expect(observer.joinCallCount, 1);
      expect(observer.isStopped, isTrue);
      expect(observer.isJoined, isTrue);
    });

    test('ApiServer skips tearDownObserver when setupObserver is null', () async {
      int tearDownCalls = 0;
      final ApiServer apiServer = ApiServer(agentsDir: tempAgentsDir.path);

      final FastApiApp app = apiServer.getFastApiApp(
        tearDownObserver: (AgentsFileObserver obs, AdkWebServer srv) {
          tearDownCalls += 1;
        },
      );
      await app.stop();

      expect(createdObservers, isEmpty);
      expect(tearDownCalls, 0);
    });

    test('ApiServer allows setupObserver without tearDownObserver', () async {
      final List<(AgentsFileObserver, AdkWebServer)> setupCalls =
          <(AgentsFileObserver, AdkWebServer)>[];
      final ApiServer apiServer = ApiServer(agentsDir: tempAgentsDir.path);

      final FastApiApp app = apiServer.getFastApiApp(
        setupObserver: (AgentsFileObserver obs, AdkWebServer srv) {
          setupCalls.add((obs, srv));
        },
      );
      await app.stop();

      expect(createdObservers, hasLength(1));
      expect(setupCalls, hasLength(1));
      expect(setupCalls.single.$1, same(createdObservers.single));
      expect(setupCalls.single.$2, same(apiServer));
    });
  });
}
