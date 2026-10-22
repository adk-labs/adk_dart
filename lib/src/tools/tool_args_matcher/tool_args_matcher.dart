/// Extensible argument matching for tool call verification and simulation.
library;

import 'dart:math' as math;

import '../../features/_feature_registry.dart';

const Object _argMatchSentinel = Object();

/// Result of comparing a single tool call argument against an expected matcher.
class ArgMatchResult {
  /// Creates an argument match result.
  const ArgMatchResult({
    required this.matched,
    this.reason,
    this.argName,
    this.expected,
    this.actual,
    this.matcherType,
    double? score,
  }) : score = score ?? (matched ? 1.0 : 0.0);

  /// Whether the actual argument value satisfied the matcher.
  final bool matched;

  /// Optional explanation when [matched] is `false` (or additional context).
  final String? reason;

  /// Name of the tool argument that was evaluated, if known.
  final String? argName;

  /// Expected value or description configured on the matcher.
  final Object? expected;

  /// Actual value provided in the tool call.
  final Object? actual;

  /// Identifier of the matcher that produced this result.
  final String? matcherType;

  /// Match score in the range `0.0` to `1.0`.
  final double score;

  /// Returns a copy of this result with the specified fields replaced.
  ArgMatchResult copyWith({
    bool? matched,
    String? reason,
    String? argName,
    Object? expected = _argMatchSentinel,
    Object? actual = _argMatchSentinel,
    String? matcherType,
    double? score,
  }) {
    final bool nextMatched = matched ?? this.matched;
    return ArgMatchResult(
      matched: nextMatched,
      reason: reason ?? this.reason,
      argName: argName ?? this.argName,
      expected: identical(expected, _argMatchSentinel)
          ? this.expected
          : expected,
      actual: identical(actual, _argMatchSentinel) ? this.actual : actual,
      matcherType: matcherType ?? this.matcherType,
      score: score ?? (matched != null ? (nextMatched ? 1.0 : 0.0) : this.score),
    );
  }
}

/// Aggregated result of matching all arguments of a tool call.
class ToolArgsMatchResult {
  /// Creates an aggregated tool arguments match result.
  ToolArgsMatchResult({
    required this.matched,
    Map<String, ArgMatchResult>? results,
    List<String>? unexpectedArgs,
    List<String>? missingArgs,
    this.reason,
  }) : results = Map<String, ArgMatchResult>.unmodifiable(
         results ?? const <String, ArgMatchResult>{},
       ),
       unexpectedArgs = List<String>.unmodifiable(
         unexpectedArgs ?? const <String>[],
       ),
       missingArgs = List<String>.unmodifiable(missingArgs ?? const <String>[]);

  /// Whether all expected arguments matched and extra-argument rules passed.
  final bool matched;

  /// Per-argument match results keyed by argument name.
  final Map<String, ArgMatchResult> results;

  /// Alias for [results] matching Python `per_arg` naming.
  Map<String, ArgMatchResult> get perArg => results;

  /// Argument names present in the actual call that were not expected.
  final List<String> unexpectedArgs;

  /// Expected argument names that were absent from the actual call.
  final List<String> missingArgs;

  /// Optional human-readable summary when [matched] is `false`.
  final String? reason;

  /// Mean score across all evaluated arguments (`1.0` when none were expected).
  double get score {
    if (results.isEmpty) {
      return matched ? 1.0 : 0.0;
    }
    double total = 0.0;
    for (final ArgMatchResult result in results.values) {
      total += result.score;
    }
    return total / results.length;
  }
}

/// Base class for single-argument matchers used by [ToolArgsMatcher].
abstract class BaseArgMatcher {
  /// Creates a single-argument matcher.
  const BaseArgMatcher();

  /// Unique type identifier used when registering and deserializing matchers.
  String get type;

  /// Evaluates whether [actual] satisfies this matcher.
  ArgMatchResult match(Object? actual);
}

/// Matcher that checks deep equality between [expected] and the actual value.
class ExactArgMatcher extends BaseArgMatcher {
  /// Creates an exact matcher expecting [expected].
  const ExactArgMatcher(this.expected);

