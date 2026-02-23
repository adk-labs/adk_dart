import 'dart:async';

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';

typedef CustomMetricFunction =
    FutureOr<EvaluationResult> Function(
      EvalMetricSpec evalMetric,
      List<Invocation> actualInvocations,
      List<Invocation>? expectedInvocations,
      ConversationScenario? conversationScenario,
    );

final Map<String, CustomMetricFunction> _customMetricRegistry =
    <String, CustomMetricFunction>{};

void registerCustomMetricFunction(String path, CustomMetricFunction function) {
  _customMetricRegistry[path] = function;
}

void unregisterCustomMetricFunction(String path) {
  _customMetricRegistry.remove(path);
}

CustomMetricFunction _getMetricFunction(String customFunctionPath) {
  final CustomMetricFunction? metricFunction =
      _customMetricRegistry[customFunctionPath];
  if (metricFunction == null) {
    throw ArgumentError(
      'Could not import custom metric function from $customFunctionPath',
    );
  }
  return metricFunction;
}

class CustomMetricEvaluator extends Evaluator {
  CustomMetricEvaluator({
    required EvalMetricSpec evalMetric,
    required String customFunctionPath,
  }) : _evalMetric = evalMetric,
       _metricFunction = _getMetricFunction(customFunctionPath);

  final EvalMetricSpec _evalMetric;
  final CustomMetricFunction _metricFunction;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    final EvalMetricSpec evalMetric = EvalMetricSpec(
      metricName: _evalMetric.metricName,
      threshold: null,
      criterion: _evalMetric.criterion,
      customFunctionPath: _evalMetric.customFunctionPath,
    );
    return await _metricFunction(
      evalMetric,
      actualInvocations,
      expectedInvocations,
      conversationScenario,
    );
  }
}
