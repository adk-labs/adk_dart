import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('EvalSetResultsManager', () {
    test('saves, lists, and loads eval set results', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_eval_results_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final LocalEvalSetResultsManager manager = LocalEvalSetResultsManager(
        dir.path,
      );

      final EvalCaseResult result = EvalCaseResult(
        evalCaseId: 'case1',
        metrics: <EvalMetricResult>[
          EvalMetricResult(
            metric: EvalMetric.finalResponseExactMatch,
            score: 1,
            passed: true,
          ),
        ],
      );

      await manager.saveEvalSetResult('app', 'set1', <EvalCaseResult>[result]);
      final List<String> ids = await manager.listEvalSetResults('app');
      expect(ids, hasLength(1));

      final EvalSetResult loaded = await manager.getEvalSetResult(
        'app',
        ids.first,
      );
      expect(loaded.evalSetId, 'set1');
      expect(loaded.evalCaseResults, hasLength(1));
      expect(loaded.evalCaseResults.first.evalCaseId, 'case1');
    });

    test('parses legacy double encoded json', () {
      final EvalSetResult value = EvalSetResult(
        evalSetResultId: 'id1',
        evalSetResultName: 'name1',
        evalSetId: 'set1',
        evalCaseResults: <EvalCaseResult>[],
        creationTimestamp: 1,
      );
      final String json = jsonEncode(value.toJson());
      final String wrapped = jsonEncode(json);
      final EvalSetResult parsed = parseEvalSetResultJson(wrapped);
      expect(parsed.evalSetResultId, 'id1');
      expect(parsed.evalSetResultName, 'name1');
    });
  });
}