  /// Expected argument value.
  final Object? expected;

  @override
  String get type => 'exact';

  @override
  ArgMatchResult match(Object? actual) {
    final bool isMatch = _deepEquals(expected, actual);
    return ArgMatchResult(
      matched: isMatch,
      expected: expected,
      actual: actual,
      matcherType: type,
      reason: isMatch
          ? null
          : 'Expected exact value $expected, but got $actual.',
    );
  }
}

/// Matcher that compares string values case-insensitively with trimmed whitespace.
class CasefoldArgMatcher extends BaseArgMatcher {
  /// Creates a case-insensitive string matcher expecting [expected].
  const CasefoldArgMatcher(this.expected);

  /// Expected string value.
  final String expected;

  @override
  String get type => 'casefold';

  @override
  ArgMatchResult match(Object? actual) {
    if (actual is! String) {
      return ArgMatchResult(
        matched: false,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason:
            'Expected a String for casefold comparison, got ${actual.runtimeType}.',
      );
    }
    final bool isMatch =
        expected.trim().toLowerCase() == actual.trim().toLowerCase();
    return ArgMatchResult(
      matched: isMatch,
      expected: expected,
      actual: actual,
      matcherType: type,
      reason: isMatch
          ? null
          : 'Expected "$expected" (case-insensitive), got "$actual".',
    );
  }
}

/// Matcher that compares numeric values within relative and absolute tolerances.
class NumericArgMatcher extends BaseArgMatcher {
  /// Creates a numeric matcher for [expected] with [relTol] and [absTol].
  NumericArgMatcher(
    this.expected, {
    this.relTol = 1e-9,
    this.absTol = 0.0,
  }) {
    if (relTol < 0 || relTol.isNaN) {
      throw ArgumentError.value(
        relTol,
        'relTol',
        'Must be a non-negative number.',
      );
    }
    if (absTol < 0 || absTol.isNaN) {
      throw ArgumentError.value(
        absTol,
        'absTol',
        'Must be a non-negative number.',
      );
    }
  }

  /// Expected numeric value.
  final num expected;

  /// Relative tolerance for floating-point comparisons.
  final double relTol;

  /// Absolute tolerance for numeric comparisons.
  final double absTol;

  @override
  String get type => 'numeric';

  @override
  ArgMatchResult match(Object? actual) {
    if (actual is bool || actual is! num) {
      return ArgMatchResult(
        matched: false,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: 'Expected a numeric value, got ${actual.runtimeType}.',
      );
    }
    final double expectedDouble = expected.toDouble();
    final double actualDouble = actual.toDouble();
    if (expectedDouble.isNaN || actualDouble.isNaN) {
      return ArgMatchResult(
        matched: false,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: 'NaN values cannot match in NumericArgMatcher.',
      );
    }
    if (expectedDouble.isInfinite || actualDouble.isInfinite) {
      final bool isMatch = expectedDouble == actualDouble;
      return ArgMatchResult(
        matched: isMatch,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: isMatch
            ? null
            : 'Expected numeric value $expected, got $actual.',
      );
    }
    final double diff = (actualDouble - expectedDouble).abs();
    final double limit = math.max(
      relTol * math.max(expectedDouble.abs(), actualDouble.abs()),
      absTol,
    );
    final bool isMatch = diff <= limit;
    return ArgMatchResult(
      matched: isMatch,
      expected: expected,
      actual: actual,
      matcherType: type,
      reason: isMatch
          ? null
          : 'Numeric value $actual differs from $expected by $diff '
                '(allowed tolerance: $limit).',
    );
  }
}

/// Matcher that verifies an actual string or collection contains [expected].
class ContainsArgMatcher extends BaseArgMatcher {
  /// Creates a substring or element containment matcher for [expected].
  const ContainsArgMatcher(
    this.expected, {
    this.caseSensitive = true,
  });

  /// Expected substring or element.
  final Object? expected;

