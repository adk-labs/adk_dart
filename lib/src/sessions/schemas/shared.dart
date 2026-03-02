/// Shared schema utilities for session storage versions.
library;

import 'dart:convert';

/// Default max key length used by storage schemas.
const int defaultMaxKeyLength = 128;

/// Default max varchar length used by storage schemas.
const int defaultMaxVarcharLength = 256;

/// Helpers for tolerant JSON encode/decode behavior.
class DynamicJson {
  const DynamicJson._();

  /// Decodes [value] when it is a JSON string, otherwise returns [value].
  static Object? decode(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
    return value;
  }

  /// Encodes [value] as a JSON string.
  static String encode(Object? value) => jsonEncode(value);
}

/// Utilities for preserving microsecond precision timestamps.
class PreciseTimestamp {
  const PreciseTimestamp._();

  /// Converts unix epoch [seconds] to a UTC [DateTime].
  static DateTime fromSeconds(num seconds) {
    return DateTime.fromMicrosecondsSinceEpoch(
      (seconds * 1000000).round(),
      isUtc: true,
    );
  }

  /// Converts [time] to unix epoch seconds with microsecond precision.
  static double toSeconds(DateTime time) {
    return time.toUtc().microsecondsSinceEpoch / 1000000;
  }
}
