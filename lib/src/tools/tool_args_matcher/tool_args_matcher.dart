/// Pluggable argument matchers for comparing expected and actual tool call arguments.
library;

import 'dart:async';

import '../../features/_feature_registry.dart';
import 'semantic_arg_matcher.dart';

export 'semantic_arg_matcher.dart';

/// Result of matching a single argument value.
class ArgMatchResult {
  /// Creates an argument match result.
  const ArgMatchResult({
    required this.matched,
    double? score,
    this.expected,
    this.actual,
    this.matcherType = 'exact',
    this.reason,
  }) : score = score ?? (matched ? 1.0 : 0.0),
       assert(
         (score ?? (matched ? 1.0 : 0.0)) >= 0.0 &&
             (score ?? (matched ? 1.0 : 0.0)) <= 1.0,
         'score must be between 0.0 and 1.0.',
      );

  /// Creates an [ArgMatchResult] from a JSON map.
  factory ArgMatchResult.fromJson(Map<String, Object?> json) {
    final Object? rawMatched = json['matched'];
    final bool matched = switch (rawMatched) {
      bool() => rawMatched,
      String() => rawMatched.trim().toLowerCase() == 'true',
      _ => false,
    };
    final Object? rawScore = json['score'];
    final double? score = rawScore is num && rawScore is! bool
        ? rawScore.toDouble()
        : null;
    if (score != null && (score.isNaN || score < 0.0 || score > 1.0)) {
      throw ArgumentError.value(
        score,
        'score',
        'score must be between 0.0 and 1.0.',
      );
    }
    return ArgMatchResult(
      matched: matched,
      score: score,
      expected: json['expected'],
      actual: json['actual'],
      matcherType: '${json['matcher_type'] ?? json['matcherType'] ?? 'exact'}',
      reason: json['reason'] as String?,
    );
  }

  /// Whether the argument matched.
  final bool matched;

  /// How well the actual value matches, from `0.0` to `1.0`.
  ///
  /// Defaults to `1.0` when [matched] is `true` and `0.0` otherwise.
  final double score;

  /// Expected value or pattern.
  final Object? expected;

  /// Actual value provided in the tool call.
  final Object? actual;

  /// Matcher type identifier.
  final String matcherType;

  /// Optional explanation when [matched] is `false` (or from a semantic judge).
  final String? reason;

  /// Returns a copy of this result with selectively replaced fields.
  ArgMatchResult copyWith({
    bool? matched,
    double? score,
    Object? expected,
    Object? actual,
    String? matcherType,
    String? reason,
  }) {
    return ArgMatchResult(
      matched: matched ?? this.matched,
      score: score ?? this.score,
      expected: expected ?? this.expected,
      actual: actual ?? this.actual,
      matcherType: matcherType ?? this.matcherType,
      reason: reason ?? this.reason,
    );
  }

  /// Serializes this result to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'matched': matched,
    'score': score,
    'expected': expected,
    'actual': actual,
    'matcher_type': matcherType,
    if (reason != null) 'reason': reason,
  };
}

/// Result of matching a full map of tool call arguments.
class ToolArgsMatchResult {
  /// Creates a tool arguments match result.
  const ToolArgsMatchResult({
    required this.matched,
    double? score,
    Map<String, ArgMatchResult>? argResults,
    Map<String, ArgMatchResult>? perArg,
    this.missingArgs = const <String>[],
    this.unexpectedArgs = const <String>[],
  }) : argResults = perArg ?? argResults ?? const <String, ArgMatchResult>{},
       score = score ?? (matched ? 1.0 : 0.0);

  /// Whether all arguments matched.
  final bool matched;

  /// Mean score of the arguments that were compared (`0.0` to `1.0`).
  final double score;

  /// Per-argument match results.
  final Map<String, ArgMatchResult> argResults;

  /// Alias for [argResults] matching the upstream `per_arg` field name.
  Map<String, ArgMatchResult> get perArg => argResults;

  /// Expected argument keys that were missing from actual arguments.
  final List<String> missingArgs;

  /// Unexpected argument keys present when `allowExtraArgs` is `false`.
  final List<String> unexpectedArgs;

