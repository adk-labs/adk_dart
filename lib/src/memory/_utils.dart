/// Shared helpers for memory service serialization and formatting.
library;

/// The ISO-8601 timestamp string converted from UNIX seconds [timestamp].
String formatTimestamp(num timestamp) {
  final int milliseconds = (timestamp * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(milliseconds).toIso8601String();
}
