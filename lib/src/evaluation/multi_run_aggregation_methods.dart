/// Cross-run aggregation methods for multi-run evaluations.
library;

import 'dart:math' as math;

import 'eval_config.dart';
import 'eval_result.dart';

/// Per-run data for one metric (or the case overall), passed to aggregation methods.
class RunResult {
  /// Creates a per-run result summary for aggregation.
  RunResult({
    required this.status,
    this.score,
    List<double?>? invocationScores,
  }) : invocationScores = List<double?>.unmodifiable(
         invocationScores ?? const <double?>[],
       );

  /// Outcome of this run (`passed`, `failed`, or `notEvaluated`).
  final EvalStatus status;

  /// Run-level score for the metric (`null` when not evaluated or for case-level).
  final double? score;

  /// Per-invocation scores within this run (empty when not applicable).
  final List<double?> invocationScores;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! RunResult ||
        other.status != status ||
        other.score != score ||
        other.invocationScores.length != invocationScores.length) {
      return false;
    }
    for (int i = 0; i < invocationScores.length; i += 1) {
      if (other.invocationScores[i] != invocationScores[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(status, score, Object.hashAll(invocationScores));

  @override
  String toString() =>
      'RunResult(status: $status, score: $score, invocationScores: $invocationScores)';
}

/// Function signature for cross-run aggregation methods.
typedef AggregationMethodFn = double? Function(List<RunResult> runs);

/// Descriptor for a cross-run aggregation method.
class AggregationMethod {
  /// Creates an aggregation method descriptor.
  const AggregationMethod({
    required this.name,
    required this.compute,
    this.usesScores = true,
    this.custom = false,
  });

  /// Canonical method name (for example `'mean_over_invocations'` or `'pass_rate'`).
  final String name;

  /// Function that computes the aggregated value from per-run results.
  final AggregationMethodFn compute;

  /// `true` for score-combining methods (default), `false` for pass-count methods.
  ///
  /// Score-combining methods compare against the metric's own threshold;
  /// pass-count methods require an explicit threshold in [MultiRunCriterion] and
  /// can be used in `MultiRunConfig.crossRunCriteria`.
  final bool usesScores;

  /// `true` when loaded from `MultiRunConfig.customMethods`.
  final bool custom;
}

/// Mean over all per-invocation scores across all runs.
///
/// Falls back to [meanOfRuns] when no per-invocation scores are available.
double? meanOverInvocations(List<RunResult> runs) {
  final List<double> invScores = <double>[];
  for (final RunResult run in runs) {
    for (final double? score in run.invocationScores) {
      if (score != null && score.isFinite) {
        invScores.add(score);
      }
    }
  }
  if (invScores.isNotEmpty) {
    final double sum = invScores.fold<double>(
      0.0,
      (double acc, double v) => acc + v,
    );
    return sum / invScores.length;
  }
  return meanOfRuns(runs);
}

/// Arithmetic mean of run-level scores across runs that produced a score.
double? meanOfRuns(List<RunResult> runs) {
  final List<double> scores = <double>[
    for (final RunResult run in runs)
      if (run.score != null && run.score!.isFinite) run.score!,
  ];
  if (scores.isEmpty) {
    return null;
  }
  final double sum = scores.fold<double>(
    0.0,
    (double acc, double v) => acc + v,
  );
  return sum / scores.length;
}

/// Minimum run-level score across runs that produced a score.
double? minOverRuns(List<RunResult> runs) {
  final List<double> scores = <double>[
    for (final RunResult run in runs)
      if (run.score != null && run.score!.isFinite) run.score!,
  ];
  if (scores.isEmpty) {
    return null;
  }
  return scores.reduce(math.min);
}

/// Fraction of evaluated runs that passed (`passed / (passed + failed)`).
double? passRate(List<RunResult> runs) {
  int passed = 0;
  int failed = 0;
  for (final RunResult run in runs) {
    if (run.status == EvalStatus.passed) {
      passed += 1;
    } else if (run.status == EvalStatus.failed) {
      failed += 1;
    }
  }
  final int total = passed + failed;
  return total > 0 ? passed / total : null;
}

/// Default score-combining aggregation method (`mean_over_invocations`).
const AggregationMethod defaultAggregationMethod = AggregationMethod(
  name: 'mean_over_invocations',
  compute: meanOverInvocations,
  usesScores: true,
);

const Map<String, AggregationMethod> _builtInMethods =
    <String, AggregationMethod>{
      'mean_over_invocations': defaultAggregationMethod,
      'mean_of_runs': AggregationMethod(
        name: 'mean_of_runs',
        compute: meanOfRuns,
        usesScores: true,
      ),
      'min_over_runs': AggregationMethod(
        name: 'min_over_runs',
        compute: minOverRuns,
        usesScores: true,
      ),
      'pass_rate': AggregationMethod(
        name: 'pass_rate',
        compute: passRate,
        usesScores: false,
      ),
    };

/// Returns a copy of the built-in aggregation methods keyed by method name.
Map<String, AggregationMethod> getBuiltInAggregationMethods() {
  return Map<String, AggregationMethod>.from(_builtInMethods);
}

final Map<String, Object?> _customAggregationRegistry = <String, Object?>{};

/// Registers a custom cross-run aggregation function or value at [path].
void registerCustomAggregationMethod(String path, Object? function) {
  _customAggregationRegistry[path] = function;
}

/// Alias for [registerCustomAggregationMethod].
void registerCustomAggregationFunction(String path, Object? function) {
  registerCustomAggregationMethod(path, function);
}

/// Unregisters a previously registered custom aggregation method at [path].
void unregisterCustomAggregationMethod(String path) {
  _customAggregationRegistry.remove(path);
}

/// Alias for [unregisterCustomAggregationMethod].
void unregisterCustomAggregationFunction(String path) {
  unregisterCustomAggregationMethod(path);
}

/// Clears all registered custom cross-run aggregation methods.
void clearCustomAggregationMethods() {
  _customAggregationRegistry.clear();
}

class _CustomAggregationReturnTypeError extends Error
    implements TypeError, StateError {
  _CustomAggregationReturnTypeError(this.message);

  @override
  final String message;

  @override
  String toString() => 'TypeError: $message';
}

/// Loads a user-defined aggregation method from [config].
///
/// The function must be registered via [registerCustomAggregationMethod] using
/// `config.codeConfig.name` (in `"module.path.function_name"` format).
AggregationMethod loadCustomAggregationMethod(
  String name,
  CustomCrossRunMethodConfig config,
) {
  final String functionPath = config.codeConfig.name;
  if (!functionPath.contains('.')) {
    throw ArgumentError(
      'Invalid code_config.name for custom aggregation method "$name": '
      '"$functionPath". Expected "module.path.function_name".',
    );
  }

  if (!_customAggregationRegistry.containsKey(functionPath)) {
    throw ArgumentError(
      'Could not import custom aggregation method "$name" from $functionPath',
    );
  }

  final Object? fn = _customAggregationRegistry[functionPath];
  if (fn is! Function) {
    throw _CustomAggregationReturnTypeError(
      'Custom aggregation method "$name" ($functionPath) is not callable: $fn',
    );
  }

  double? wrapped(List<RunResult> runs) {
    final Object? result = Function.apply(fn, <Object?>[runs]);
    if (result == null) {
      return null;
    }
    if (result is bool || result is! num) {
      throw _CustomAggregationReturnTypeError(
        'Custom aggregation method "$name" returned ${result.runtimeType}, '
        'expected float or None.',
      );
    }
    final double value = result.toDouble();
    if (!value.isFinite) {
      return null;
    }
    return value;
  }

  return AggregationMethod(
    name: name,
    compute: wrapped,
    usesScores: config.usesScores,
    custom: true,
  );
}