  /// Serializes this result to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'matched': matched,
    'score': score,
    'per_arg': argResults.map(
      (String k, ArgMatchResult v) => MapEntry<String, Object?>(k, v.toJson()),
    ),
    'arg_results': argResults.map(
      (String k, ArgMatchResult v) => MapEntry<String, Object?>(k, v.toJson()),
    ),
    if (missingArgs.isNotEmpty) 'missing_args': missingArgs,
    if (unexpectedArgs.isNotEmpty) 'unexpected_args': unexpectedArgs,
  };
}

/// Abstract base class for single-argument matchers.
abstract class BaseArgMatcher {
  /// Creates a base argument matcher.
  const BaseArgMatcher();

  /// Unique matcher type discriminator.
  String get type;

  /// Whether this matcher returns the same result deterministically without remote/LLM calls.
  bool get isDeterministic => true;

  /// Evaluates whether [actual] satisfies this matcher synchronously.
  ArgMatchResult match(Object? actual);

  /// Evaluates whether [actual] satisfies [expected] asynchronously.
  ///
  /// Deterministic matchers delegate to [match] by default.
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return match(actual);
  }

  /// Serializes this matcher configuration to JSON.
  Map<String, Object?> toJson() => <String, Object?>{'type': type};
}

/// Factory signature for constructing a [BaseArgMatcher] from a JSON map.
typedef ArgMatcherFactory =
    BaseArgMatcher Function(Map<String, Object?> config);

const Set<String> _reservedArgMatcherTypes = <String>{
  'exact',
  'casefold',
  'numeric',
  'contains',
  'ignore',
  'semantic',
};

final Map<String, ArgMatcherFactory> _customArgMatchers =
    <String, ArgMatcherFactory>{};

/// Registers a custom [BaseArgMatcher] factory for [type].
///
/// Built-in matcher names (`exact`, `casefold`, `numeric`, `contains`,
/// `ignore`, `semantic`) are reserved and cannot be overridden.
void registerArgMatcher(String type, ArgMatcherFactory factory) {
  final String normalized = type.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(type, 'type', 'Matcher type must not be empty.');
  }
  if (_reservedArgMatcherTypes.contains(normalized.toLowerCase())) {
    throw ArgumentError.value(
      type,
      'type',
      'Arg matcher type "$normalized" is reserved for matchers that ship with ADK.',
    );
  }
  _customArgMatchers[normalized] = factory;
}

/// Clears custom registered argument matchers (used in tests).
void resetCustomArgMatchers() {
  _customArgMatchers.clear();
}

/// Exact equality argument matcher.
class ExactArgMatcher extends BaseArgMatcher {
  /// Creates an exact equality matcher.
  const ExactArgMatcher([this.expected]);

  /// Expected value when configured directly on the matcher.
  final Object? expected;

  @override
  String get type => 'exact';

  @override
  ArgMatchResult match(Object? actual) {
    return _matchWithExpected(expected, actual);
  }

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return _matchWithExpected(expected ?? this.expected, actual);
  }

  ArgMatchResult _matchWithExpected(Object? expectedValue, Object? actual) {
    final bool ok = deepArgEquals(expectedValue, actual);
    return ArgMatchResult(
      matched: ok,
      expected: expectedValue,
      actual: actual,
      matcherType: type,
      reason: ok ? null : 'Expected $expectedValue, got $actual.',
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (expected != null) 'expected': expected,
  };
}

/// Case-insensitive string equality matcher (trims surrounding whitespace).
class CasefoldArgMatcher extends BaseArgMatcher {
  /// Creates a case-insensitive string matcher.
  const CasefoldArgMatcher([this.expected = '']);

  /// Expected string value when configured on the matcher.
  final Object? expected;

  @override
  String get type => 'casefold';

  @override
  ArgMatchResult match(Object? actual) {
    return _matchWithExpected(expected, actual);
  }

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return _matchWithExpected(expected ?? this.expected, actual);
  }

  ArgMatchResult _matchWithExpected(Object? expectedValue, Object? actual) {
    if (expectedValue is String && actual is String) {
      final bool ok =
          expectedValue.trim().toLowerCase() == actual.trim().toLowerCase();
      return ArgMatchResult(
        matched: ok,
        expected: expectedValue,
        actual: actual,
        matcherType: type,
        reason: ok
            ? null
            : 'Expected "$expectedValue" (case-insensitive), got "$actual".',
      );
    }
    final bool ok = deepArgEquals(expectedValue, actual);
    return ArgMatchResult(
      matched: ok,
      expected: expectedValue,
      actual: actual,
      matcherType: type,
      reason: ok ? null : 'Expected $expectedValue, got $actual.',
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (expected != null) 'expected': expected,
  };
}

