import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('EvalConfig parity', () {
    test('returns default criteria when file does not exist', () {
      final EvalConfig config = getEvaluationCriteriaOrDefault(null);
      expect(config.criteria['tool_trajectory_avg_score'], 1.0);
      expect(config.criteria['response_match_score'], 0.8);
    });

    test('loads config from json file', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'adk_eval_config_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final File file = File('${dir.path}/eval_config.json');
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'criteria': <String, Object?>{
            'custom_metric': 0.6,
            'other_metric': <String, Object?>{'threshold': 0.9},
          },
          'custom_metrics': <String, Object?>{
            'custom_metric': <String, Object?>{
              'code_config': <String, Object?>{'name': 'pkg.metrics.fn'},
            },
          },
        }),
      );

      final EvalConfig config = getEvaluationCriteriaOrDefault(file.path);
      final List<EvalMetricSpec> metrics = getEvalMetricsFromConfig(config);
      expect(metrics, hasLength(2));
      final EvalMetricSpec custom = metrics.firstWhere(
        (EvalMetricSpec value) => value.metricName == 'custom_metric',
      );
      expect(custom.threshold, 0.6);
      expect(custom.customFunctionPath, 'pkg.metrics.fn');
    });

    test('custom metric config rejects CodeConfig args', () {
      expect(
        () => CustomMetricConfig(
          codeConfig: CodeConfig(name: 'm.fn', args: <Object?>['a']),
        ),
        throwsArgumentError,
      );
    });
  });
}