  /// Whether string containment checks are case-sensitive.
  final bool caseSensitive;

  @override
  String get type => 'contains';

  @override
  ArgMatchResult match(Object? actual) {
    if (actual is String && expected is String) {
      final String expectedStr = expected as String;
      final bool isMatch = caseSensitive
          ? actual.contains(expectedStr)
          : actual.toLowerCase().contains(expectedStr.toLowerCase());
      return ArgMatchResult(
        matched: isMatch,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: isMatch
            ? null
            : 'String "$actual" does not contain "$expectedStr".',
      );
    }
    if (actual is Iterable) {
      final bool isMatch = actual.any((Object? element) {
        if (!caseSensitive && element is String && expected is String) {
          return element.toLowerCase() == (expected as String).toLowerCase();
        }
        return _deepEquals(element, expected);
      });
      return ArgMatchResult(
        matched: isMatch,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: isMatch
            ? null
            : 'Collection $actual does not contain $expected.',
      );
    }
    if (actual is Map && expected is Map) {
      final Map<Object?, Object?> actualMap = actual;
      final Map<Object?, Object?> expectedMap = expected as Map<Object?, Object?>;
      final bool isMatch = expectedMap.entries.every(
        (MapEntry<Object?, Object?> entry) =>
            actualMap.containsKey(entry.key) &&
            _deepEquals(actualMap[entry.key], entry.value),
      );
      return ArgMatchResult(
        matched: isMatch,
        expected: expected,
        actual: actual,
        matcherType: type,
        reason: isMatch ? null : 'Map $actual does not contain $expected.',
      );
    }
    return ArgMatchResult(
      matched: false,
      expected: expected,
      actual: actual,
      matcherType: type,
      reason:
          'Cannot evaluate contains matcher for expected=${expected.runtimeType} '
          'and actual=${actual.runtimeType}.',
    );
  }
}

/// Matcher that accepts any value as long as the argument is present.
class IgnoreArgMatcher extends BaseArgMatcher {
  /// Creates a matcher that ignores the argument's value.
  const IgnoreArgMatcher();

  @override
  String get type => 'ignore';

  @override
  ArgMatchResult match(Object? actual) {
    return ArgMatchResult(
      matched: true,
      actual: actual,
      matcherType: type,
    );
  }
}

/// Factory function signature for building a [BaseArgMatcher] from a config map.
typedef ArgMatcherFactory =
    BaseArgMatcher Function(Map<String, Object?> config);

final Map<String, ArgMatcherFactory> _builtinMatcherRegistry =
    <String, ArgMatcherFactory>{
      'exact': (Map<String, Object?> config) {
        final Object? expected = config.containsKey('expected')
            ? config['expected']
            : config['value'];
        return ExactArgMatcher(expected);
      },
      'casefold': (Map<String, Object?> config) {
        final Object? raw = config.containsKey('expected')
            ? config['expected']
            : config['value'];
        if (raw is! String) {
          throw ArgumentError(
            'CasefoldArgMatcher requires a String "expected" field.',
          );
        }
        return CasefoldArgMatcher(raw);
      },
      'numeric': (Map<String, Object?> config) {
        final Object? raw = config.containsKey('expected')
            ? config['expected']
            : config['value'];
        if (raw is bool || raw is! num) {
          throw ArgumentError(
            'NumericArgMatcher requires a numeric "expected" field.',
          );
        }
        final Object? rawRelTol = config['relTol'] ?? config['rel_tol'];
        final Object? rawAbsTol =
            config['absTol'] ?? config['abs_tol'] ?? config['tolerance'];
        return NumericArgMatcher(
          raw,
          relTol: rawRelTol is num ? rawRelTol.toDouble() : 1e-9,
          absTol: rawAbsTol is num ? rawAbsTol.toDouble() : 0.0,
        );
      },
      'contains': (Map<String, Object?> config) {
        final Object? expected = config.containsKey('expected')
            ? config['expected']
            : config['value'];
        final Object? rawCaseSensitive =
            config['caseSensitive'] ?? config['case_sensitive'];
        return ContainsArgMatcher(
          expected,
          caseSensitive: rawCaseSensitive is bool ? rawCaseSensitive : true,
        );
      },
      'ignore': (Map<String, Object?> _) => const IgnoreArgMatcher(),
    };