/// Numeric matcher with configurable tolerance.
class NumericArgMatcher extends BaseArgMatcher {
  /// Creates a numeric matcher.
  NumericArgMatcher({
    this.expected,
    double? tolerance,
    double? absTol,
    this.relTol = 0.0,
  }) : absTol = tolerance ?? absTol ?? 0.0 {
    if (this.absTol < 0.0 || this.absTol.isNaN) {
      throw ArgumentError.value(
        this.absTol,
        'tolerance',
        'tolerance must be non-negative.',
      );
    }
  }

  /// Expected numeric value when configured directly on the matcher.
  final num? expected;

  /// Absolute tolerance.
  final double absTol;

  /// Alias for [absTol] matching upstream `tolerance`.
  double get tolerance => absTol;

  /// Relative tolerance.
  final double relTol;

  @override
  String get type => 'numeric';

  @override
  ArgMatchResult match(Object? actual) {
    return _matchWithExpected(expected, actual);
  }

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return _matchWithExpected(expected ?? this.expected, actual);
  }

  ArgMatchResult _matchWithExpected(Object? expectedValue, Object? actual) {
    if (expectedValue is! num ||
        expectedValue is bool ||
        actual is! num ||
        actual is bool) {
      return ArgMatchResult(
        matched: false,
        expected: expectedValue,
        actual: actual,
        matcherType: type,
        reason:
            'Both values must be numbers, got ${expectedValue.runtimeType} and ${actual.runtimeType}.',
      );
    }
    final double diff = (actual.toDouble() - expectedValue.toDouble()).abs();
    final double relThreshold = relTol * expectedValue.toDouble().abs();
    final double threshold = absTol >= relThreshold ? absTol : relThreshold;
    final bool ok = diff <= threshold;
    return ArgMatchResult(
      matched: ok,
      expected: expectedValue,
      actual: actual,
      matcherType: type,
      reason: ok
          ? null
          : 'Numeric difference $diff exceeds tolerance $threshold.',
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (expected != null) 'expected': expected,
    'tolerance': absTol,
    'abs_tol': absTol,
    'rel_tol': relTol,
  };
}

/// Substring or collection element containment matcher.
class ContainsArgMatcher extends BaseArgMatcher {
  /// Creates a containment matcher.
  const ContainsArgMatcher(this.expected, {this.caseSensitive = true});

  /// Expected substring or element when configured on the matcher.
  final Object? expected;

  /// Whether string containment is case-sensitive.
  final bool caseSensitive;

  @override
  String get type => 'contains';

  @override
  ArgMatchResult match(Object? actual) {
    return _matchWithExpected(expected, actual);
  }

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return _matchWithExpected(expected ?? this.expected, actual);
  }

  ArgMatchResult _matchWithExpected(Object? expectedValue, Object? actual) {
    if (actual is String && expectedValue is String) {
      final bool ok = caseSensitive
          ? actual.contains(expectedValue)
          : actual.toLowerCase().contains(expectedValue.toLowerCase());
      return ArgMatchResult(
        matched: ok,
        expected: expectedValue,
        actual: actual,
        matcherType: type,
        reason: ok
            ? null
            : 'String "$actual" does not contain "$expectedValue".',
      );
    }
    if (actual is Iterable && expectedValue is! Iterable) {
      final bool ok = actual.any(
        (Object? item) => deepArgEquals(item, expectedValue),
      );
      return ArgMatchResult(
        matched: ok,
        expected: expectedValue,
        actual: actual,
        matcherType: type,
        reason: ok ? null : 'Iterable does not contain $expectedValue.',
      );
    }
    final bool ok = deepArgEquals(expectedValue, actual);
    return ArgMatchResult(
      matched: ok,
      expected: expectedValue,
      actual: actual,
      matcherType: type,
      reason: ok ? null : 'Expected $expectedValue, got $actual.',
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    if (expected != null) 'expected': expected,
    'case_sensitive': caseSensitive,
  };
}

