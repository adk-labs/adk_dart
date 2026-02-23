String formatTimestamp(num timestamp) {
  final int milliseconds = (timestamp * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(milliseconds).toIso8601String();
}
