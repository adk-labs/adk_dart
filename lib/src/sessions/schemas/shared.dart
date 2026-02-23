import 'dart:convert';

const int defaultMaxKeyLength = 128;
const int defaultMaxVarcharLength = 256;

class DynamicJson {
  const DynamicJson._();

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

  static String encode(Object? value) => jsonEncode(value);
}

class PreciseTimestamp {
  const PreciseTimestamp._();

  static DateTime fromSeconds(num seconds) {
    return DateTime.fromMicrosecondsSinceEpoch(
      (seconds * 1000000).round(),
      isUtc: true,
    );
  }

  static double toSeconds(DateTime time) {
    return time.toUtc().microsecondsSinceEpoch / 1000000;
  }
}