/// Wildcard matcher that ignores the argument value and always succeeds.
class IgnoreArgMatcher extends BaseArgMatcher {
  /// Creates an ignore matcher.
  const IgnoreArgMatcher();

  @override
  String get type => 'ignore';

  @override
  ArgMatchResult match(Object? actual) {
    return ArgMatchResult(
      matched: true,
      expected: '*',
      actual: actual,
      matcherType: type,
    );
  }

  @override
  Future<ArgMatchResult> matchAsync({
    String toolName = '',
    String argName = '',
    Object? expected,
    required Object? actual,
  }) async {
    return ArgMatchResult(
      matched: true,
      expected: expected ?? '*',
      actual: actual,
      matcherType: type,
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{'type': type};
}

/// Matches a dictionary of tool call arguments against configured matchers.
class ToolArgsMatcher {
  /// Creates a [ToolArgsMatcher].
  ///
  /// Supports both per-argument expected matchers ([expectedArgs]) and
  /// upstream-style [defaultMatcher] + [perArgMatchers].
  ToolArgsMatcher({
    Map<String, BaseArgMatcher>? expectedArgs,
    BaseArgMatcher? defaultMatcher,
    Map<String, BaseArgMatcher>? perArgMatchers,
    bool? allowExtraArgs,
  }) : defaultMatcher = defaultMatcher ?? const ExactArgMatcher(),
       perArgMatchers = Map<String, BaseArgMatcher>.unmodifiable(
         perArgMatchers ?? expectedArgs ?? const <String, BaseArgMatcher>{},
       ),
       expectedArgs = Map<String, BaseArgMatcher>.unmodifiable(
         expectedArgs ?? perArgMatchers ?? const <String, BaseArgMatcher>{},
       ),
       allowExtraArgs = allowExtraArgs ?? (expectedArgs == null);

  /// Creates a [ToolArgsMatcher] from a JSON/YAML config map.
  factory ToolArgsMatcher.fromJson(Map<String, Object?> json) {
    const Set<String> schemaKeys = <String>{
      'defaultMatcher',
      'default_matcher',
      'perArgMatchers',
      'per_arg_matchers',
      'allowExtraArgs',
      'allow_extra_args',
    };
    if (json.keys.any(schemaKeys.contains)) {
      for (final String key in json.keys) {
        if (!schemaKeys.contains(key)) {
          throw ArgumentError.value(
            key,
            'json',
            'Unexpected field `$key` in ToolArgsMatcher config.',
          );
        }
      }
      final Object? rawDefault =
          json['defaultMatcher'] ?? json['default_matcher'];
      final BaseArgMatcher defaultMatcher = rawDefault == null
          ? const ExactArgMatcher()
          : _coerceArgMatcher(rawDefault);
      final Object? rawPerArg =
          json['perArgMatchers'] ?? json['per_arg_matchers'];
      final Map<String, BaseArgMatcher> perArg = <String, BaseArgMatcher>{};
      if (rawPerArg is Map) {
        for (final MapEntry<Object?, Object?> entry in rawPerArg.entries) {
          perArg['${entry.key}'] = _coerceArgMatcher(entry.value);
        }
      } else if (rawPerArg != null) {
        throw ArgumentError.value(
          rawPerArg,
          'perArgMatchers',
          '`perArgMatchers` must be a mapping.',
        );
      }
      final Object? rawAllowExtra =
          json['allowExtraArgs'] ?? json['allow_extra_args'];
      final bool allowExtraArgs = rawAllowExtra is bool ? rawAllowExtra : true;
      return ToolArgsMatcher(
        defaultMatcher: defaultMatcher,
        perArgMatchers: perArg,
        allowExtraArgs: allowExtraArgs,
      );
    }
    return ToolArgsMatcher.fromMapping(json);
  }

  /// Creates a [ToolArgsMatcher] from a raw mapping of argument names to
  /// matcher specs or literal expected values.
  factory ToolArgsMatcher.fromMapping(
    Map<String, Object?> mapping, {
    bool allowExtraArgs = false,
  }) {
    final Map<String, BaseArgMatcher> matchers = <String, BaseArgMatcher>{};
    for (final MapEntry<String, Object?> entry in mapping.entries) {
      final Object? spec = entry.value;
      if (spec is BaseArgMatcher) {
        matchers[entry.key] = spec;
      } else if (spec is Map) {
        final Map<String, Object?> config = spec.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        );
        if (config.containsKey('type')) {
          matchers[entry.key] = _buildArgMatcherFromConfig(config);
        } else {
          matchers[entry.key] = ExactArgMatcher(spec);
        }
      } else {
        matchers[entry.key] = ExactArgMatcher(spec);
      }
    }
    return ToolArgsMatcher(
      expectedArgs: matchers,
      allowExtraArgs: allowExtraArgs,
    );
  }

  /// The matcher used for expected arguments not listed in [perArgMatchers].
  final BaseArgMatcher defaultMatcher;

  /// Matchers keyed by argument name, overriding [defaultMatcher].
  final Map<String, BaseArgMatcher> perArgMatchers;

  /// Expected matchers keyed by argument name (alias for [perArgMatchers]).
  final Map<String, BaseArgMatcher> expectedArgs;

  /// Whether extra arguments not in expected arguments are permitted.
  final bool allowExtraArgs;

  /// Evaluates [actualArgs] synchronously against [expected] (or [expectedArgs]).
  ToolArgsMatchResult match(
    Map<String, Object?> actualArgs, {
    String toolName = '',
    Map<String, Object?>? expected,
    bool shortCircuit = false,
  }) {
    isFeatureEnabled(FeatureName.toolArgsMatcher);
    if (expected != null) {
      return _matchWithExpectedSync(
        toolName: toolName,
        expected: expected,
        actual: actualArgs,
        shortCircuit: shortCircuit,
      );
    }

    final Map<String, ArgMatchResult> results = <String, ArgMatchResult>{};
    final List<String> missingArgs = <String>[];
    final List<String> unexpectedArgs = <String>[];

    for (final MapEntry<String, BaseArgMatcher> entry in expectedArgs.entries) {
      final String key = entry.key;
      final BaseArgMatcher matcher = entry.value;
      if (!actualArgs.containsKey(key)) {
        if (matcher is IgnoreArgMatcher) {
          results[key] = matcher.match(null);
        } else {
          missingArgs.add(key);
          results[key] = ArgMatchResult(
            matched: false,
            expected: matcher.toJson()['expected'],
            actual: null,
            matcherType: matcher.type,
            reason: 'The argument is missing from the call.',
          );
        }
        continue;
      }
      results[key] = matcher.match(actualArgs[key]);
    }

    if (!allowExtraArgs) {
      for (final String key in actualArgs.keys) {
        if (!expectedArgs.containsKey(key)) {
          unexpectedArgs.add(key);
        }
      }
    }

    final bool allMatched =
        missingArgs.isEmpty &&
        unexpectedArgs.isEmpty &&
        results.values.every((ArgMatchResult r) => r.matched);

    final double score = results.isNotEmpty
        ? results.values.fold<double>(
                0.0,
                (double sum, ArgMatchResult r) => sum + r.score,
              ) /
              results.length
        : (expectedArgs.isEmpty ? 1.0 : 0.0);

    return ToolArgsMatchResult(
      matched: allMatched,
      score: score,
      argResults: results,
      missingArgs: missingArgs,
      unexpectedArgs: unexpectedArgs,
    );
  }

  ToolArgsMatchResult _matchWithExpectedSync({
    required String toolName,
    required Map<String, Object?> expected,
    required Map<String, Object?> actual,
    required bool shortCircuit,
  }) {
    final List<String> unexpectedArgs = <String>[];
    if (!allowExtraArgs) {
      for (final String argName in actual.keys) {
        if (!expected.containsKey(argName)) {
          unexpectedArgs.add(argName);
        }
      }
    }
    final bool extraArgsOk = unexpectedArgs.isEmpty;
    final Map<String, ArgMatchResult> results = <String, ArgMatchResult>{};
    final List<String> missingArgs = <String>[];
    final List<(String, BaseArgMatcher)> deferred =
        <(String, BaseArgMatcher)>[];

    for (final MapEntry<String, Object?> entry in expected.entries) {
      final String argName = entry.key;
      if (!actual.containsKey(argName)) {
        missingArgs.add(argName);
        results[argName] = const ArgMatchResult(
          matched: false,
          reason: 'The argument is missing from the call.',
        );
        continue;
      }
      final BaseArgMatcher matcher = perArgMatchers[argName] ?? defaultMatcher;
      if (!matcher.isDeterministic) {
        deferred.add((argName, matcher));
        continue;
      }
      results[argName] = _matchDeterministic(
        matcher,
        expected: entry.value,
        actual: actual[argName],
      );
    }

    final bool decided =
        !extraArgsOk ||
        results.values.any((ArgMatchResult result) => !result.matched);
    if (deferred.isNotEmpty && !(shortCircuit && decided)) {
      for (final (String argName, BaseArgMatcher matcher) in deferred) {
        results[argName] = matcher.match(actual[argName]);
      }
    }

    final Map<String, ArgMatchResult> perArg = <String, ArgMatchResult>{
      for (final String argName in expected.keys)
        if (results.containsKey(argName)) argName: results[argName]!,
    };
    final bool matched =
        extraArgsOk &&
        perArg.values.every((ArgMatchResult result) => result.matched);
    final double score;
    if (perArg.isNotEmpty) {
      score =
          perArg.values.fold<double>(
            0.0,
            (double sum, ArgMatchResult r) => sum + r.score,
          ) /
          perArg.length;
    } else if (expected.isEmpty) {
      score = 1.0;
    } else {
      score = 0.0;
    }
    return ToolArgsMatchResult(
      matched: matched,
      score: score,
      perArg: perArg,
      missingArgs: missingArgs,
      unexpectedArgs: unexpectedArgs,
    );
  }

  /// Compares the [actual] arguments of a tool call with the [expected] ones asynchronously.
  ///
  /// Deterministic matchers run first in order. Non-deterministic matchers
  /// (such as [SemanticArgMatcher]) run concurrently afterwards unless
  /// [shortCircuit] is `true` and a mismatch or disallowed extra argument has
  /// already decided `matched`.
  Future<ToolArgsMatchResult> matchAsync({
    String toolName = '',
    Map<String, Object?>? expected,
    required Map<String, Object?> actual,
    bool shortCircuit = false,
  }) async {
    isFeatureEnabled(FeatureName.toolArgsMatcher);
    final Map<String, Object?> effectiveExpected =
        expected ??
        <String, Object?>{
          for (final MapEntry<String, BaseArgMatcher> e in expectedArgs.entries)
            e.key: e.value.toJson()['expected'],
        };

    final List<String> unexpectedArgs = <String>[];
    if (!allowExtraArgs) {
      for (final String argName in actual.keys) {
        if (!effectiveExpected.containsKey(argName)) {
          unexpectedArgs.add(argName);
        }
      }
    }
    final bool extraArgsOk = unexpectedArgs.isEmpty;
    final Map<String, ArgMatchResult> results = <String, ArgMatchResult>{};
    final List<String> missingArgs = <String>[];
    final List<(String, BaseArgMatcher)> deferred =
        <(String, BaseArgMatcher)>[];

    for (final MapEntry<String, Object?> entry in effectiveExpected.entries) {
      final String argName = entry.key;
      final Object? expectedValue = entry.value;
      if (!actual.containsKey(argName)) {
        missingArgs.add(argName);
        results[argName] = const ArgMatchResult(
          matched: false,
          reason: 'The argument is missing from the call.',
        );
        continue;
      }
      final BaseArgMatcher matcher = perArgMatchers[argName] ?? defaultMatcher;
      if (!matcher.isDeterministic) {
        deferred.add((argName, matcher));
        continue;
      }
      results[argName] = await matcher.matchAsync(
        toolName: toolName,
        argName: argName,
        expected: expectedValue,
        actual: actual[argName],
      );
    }

    final bool decided =
        !extraArgsOk ||
        results.values.any((ArgMatchResult result) => !result.matched);
    if (deferred.isNotEmpty && !(shortCircuit && decided)) {
      final List<Future<ArgMatchResult>> tasks = <Future<ArgMatchResult>>[
        for (final (String argName, BaseArgMatcher matcher) in deferred)
          matcher.matchAsync(
            toolName: toolName,
            argName: argName,
            expected: effectiveExpected[argName],
            actual: actual[argName],
          ),
      ];
      final List<ArgMatchResult> deferredResults = await Future.wait(tasks);
      for (int i = 0; i < deferred.length; i += 1) {
        results[deferred[i].$1] = deferredResults[i];
      }
    }

    final Map<String, ArgMatchResult> perArg = <String, ArgMatchResult>{
      for (final String argName in effectiveExpected.keys)
        if (results.containsKey(argName)) argName: results[argName]!,
    };
    final bool matched =
        extraArgsOk &&
        perArg.values.every((ArgMatchResult result) => result.matched);
    final double score;
    if (perArg.isNotEmpty) {
      score =
          perArg.values.fold<double>(
            0.0,
            (double sum, ArgMatchResult r) => sum + r.score,
          ) /
          perArg.length;
    } else if (effectiveExpected.isEmpty) {
      score = 1.0;
    } else {
      score = 0.0;
    }
    return ToolArgsMatchResult(
      matched: matched,
      score: score,
      perArg: perArg,
      missingArgs: missingArgs,
      unexpectedArgs: unexpectedArgs,
    );
  }

  ArgMatchResult _matchDeterministic(
    BaseArgMatcher matcher, {
    required Object? expected,
    required Object? actual,
  }) {
    if (matcher is ExactArgMatcher) {
      return matcher._matchWithExpected(expected ?? matcher.expected, actual);
    }
    if (matcher is CasefoldArgMatcher) {
      return matcher._matchWithExpected(expected ?? matcher.expected, actual);
    }
    if (matcher is NumericArgMatcher) {
      return matcher._matchWithExpected(expected ?? matcher.expected, actual);
    }
    if (matcher is ContainsArgMatcher) {
      return matcher._matchWithExpected(expected ?? matcher.expected, actual);
    }
    if (matcher is IgnoreArgMatcher) {
      return matcher.match(actual);
    }
    return matcher.match(actual);
  }
}

BaseArgMatcher _coerceArgMatcher(Object? value) {
  if (value is BaseArgMatcher) {
    return value;
  }
  if (value is Map) {
    return _buildArgMatcherFromConfig(
      value.map(
        (Object? key, Object? item) => MapEntry<String, Object?>('$key', item),
      ),
    );
  }
  throw ArgumentError.value(
    value,
    'value',
    'Expected a BaseArgMatcher or config map, got ${value.runtimeType}.',
  );
}

BaseArgMatcher _buildArgMatcherFromConfig(Map<String, Object?> config) {
  final Object? rawType = config['type'];
  final String type = rawType is String ? rawType.trim() : '';
  switch (type) {
    case 'exact':
      return ExactArgMatcher(config['expected'] ?? config['value']);
    case 'casefold':
      return CasefoldArgMatcher(config['expected'] ?? config['value']);
    case 'numeric':
      final Object? rawExpected = config['expected'] ?? config['value'];
      final Object? rawTolerance =
          config['tolerance'] ?? config['abs_tol'] ?? config['absTol'];
      final double tolerance = rawTolerance is num && rawTolerance is! bool
          ? rawTolerance.toDouble()
          : 0.0;
      final Object? rawRelTol = config['rel_tol'] ?? config['relTol'];
      final double relTol = rawRelTol is num && rawRelTol is! bool
          ? rawRelTol.toDouble()
          : 0.0;
      return NumericArgMatcher(
        expected: rawExpected is num && rawExpected is! bool
            ? rawExpected
            : null,
        tolerance: tolerance,
        relTol: relTol,
      );
    case 'contains':
      return ContainsArgMatcher(
        config['expected'] ?? config['value'],
        caseSensitive:
            (config['case_sensitive'] ?? config['caseSensitive']) != false,
      );
    case 'ignore':
      return const IgnoreArgMatcher();
    case 'semantic':
      return SemanticArgMatcher.fromConfig(config);
    default:
      final ArgMatcherFactory? custom = _customArgMatchers[type];
      if (custom != null) {
        return custom(config);
      }
      final List<String> registered = <String>[
        ..._reservedArgMatcherTypes,
        ..._customArgMatchers.keys,
      ]..sort();
      throw ArgumentError.value(
        type,
        'type',
        'Unknown arg matcher type "$type". Registered types: $registered.',
      );
  }
}

/// Deep equality check for tool argument values (maps, lists, numbers, primitives).
bool deepArgEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is num && b is num && a is! bool && b is! bool) {
    return a == b;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (!deepArgEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final Object? key in a.keys) {
      if (!b.containsKey(key) || !deepArgEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