final Map<String, ArgMatcherFactory> _customMatcherRegistry =
    <String, ArgMatcherFactory>{};

/// Registers a custom [BaseArgMatcher] [factory] under [type].
///
/// Throws an [ArgumentError] if [type] is empty.
void registerArgMatcher(
  String type,
  BaseArgMatcher Function(Map<String, Object?> config) factory,
) {
  final String normalized = type.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(type, 'type', 'Matcher type must not be empty.');
  }
  _customMatcherRegistry[normalized] = factory;
}

/// Clears custom registered argument matchers (intended for testing).
void resetCustomArgMatchers() {
  _customMatcherRegistry.clear();
}

/// Evaluates actual tool call arguments against per-argument [BaseArgMatcher]s.
///
/// ```dart
/// final matcher = ToolArgsMatcher(
///   expectedArgs: <String, Object?>{
///     'city': const CasefoldArgMatcher('San Francisco'),
///     'temperature': NumericArgMatcher(72.0, absTol: 0.5),
///     'request_id': const IgnoreArgMatcher(),
///   },
/// );
///
/// final result = matcher.match(<String, Object?>{
///   'city': 'san francisco',
///   'temperature': 72.2,
///   'request_id': 'req-123',
/// });
/// print(result.matched); // true
/// ```
class ToolArgsMatcher {
  /// Creates a [ToolArgsMatcher] from [expectedArgs] and [allowExtraArgs].
  ///
  /// Values in [expectedArgs] may be [BaseArgMatcher] instances or raw expected
  /// values (which are wrapped in [ExactArgMatcher]).
  ToolArgsMatcher({
    Map<String, Object?> expectedArgs = const <String, Object?>{},
    this.allowExtraArgs = false,
  }) : expectedArgs = Map<String, BaseArgMatcher>.unmodifiable(
         _coerceExpectedMatchers(expectedArgs),
       );

  /// Creates a [ToolArgsMatcher] from a configuration [mapping].
  ///
  /// Each entry in [mapping] can be a [BaseArgMatcher], a matcher config map
  /// containing a `'type'` key, or a literal value wrapped in [ExactArgMatcher].
  factory ToolArgsMatcher.fromMapping(
    Map<String, Object?> mapping, {
    bool allowExtraArgs = false,
  }) {
    return ToolArgsMatcher(
      expectedArgs: <String, Object?>{
        for (final MapEntry<String, Object?> entry in mapping.entries)
          entry.key: _parseMatcherSpec(entry.value),
      },
      allowExtraArgs: allowExtraArgs,
    );
  }

  /// Expected argument matchers keyed by argument name.
  final Map<String, BaseArgMatcher> expectedArgs;

  /// Whether arguments not present in [expectedArgs] are permitted.
  final bool allowExtraArgs;

