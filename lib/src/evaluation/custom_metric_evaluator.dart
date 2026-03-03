/// Custom metric evaluator registration and execution helpers.
library;

import 'dart:async';

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';

/// Signature for externally registered custom metric evaluators.
typedef CustomMetricFunction =
    FutureOr<EvaluationResult> Function(
      EvalMetricSpec evalMetric,
      List<Invocation> actualInvocations,
      List<Invocation>? expectedInvocations,
      ConversationScenario? conversationScenario,
    );

final Map<String, CustomMetricFunction> _customMetricRegistry =
    <String, CustomMetricFunction>{};

/// Registers a custom metric function at [path].
void registerCustomMetricFunction(String path, CustomMetricFunction function) {
  _customMetricRegistry[path] = function;
}

/// Removes a previously registered custom metric function at [path].
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

/// Evaluator that delegates scoring to a registered custom metric function.
class CustomMetricEvaluator extends Evaluator {
  /// Creates a custom metric evaluator from [evalMetric] and function path.
  CustomMetricEvaluator({
    required EvalMetricSpec evalMetric,
    required String customFunctionPath,
  }) : _evalMetric = evalMetric,
       _metricFunction = _getMetricFunction(customFunctionPath);

  final EvalMetricSpec _evalMetric;
  final CustomMetricFunction _metricFunction;

  @override
  /// Evaluates invocations using the custom metric callback.
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