  /// Matches [actualArgs] against [expectedArgs].
  ///
  /// Checks `isFeatureEnabled(FeatureName.toolArgsMatcher)` before evaluating
  /// and throws a [StateError] when the feature is disabled.
  ToolArgsMatchResult match(Map<String, Object?>? actualArgs) {
    _ensureToolArgsMatcherFeatureEnabled();

    final Map<String, Object?> actual =
        actualArgs ?? const <String, Object?>{};
    final Map<String, ArgMatchResult> results = <String, ArgMatchResult>{};
    final List<String> missingArgs = <String>[];
    final List<String> failureReasons = <String>[];

    for (final MapEntry<String, BaseArgMatcher> entry in expectedArgs.entries) {
      final String argName = entry.key;
      final BaseArgMatcher matcher = entry.value;
      if (!actual.containsKey(argName)) {
        missingArgs.add(argName);
        final ArgMatchResult missingResult = ArgMatchResult(
          matched: false,
          argName: argName,
          expected: _extractExpectedValue(matcher),
          actual: null,
          matcherType: matcher.type,
          reason: 'Missing expected argument "$argName".',
        );
        results[argName] = missingResult;
        failureReasons.add(missingResult.reason!);
        continue;
      }

      final Object? actualValue = actual[argName];
      final ArgMatchResult rawResult = matcher.match(actualValue);
      final ArgMatchResult normalizedResult = rawResult.copyWith(
        argName: rawResult.argName ?? argName,
        matcherType: rawResult.matcherType ?? matcher.type,
      );
      results[argName] = normalizedResult;
      if (!normalizedResult.matched) {
        failureReasons.add(
          normalizedResult.reason ?? 'Argument "$argName" did not match.',
        );
      }
    }

    final List<String> unexpectedArgs = <String>[
      for (final String key in actual.keys)
        if (!expectedArgs.containsKey(key)) key,
    ];
    if (!allowExtraArgs && unexpectedArgs.isNotEmpty) {
      failureReasons.add(
        'Unexpected arguments: ${unexpectedArgs.join(', ')}.',
      );
    }

    final bool allExpectedMatched =
        missingArgs.isEmpty &&
        results.values.every((ArgMatchResult r) => r.matched);
    final bool extraOk = allowExtraArgs || unexpectedArgs.isEmpty;
    final bool matched = allExpectedMatched && extraOk;

    return ToolArgsMatchResult(
      matched: matched,
      results: results,
      unexpectedArgs: unexpectedArgs,
      missingArgs: missingArgs,
      reason: matched ? null : failureReasons.join(' '),
    );
  }
}

void _ensureToolArgsMatcherFeatureEnabled() {
  for (final FeatureName feature in FeatureName.values) {
    if (feature.value == 'TOOL_ARGS_MATCHER' ||
        feature.name == 'toolArgsMatcher') {
      if (!isFeatureEnabled(feature)) {
        throw StateError(
          'Feature $feature (${feature.value}) is not enabled.',
        );
      }
      return;
    }
  }
}

Map<String, BaseArgMatcher> _coerceExpectedMatchers(
  Map<String, Object?> rawExpected,
) {
  final Map<String, BaseArgMatcher> coerced = <String, BaseArgMatcher>{};
  for (final MapEntry<String, Object?> entry in rawExpected.entries) {
    final Object? value = entry.value;
    if (value is BaseArgMatcher) {
      coerced[entry.key] = value;
    } else {
      coerced[entry.key] = ExactArgMatcher(value);
    }
  }
  return coerced;
}

BaseArgMatcher _parseMatcherSpec(Object? spec) {
  if (spec is BaseArgMatcher) {
    return spec;
  }
  if (spec is Map) {
    final Map<String, Object?> map = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in spec.entries)
        '${entry.key}': entry.value,
    };
    if (map.containsKey('type')) {
      final Object? rawType = map['type'];
      if (rawType is! String || rawType.trim().isEmpty) {
        throw ArgumentError('Matcher config "type" must be a non-empty String.');
      }
      final String matcherType = rawType.trim();
      final ArgMatcherFactory? factory =
          _customMatcherRegistry[matcherType] ??
          _builtinMatcherRegistry[matcherType];
      if (factory == null) {
        throw ArgumentError('Unknown argument matcher type "$matcherType".');
      }
      return factory(map);
    }
  }
  return ExactArgMatcher(spec);
}

Object? _extractExpectedValue(BaseArgMatcher matcher) {
  if (matcher is ExactArgMatcher) return matcher.expected;
  if (matcher is CasefoldArgMatcher) return matcher.expected;
  if (matcher is NumericArgMatcher) return matcher.expected;
  if (matcher is ContainsArgMatcher) return matcher.expected;
  return null;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<Object?, Object?> entry in a.entries) {
      if (!b.containsKey(entry.key)) {
        return false;
      }
      if (!_deepEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) {
      return false;
    }
    return a.containsAll(b);
  }
  return a == b;
}
